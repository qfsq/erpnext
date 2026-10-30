#!/bin/bash
# ============================================================
# 修复「前端资源未构建」问题
#
# 现象：erpnext_china 已经安装成功，但 bench build 报
#       ValueError: Invalid version string: 'bin/sh: 1: node: not found'
#       -> /assets/erpnext_china/... 404
#       -> 中文包的 business.bundle.css / erpnext_china.bundle.js 不生效
#
# 原因：erp_backend 容器内 node 不在 PATH 中（镜像用 nvm 装 node，
#       非登录 shell 不会加载 nvm），bench build 中途失败。
#
# 对策：方案 A 动态定位 node 后重跑 bench build（首选）
#       方案 B 从镜像内复制已构建好的 sites/assets（兜底）
#       方案 C 重建 apps 软链（最后手段）
#
# 用法：cd 到 docker-compose.yaml 所在目录，然后 bash fix-assets.sh
# ============================================================
set -u

BACKEND="${BACKEND_CONTAINER:-erp_backend}"
SITE="${SITE:-frontend}"
IMAGE="${CN_IMAGE:-localhost/erpnext-cn:v15.32.0}"
BENCH=/home/frappe/frappe-bench

echo "=================================================="
echo " 前端资源修复  (site=$SITE, container=$BACKEND)"
echo "=================================================="

if ! podman ps --format '{{.Names}}' | grep -qx "$BACKEND"; then
  echo "错误：未找到运行中的 $BACKEND 容器。请先启动部署。"
  exit 1
fi

echo
echo "=== 1. 诊断：当前资源状态 ==="
podman exec "$BACKEND" bash -lc "ls -1 $BENCH/sites/assets 2>/dev/null | head -20 || echo '  (sites/assets 不存在)'"
echo "  --- erpnext_china/dist/js ---"
podman exec "$BACKEND" bash -lc "ls -1 $BENCH/sites/assets/erpnext_china/dist/js 2>/dev/null || echo '  (缺失)'"

echo
echo "=== 2. 诊断：node / yarn 位置 ==="
podman exec "$BACKEND" bash -lc 'echo "  PATH=$PATH"; command -v node || echo "  PATH 中无 node"; command -v yarn || echo "  PATH 中无 yarn"; ls -d /home/frappe/.nvm/versions/node/*/bin 2>/dev/null || echo "  无 nvm 目录"'

# ---------- 方案 A：定位 node 后重跑 bench build ----------
cat > /tmp/_build_assets_inner.sh <<INNER
#!/bin/bash
set -e
BENCH_DIR=$BENCH
SITE_NAME=$SITE
export NVM_DIR=/home/frappe/.nvm
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
if ! command -v node >/dev/null 2>&1; then
  D=\$(ls -d /home/frappe/.nvm/versions/node/*/bin 2>/dev/null | tail -1 || true)
  [ -n "\$D" ] && export PATH="\$D:\$PATH"
fi
if ! command -v node >/dev/null 2>&1; then
  for d in /usr/local/bin /usr/bin /opt/node/bin; do
    [ -x "\$d/node" ] && export PATH="\$d:\$PATH" && break
  done
fi
command -v node >/dev/null 2>&1 || { echo "NODE_NOT_FOUND"; exit 9; }
echo "  using node: \$(node -v)"
cd "\$BENCH_DIR"
bench build --app erpnext_china
bench --site "\$SITE_NAME" clear-cache
INNER

podman cp /tmp/_build_assets_inner.sh "$BACKEND":/tmp/_build_assets_inner.sh >/dev/null 2>&1

echo
echo "=== 3. 方案 A：定位 node 后重跑 bench build ==="
A_OK=0
if podman exec "$BACKEND" bash /tmp/_build_assets_inner.sh; then
  echo "  [OK] 方案 A 成功"
  A_OK=1
else
  echo "  [WARN] 方案 A 未成功（容器内确实找不到 node）"
fi

# ---------- 方案 B / C：从镜像里拿资源 ----------
if [ "$A_OK" != "1" ]; then
  echo
  echo "=== 4. 方案 B（兜底）：从镜像复制已构建好的 sites/assets ==="
  if podman run --rm --entrypoint sh \
      -v "$PWD/sites:/hostsites:Z" \
      "$IMAGE" -c '
        SRC=/home/frappe/frappe-bench/sites/assets
        if [ ! -d "$SRC" ]; then echo "  镜像内 sites/assets 不存在"; exit 1; fi
        rm -rf /hostsites/assets
        cp -a "$SRC" /hostsites/assets
        echo "  已复制，条目数: $(ls -1 /hostsites/assets | wc -l)"
      '; then
    echo "  [OK] 方案 B 完成"
  else
    echo "  [WARN] 方案 B 失败，改用方案 C"
    echo
    echo "=== 5. 方案 C：直接重建 apps 软链 ==="
    podman run --rm --entrypoint sh \
      -v "$PWD/sites:/hostsites:Z" \
      "$IMAGE" -c '
        mkdir -p /hostsites/assets
        for app in frappe erpnext erpnext_china; do
          P=/home/frappe/frappe-bench/apps/$app/$app/public
          if [ -d "$P" ]; then ln -sfn "$P" /hostsites/assets/$app; echo "  linked $app"; else echo "  skip $app"; fi
        done
      '
  fi
fi

echo
echo "=== 6. 站点内 assets 软链 ==="
podman exec "$BACKEND" bash -lc "cd $BENCH/sites && [ -e $SITE/assets ] || ln -sfn ../assets $SITE/assets; ls -ld $SITE/assets 2>/dev/null || echo '  (无)'"

echo
echo "=== 7. 清缓存 ==="
podman exec "$BACKEND" bash -lc "cd $BENCH && bench --site $SITE clear-cache" 2>&1 | tail -3

echo
echo "=== 8. 复查 ==="
podman exec "$BACKEND" bash -lc "ls -1 $BENCH/sites/assets/erpnext_china/dist/js 2>/dev/null || echo '  (仍缺失，请把上面 1~2 步的诊断输出发我)'"

echo
echo "完成。请用 Ctrl+Shift+R 强制刷新浏览器，检查中文包字段是否出现。"

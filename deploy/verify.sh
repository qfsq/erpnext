#!/bin/bash
# ============================================================
# 部署后体检（10 项）
# 用法：cd 到 docker-compose.yaml 所在目录，bash verify.sh
# 可用环境变量覆盖：SITE / BACKEND_CONTAINER / DB_CONTAINER / ERP_URL
# ============================================================
set -u

SITE="${SITE:-frontend}"
BACKEND="${BACKEND_CONTAINER:-erp_backend}"
DB="${DB_CONTAINER:-erp_postgres}"
URL="${ERP_URL:-http://localhost:8089}"
PASS=0; FAIL=0; INFO=0
ok(){   echo "  [PASS] $1"; PASS=$((PASS+1)); }
no(){   echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
info(){ echo "  [INFO] $1"; INFO=$((INFO+1)); }

echo "=================================================="
echo " ERPNext 中文版 部署体检"
echo "=================================================="

echo
echo "=== 1. 容器状态 ==="
podman ps --format "  {{.Names}}\t{{.Status}}" 2>/dev/null | grep erp_ || echo "  (无 erp_ 容器)"
for c in erp_postgres erp_redis_cache erp_redis_queue erp_backend erp_websocket erp_frontend; do
  if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx "$c"; then ok "$c 运行中"; else no "$c 未运行"; fi
done

echo
echo "=== 2. 镜像内 app 列表 ==="
podman exec "$BACKEND" bash -lc "cd /home/frappe/frappe-bench && bench version" 2>/dev/null | sed 's/^/  /'
if podman exec "$BACKEND" bash -lc "cd /home/frappe/frappe-bench && bench version" 2>/dev/null | grep -q erpnext_china; then
  ok "镜像含 erpnext_china"
else
  no "镜像缺 erpnext_china"
fi

echo
echo "=== 3. 镜像内 Python 依赖（pandas / numpy）==="
if podman exec "$BACKEND" bash -lc "/home/frappe/frappe-bench/env/bin/python -c 'import pandas,numpy;print(pandas.__version__, numpy.__version__)'" >/tmp/_dep 2>&1; then
  info "pandas / numpy: $(cat /tmp/_dep)"
  ok "pandas / numpy 可导入"
else
  no "pandas / numpy 不可导入"
fi

echo
echo "=== 4. 站点已安装 app ==="
podman exec "$BACKEND" bash -lc "cd /home/frappe/frappe-bench && bench --site $SITE list-apps" 2>/dev/null | sed 's/^/  /'
if podman exec "$BACKEND" bash -lc "cd /home/frappe/frappe-bench && bench --site $SITE list-apps" 2>/dev/null | grep -q erpnext_china; then
  ok "站点已装 erpnext_china"
else
  no "站点未装 erpnext_china"
fi

echo
echo "=== 5. Web 探活（$URL）==="
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$URL" 2>/dev/null || echo 000)
info "HTTP 状态码：$CODE"
if [ "$CODE" = "200" ]; then ok "服务可访问（200）"; else no "服务不可访问（$CODE）"; fi

echo
echo "=== 6. 中文本地化 DocType（数据库直查）==="
N=$(podman exec "$DB" psql -U postgres -d "$SITE" -tAc \
    "select count(*) from \"tabDocType\" where module='ERPNext China'" 2>/dev/null | tr -d '[:space:]')
info "ERPNext China 模块 DocType 数量：${N:-0}"
if [ "${N:-0}" -gt 0 ] 2>/dev/null; then ok "中文本地化 DocType 已装"; else no "未查到中文本地化 DocType"; fi

echo
echo "=== 7. 中国行政区划（Territory）==="
T=$(podman exec "$DB" psql -U postgres -d "$SITE" -tAc \
    "select count(*) from \"tabTerritory\"" 2>/dev/null | tr -d '[:space:]')
info "Territory 总数：${T:-0}"
if [ "${T:-0}" -gt 0 ] 2>/dev/null; then ok "行政区划已导入"; else no "未查到行政区划"; fi

echo
echo "=== 8. 前端资源（erpnext_china bundle）==="
if podman exec "$BACKEND" bash -lc "test -d /home/frappe/frappe-bench/sites/assets/erpnext_china/dist/js" 2>/dev/null; then
  podman exec "$BACKEND" bash -lc "ls -1 /home/frappe/frappe-bench/sites/assets/erpnext_china/dist/js" 2>/dev/null | sed 's/^/  /'
  ok "erpnext_china 前端资源已就位"
else
  no "erpnext_china 前端资源缺失 —— 请执行 bash fix-assets.sh"
fi

echo
echo "=== 9. AI 助手 erp_mcp ==="
if podman ps --format '{{.Names}}' 2>/dev/null | grep -qx erp_mcp; then
  ST=$(podman ps --format '{{.Names}}|{{.Status}}' 2>/dev/null | grep '^erp_mcp|' | cut -d'|' -f2)
  info "erp_mcp 状态：$ST"
  case "$ST" in
    Up*) ok "erp_mcp 持续运行中" ;;
    *)   no "erp_mcp 未稳定运行（检查包名 @casys/mcp-erpnext 与 --http 模式）" ;;
  esac
else
  no "erp_mcp 未运行（可选组件）"
fi
echo "  --- 最近 10 行日志 ---"
podman logs erp_mcp --tail 10 2>&1 | sed 's/^/  /' || true

echo
echo "=== 10. 后端日志（最近 10 行）==="
podman logs erp_backend --tail 10 2>&1 | sed 's/^/  /' || true

echo
echo "=================================================="
echo " 体检结果： PASS=$PASS  FAIL=$FAIL  INFO=$INFO"
echo "=================================================="
if [ "$FAIL" -gt 0 ]; then
  echo " 有 $FAIL 项未通过，请对照上面的 [FAIL] 处理。"
else
  echo " 全部通过。"
fi

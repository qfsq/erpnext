#!/bin/bash
# ================================================================
# 在【已有站点和数据】的部署上续装 erpnext_china
# 不重建数据库、不重跑 new-site，2-3 分钟完成
#
# 适用：站点已建好（bench new-site 成功），但装中文包失败的情况。
# ================================================================
set -o pipefail

SITE_NAME="frontend"
BACKEND="erp_backend"
CORE_SERVICES="erp_postgres erp_redis_cache erp_redis_queue erp_backend erp_websocket erp_frontend"

bexec() { podman exec "$BACKEND" bash -lc "cd /home/frappe/frappe-bench && $*"; }

echo "=== 1. 确保核心容器在运行 ==="
if ! podman ps --format "{{.Names}}" 2>/dev/null | grep -qx "$BACKEND"; then
  echo "  backend 未运行，尝试启动核心容器..."
  podman-compose up -d $CORE_SERVICES
  sleep 10
fi
podman ps --format "  {{.Names}}\t{{.Status}}" 2>/dev/null | grep erp_

echo ""
echo "=== 2. 检查站点是否存在 ==="
APPS=$(bexec "bench --site $SITE_NAME list-apps" 2>/dev/null)
if ! echo "$APPS" | grep -q erpnext; then
  echo "  错误：站点 $SITE_NAME 不存在或未安装 erpnext。"
  echo "  请改用全新部署： bash deploy.sh"
  exit 1
fi
echo "$APPS" | sed 's/^/  /'

echo ""
echo "=== 3. 补齐 Python 依赖（必须装进 env 虚拟环境） ==="
bexec "./env/bin/pip install --no-cache-dir 'pandas>=2.0,<3' 'numpy>=1.23'" 2>&1 | tail -3
bexec "./env/bin/python -c \"import pandas, numpy; print('deps ok:', pandas.__version__, numpy.__version__)\""

echo ""
echo "=== 4. 续装 erpnext_china ==="
if bexec "bench --site $SITE_NAME list-apps" 2>/dev/null | grep -q erpnext_china; then
  echo "  已安装，跳过。"
else
  bexec "export LC_ALL=C.UTF-8 LANG=C.UTF-8 && bench --site $SITE_NAME install-app erpnext_china" 2>&1 | tail -20
  if ! bexec "bench --site $SITE_NAME list-apps" 2>/dev/null | grep -q erpnext_china; then
    echo "  首次失败，尝试 --force 重试..."
    bexec "export LC_ALL=C.UTF-8 LANG=C.UTF-8 && bench --site $SITE_NAME install-app erpnext_china --force" 2>&1 | tail -20
  fi
fi

echo ""
echo "=== 5. 构建前端资源 + 清缓存 ==="
bexec "bench build --app erpnext_china" 2>&1 | tail -5
bexec "bench --site $SITE_NAME clear-cache"

echo ""
echo "=== 6. 结果 ==="
bexec "bench --site $SITE_NAME list-apps" | sed 's/^/  /'
echo ""
echo "完成。可执行 bash verify.sh 做完整体检。"

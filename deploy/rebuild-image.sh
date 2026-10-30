#!/bin/bash
# ================================================================
# 只重建中文镜像（不动数据）
#
# 适用：镜像存在但内容不对（例如缺 erpnext_china 或缺 pandas）。
# 关键：必须先清容器，否则 podman rmi 会报
#       "container xxx using image could not be removed"
# ================================================================
set -o pipefail

CN_IMAGE="localhost/erpnext-cn:v15.32.0"
BASE_IMAGE="docker.io/frappe/erpnext:v15.32.0"

[ -f Dockerfile ] || { echo "错误：当前目录缺少 Dockerfile"; exit 1; }

echo "=== 1. 清理容器（保留数据卷） ==="
podman-compose down 2>/dev/null || true
podman rm -f -a 2>/dev/null || true
for id in $(podman ps -aq 2>/dev/null); do
  podman rm -f --depend "$id" 2>/dev/null || true
done
echo "  完成"

echo ""
echo "=== 2. 删除旧镜像 ==="
podman rmi -f "$CN_IMAGE" 2>/dev/null || echo "  （旧镜像不存在，跳过）"

echo ""
echo "=== 3. 拉取基础镜像 ==="
podman pull "$BASE_IMAGE" || { echo "错误：拉取失败"; exit 1; }

echo ""
echo "=== 4. 构建（--no-cache，首次约 3-10 分钟） ==="
podman build --no-cache -t "$CN_IMAGE" -f Dockerfile . || { echo "错误：构建失败"; exit 1; }

echo ""
echo "=== 5. 验证 ==="
podman run --rm "$CN_IMAGE" bench version
podman run --rm "$CN_IMAGE" /home/frappe/frappe-bench/env/bin/python -c \
  "import pandas, numpy; print('deps ok:', pandas.__version__, numpy.__version__)"

echo ""
echo "镜像重建完成。接下来二选一："
echo "  - 全新部署：      bash deploy.sh"
echo "  - 用现有数据卷：  podman-compose up -d"

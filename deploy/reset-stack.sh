#!/bin/bash
# ================================================================
# 容器清理解锁
# 解决：Error: container xxx has dependent containers which must be
#       removed before it ...
#
# 原因：podman-compose 会把 compose 里的 depends_on 翻译成 Podman 的
#       硬依赖（--requires）。单独删一个"被依赖"的容器时会被拒绝。
#       这不是操作错误，而是 podman-compose 的已知行为。
#
# 正解（本脚本三级兜底）：
#   1) podman-compose down        不带 -v，保留数据卷
#   2) podman rm -f -a            单次调用内自行解析依赖顺序
#   3) podman rm -f --depend ID   连依赖它的容器一起删
#
# ⚠️ 绝不要用 -v。数据在命名卷与 sites 目录里，不受影响。
# ================================================================
set -o pipefail

echo "=== 清理前容器清单 ==="
podman ps -a --format "  {{.Names}}\t{{.Status}}" 2>/dev/null || echo "  (无)"

echo ""
echo "=== [1/4] podman-compose down（不带 -v，保留数据卷） ==="
podman-compose down 2>/dev/null || true
echo "  完成"

echo ""
echo "=== [2/4] 一次性删除所有容器（单次调用内自行解析依赖顺序） ==="
podman rm -f -a 2>/dev/null || true
echo "  完成"

echo ""
echo "=== [3/4] --depend 递归兜底（处理残留依赖链） ==="
for id in $(podman ps -aq 2>/dev/null); do
  podman rm -f --depend "$id" 2>/dev/null || true
done
echo "  完成"

echo ""
echo "=== [4/4] 核查结果 ==="
LEFT=$(podman ps -aq 2>/dev/null | wc -l | tr -d ' ')
if [ "$LEFT" = "0" ]; then
  echo "  ✅ 所有容器已清理干净。"
else
  echo "  仍有 $LEFT 个容器："
  podman ps -a --format "  {{.Names}}\t{{.Status}}"
fi

echo ""
echo "=== 数据卷（未删除，数据完好） ==="
podman volume ls --format "  {{.Name}}" 2>/dev/null || true

echo ""
echo "清理完成。接下来："
echo "  - 全新部署：    bash deploy.sh"
echo "  - 只重建镜像：  bash rebuild-image.sh"
echo "  - 续装中文包：  bash resume.sh"

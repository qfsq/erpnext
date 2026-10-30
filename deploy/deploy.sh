#!/bin/bash
# ================================================================
# ERPNext 中文本地化 + AI(MCP) 一键部署
# 目标环境：Podman + podman-compose
#
# 流程：
#   0    前置检查
#   1    清理旧容器与网络（保留数据卷）
#   2    检查 / 构建中文镜像（缺 app 或缺 pandas 都会自动重建）
#   3    清理 sites 目录并初始化 apps.txt
#   3.5  提前写入 common_site_config.json
#   4    启动核心 6 个容器（不含 MCP）
#   4.5  等待 PostgreSQL 就绪
#   5    初始化数据库与用户（含 public schema 授权）
#   6    创建站点并安装 ERPNext
#   6.1  安装 erpnext_china + build + clear-cache
#   7    设默认站点 + 校验 Nginx
#   8    最后启动 MCP（可选；失败只警告，不影响 ERPNext）
#
# 已内置规避的 6 个坑：
#   ① short-name 不解析        -> 所有镜像写全路径 docker.io/...
#   ② image not known          -> 自动检测并构建，不再"跳过构建"用旧镜像
#   ③ tabDefaultValue 缺失     -> 提前写好含 db_type 的 common_site_config.json
#   ④ No module named pandas   -> 镜像内用 env/bin/pip 补装
#   ⑤ 容器有依赖删不掉          -> rm -f -a 一次性删 + --depend 兜底
#   ⑥ workdir /app 不存在       -> compose 里不写 working_dir
# ================================================================
set -o pipefail

SITE_NAME="frontend"
DB_PASSWORD="postgres"
DB_ROOT_USER="postgres"
DB_ROOT_PASSWORD="postgres"
CN_IMAGE="localhost/erpnext-cn:v15.32.0"
BASE_IMAGE="docker.io/frappe/erpnext:v15.32.0"
BACKEND="erp_backend"
CORE_SERVICES="erp_postgres erp_redis_cache erp_redis_queue erp_backend erp_websocket erp_frontend"

# 在 backend 容器内 bench 目录下执行命令
bexec() { podman exec "$BACKEND" bash -lc "cd /home/frappe/frappe-bench && $*"; }

echo "=== 0. 前置检查 ==="
command -v podman >/dev/null 2>&1 || { echo "错误：未安装 podman"; exit 1; }
[ -f Dockerfile ] || { echo "错误：当前目录缺少 Dockerfile"; exit 1; }
[ -f docker-compose.yaml ] || { echo "错误：当前目录缺少 docker-compose.yaml"; exit 1; }
if ! command -v podman-compose >/dev/null 2>&1; then
  echo "警告：未检测到 podman-compose。若你的环境使用 'podman compose'，"
  echo "      请把本脚本里的 podman-compose 全部替换为 'podman compose'。"
fi

echo ""
echo "=== 1. 清理旧容器与网络（保留数据卷） ==="
podman-compose down 2>/dev/null || true
# 一次性删除全部容器：Podman 在单次调用内自行解析依赖顺序，不会报
# "container ... has dependent containers which must be removed before it"
podman rm -f -a 2>/dev/null || true
# 兜底：递归清掉残留的依赖链
for id in $(podman ps -aq 2>/dev/null); do
  podman rm -f --depend "$id" 2>/dev/null || true
done
podman network prune -f 2>/dev/null || true
echo "  容器清理完成（数据库卷保留）"

echo ""
echo "=== 2. 检查 / 构建中文镜像 ==="
image_has_app() {
  podman run --rm "$CN_IMAGE" bench version 2>/dev/null | grep -q "erpnext_china"
}
image_has_deps() {
  podman run --rm "$CN_IMAGE" /home/frappe/frappe-bench/env/bin/python -c \
    "import pandas, numpy" >/dev/null 2>&1
}

NEED_BUILD=0
REASON=""
if ! podman image exists "$CN_IMAGE"; then
  NEED_BUILD=1; REASON="镜像不存在"
elif ! image_has_app; then
  NEED_BUILD=1; REASON="镜像内缺少 erpnext_china"
elif ! image_has_deps; then
  NEED_BUILD=1; REASON="镜像缺少 pandas / numpy（erpnext_china 漏声明的依赖）"
fi

if [ "$NEED_BUILD" = "1" ]; then
  echo "  需要构建镜像，原因：$REASON"
  echo "  --- 2.1 删除旧镜像（此时容器已清空，不会再报依赖错误）---"
  podman rmi -f "$CN_IMAGE" 2>/dev/null || true
  echo "  --- 2.2 拉取基础镜像 ---"
  podman pull "$BASE_IMAGE" || { echo "  错误：拉取基础镜像失败"; exit 1; }
  echo "  --- 2.3 构建（--no-cache，首次约 3-10 分钟）---"
  if ! podman build --no-cache -t "$CN_IMAGE" -f Dockerfile .; then
    echo "  错误：镜像构建失败。请检查上面日志（常见原因：仓库地址、网络）。"
    exit 1
  fi
  echo "  --- 2.4 验证镜像内 app 列表 ---"
  podman run --rm "$CN_IMAGE" bench version
  echo "  --- 2.5 验证镜像内 Python 依赖 ---"
  if ! podman run --rm "$CN_IMAGE" /home/frappe/frappe-bench/env/bin/python -c \
       "import pandas, numpy; print('deps ok:', pandas.__version__, numpy.__version__)"; then
    echo "  错误：镜像内 pandas / numpy 仍缺失。"
    exit 1
  fi
  echo "  依赖校验通过。"
else
  echo "  镜像已就绪（含 erpnext_china + pandas / numpy），跳过构建。"
fi

echo ""
echo "=== 3. 清理宿主机残留站点文件并初始化配置 ==="
mkdir -p sites
podman run --rm -v ./sites:/target:Z docker.io/library/alpine sh -c "rm -rf /target/*" 2>/dev/null || true
rm -rf sites/* 2>/dev/null || true
rm -rf "$SITE_NAME" 2>/dev/null || true

printf 'frappe\nerpnext\nerpnext_china\n' > apps.txt
cp apps.txt sites/apps.txt
chmod -R 777 sites
echo "  apps.txt = frappe / erpnext / erpnext_china"

echo ""
echo "=== 3.5 提前写入 common_site_config.json ==="
cat > sites/common_site_config.json <<'JSON'
{
  "db_type": "postgres",
  "db_host": "erp_postgres",
  "db_port": 5432,
  "redis_cache": "redis://erp_redis_cache:6379",
  "redis_queue": "redis://erp_redis_queue:6379",
  "redis_socketio": "redis://erp_redis_queue:6379",
  "socketio_port": 9000
}
JSON
chmod 666 sites/common_site_config.json
echo "  已写入 db_type=postgres，避免 bench new-site 走错数据库分支"

echo ""
echo "=== 4. 启动核心容器集群（不含 MCP） ==="
podman-compose up -d $CORE_SERVICES

echo ""
echo "=== 4.5 等待 PostgreSQL 完全就绪 ==="
PG_OK=0
for i in $(seq 1 30); do
  if podman exec erp_postgres pg_isready -U "$DB_ROOT_USER" -h localhost -p 5432 >/dev/null 2>&1; then
    PG_OK=1
    echo "  PostgreSQL 已成功就绪！"
    break
  fi
  echo "  等待 PostgreSQL 启动中 ($i/30)..."
  sleep 2
done
[ "$PG_OK" = "1" ] || { echo "  错误：PostgreSQL 未就绪，请查看 podman logs erp_postgres"; exit 1; }
sleep 3

echo ""
echo "=== 5. 初始化数据库与用户 ==="
cat > init_db.sql <<EOF
DROP DATABASE IF EXISTS "$SITE_NAME";
DROP ROLE IF EXISTS "$SITE_NAME";
CREATE ROLE "$SITE_NAME" WITH LOGIN PASSWORD '$DB_PASSWORD' SUPERUSER CREATEDB CREATEROLE;
CREATE DATABASE "$SITE_NAME" OWNER "$SITE_NAME";
\c "$SITE_NAME"
GRANT ALL ON SCHEMA public TO "$SITE_NAME";
ALTER SCHEMA public OWNER TO "$SITE_NAME";
EOF
podman cp init_db.sql erp_postgres:/tmp/init_db.sql
podman exec erp_postgres psql -U "$DB_ROOT_USER" -v ON_ERROR_STOP=1 -f /tmp/init_db.sql || {
  echo "  错误：数据库初始化失败"; rm -f init_db.sql; exit 1; }
rm -f init_db.sql
echo "  数据库与角色已就绪（含 public schema 授权）"

echo ""
echo "=== 6. 创建站点并安装 ERPNext（完整日志写入 newsite.log） ==="
podman exec "$BACKEND" bash -lc "mkdir -p /home/frappe/logs /home/frappe/frappe-bench/logs"

podman exec "$BACKEND" bash -lc "cd /home/frappe/frappe-bench && \
  export LC_ALL=C.UTF-8 && \
  export LANG=C.UTF-8 && \
  export PGPASSWORD=$DB_PASSWORD && \
  bench new-site $SITE_NAME \
    --db-type postgres \
    --db-host erp_postgres \
    --db-port 5432 \
    --db-name $SITE_NAME \
    --db-password $DB_PASSWORD \
    --db-root-username $DB_ROOT_USER \
    --db-root-password $DB_ROOT_PASSWORD \
    --admin-password admin \
    --install-app erpnext \
    --force" 2>&1 | tee newsite.log

if ! bexec "bench --site $SITE_NAME list-apps" 2>/dev/null | grep -q erpnext; then
  echo "  错误：站点创建失败。关键行如下："
  grep -n -i -E 'psql:|error|fatal|permission|traceback' newsite.log | head -30
  exit 1
fi
echo "  站点创建成功。"

echo ""
echo "=== 6.1 安装中文本地化包 erpnext_china ==="
if bexec "bench --site $SITE_NAME list-apps" 2>/dev/null | grep -q erpnext_china; then
  echo "  检测到已安装，跳过。"
else
  bexec "export LC_ALL=C.UTF-8 LANG=C.UTF-8 && bench --site $SITE_NAME install-app erpnext_china" 2>&1 | tee install_cn.log
  if ! bexec "bench --site $SITE_NAME list-apps" 2>/dev/null | grep -q erpnext_china; then
    echo "  首次安装未成功，尝试 --force 重试..."
    bexec "export LC_ALL=C.UTF-8 LANG=C.UTF-8 && bench --site $SITE_NAME install-app erpnext_china --force" 2>&1 | tee -a install_cn.log
  fi
fi

if bexec "bench --site $SITE_NAME list-apps" 2>/dev/null | grep -q erpnext_china; then
  echo "  erpnext_china 安装成功。"
else
  echo "  错误：erpnext_china 仍未安装。关键行如下："
  grep -n -i -E 'error|traceback|no module named' install_cn.log 2>/dev/null | head -30
  exit 1
fi

echo "  --- 构建前端资源 + 清缓存 ---"
# 注意：镜像用 nvm 装 node，非交互式 shell 里 PATH 找不到 node，
#       直接跑 bench build 会失败且不中断（报 Invalid version string: 'bin/sh: 1: node: not found'），
#       结果是 assets 未链接、中文包前端不生效。这里交给 fix-assets.sh 处理。
if [ -f "$(dirname "$0")/fix-assets.sh" ]; then
  echo "  调用 fix-assets.sh（自动定位 node 后重建资源）"
  bash "$(dirname "$0")/fix-assets.sh" 2>&1 | tail -20 || true
else
  echo "  未找到 fix-assets.sh，退回直接构建"
  bexec "bench build --app erpnext_china" 2>&1 | tail -5
  bexec "bench --site $SITE_NAME clear-cache"
fi
echo "  完成。"

echo ""
echo "=== 7. 设默认站点 + 校验 Nginx ==="
bexec "bench use $SITE_NAME"
if podman exec erp_frontend nginx -t >/dev/null 2>&1; then
  echo "  Nginx 配置校验通过。"
else
  echo "  警告：Nginx 配置校验失败，请检查 erp_frontend 日志。"
  podman logs erp_frontend --tail 20 2>/dev/null || true
fi

echo ""
echo "=== 8. 启动 AI 助手 erp_mcp（可选；失败不影响主体） ==="
if podman-compose up -d erp_mcp 2>&1; then
  sleep 3
  podman ps --filter name=erp_mcp --format "  {{.Names}}  {{.Status}}" 2>/dev/null || true
  echo "  若状态不是 Up，检查：① 包名须为 @casys/mcp-erpnext；② 须为 --http 模式；③ 见 README"
else
  echo "  警告：erp_mcp 未启动。ERPNext 本体不受影响。"
fi

echo ""
echo "=================================================="
echo " 部署完成"
echo "=================================================="
echo " 访问地址： http://localhost:8089"
echo " 用户名：   Administrator"
echo " 密码：     admin"
echo ""
echo " 下一步："
echo "   1) bash verify.sh                  部署后体检（10 项）"
echo "   2) 启用 AI 助手：生成 API Key/Secret 填入 docker-compose.yaml 的 erp_mcp，再"
echo "      podman-compose up -d erp_mcp"
echo "   3) 前端资源若异常：bash fix-assets.sh"
echo "   4) 中国三大报表与税务配置见 config/ 目录"
echo "   5) 操作与加固清单见 下一步操作清单.md"
echo "=================================================="

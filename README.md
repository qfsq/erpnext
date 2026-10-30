# ERPNext 中文版（erpnext_china）Podman 部署包 —— 完整版 v6

> 一套基于 **Podman + podman-compose** 的 ERPNext 中文本地化部署方案。
> 在官方镜像 `frappe/erpnext:v15.32.0` 基础上打入中文包 **erpnext_china**，并附带 AI 助手（MCP）与全套中国财税配置资料。
>
> **对已有环境是原地修复**：不改动已建好的站点与数据。

---

## 一、包内文件一览

### `deploy/` —— 部署文件（12 个）

| 文件 | 用途 |
|---|---|
| **`deploy.sh`** | ⭐ 一键部署（8 大步骤，已内置 6 个坑的规避） |
| **`docker-compose.yaml`** | ⭐ 7 个服务：postgres / 2×redis / backend / websocket / frontend / mcp |
| **`Dockerfile`** | 构建中文镜像：打入 erpnext_china + 补装 pandas/numpy |
| **`fix-assets.sh`** | ⭐ 修复前端资源（node PATH 问题导致 assets 未链接） |
| **`verify.sh`** | ⭐ 部署后体检 **10 项** |
| `resume.sh` | 已有站点续装中文包（不重建库） |
| `rebuild-image.sh` | 只重建镜像，不动数据 |
| `reset-stack.sh` | 容器清理解锁（解决"容器有依赖删不掉"） |
| `apps.txt` | app 清单：frappe / erpnext / erpnext_china |
| `.env.example` | 环境变量模板（MCP 凭据、包名、端口） |
| `mcp-client-config.json` | AI 客户端 MCP 配置样例 |
| `README.md` | 本版两个修复的详细说明 |

### `config/` —— 中国财税配置资料（7 个）

| 文件 | 内容 |
|---|---|
| `01_中国会计科目表导入对照表.csv` | 常用科目 + 账户类别映射 |
| `05_会计科目表_导入模板_官方8列格式.csv` | ⭐ 可直接导入的官方格式模板 |
| `06_科目类别AccountCategory_设置清单.md` | ⭐ 导入后必做，否则自定义报表全 0 |
| `02_三大报表配置清单.md` | 资产负债表 / 利润表 / 现金流量表 |
| `04_增值税与税务配置清单.md` | 税率模板、发票台账、金税对接 |
| `03_研发费用辅助账配置方案.md` | 数据模型 + 双口径 |
| `07_研发费用辅助账_查询报表SQL.sql` | 6 张可直接用的 Query Report SQL |

### 根目录

| 文件 | 内容 |
|---|---|
| `下一步操作清单.md` | 部署完成后做什么（A–F 六条线）+ 常用维护命令 |

---

## 二、快速开始

### 全新部署

```bash
cd deploy
chmod +x *.sh
bash deploy.sh          # 自动：拉基础镜像 → 构建中文镜像 → 起栈 → 建站点 → 装中文包
bash verify.sh          # 体检 10 项
```

### 已部署环境，只修前端资源

```bash
cd deploy
bash fix-assets.sh
```

### 启用 AI 助手（MCP）

1. 登录 ERPNext → 右上角头像 → **My Settings → API Access → Generate Keys**
   ⚠️ 不要用 Administrator，建个专用只读用户
2. 把 key / secret 填进 `docker-compose.yaml` 的 `erp_mcp` 环境变量
3. 启动：

```bash
podman-compose up -d erp_mcp
podman logs -f erp_mcp
```

---

## 三、已内置规避的 6 个坑

| # | 坑 | 规避方式 |
|---|---|---|
| 1 | **short-name 不解析**（Podman 默认禁短名） | 所有镜像写全路径 `docker.io/...` |
| 2 | **image not known** | 自动检测并构建，不再"跳过构建"用旧镜像 |
| 3 | **tabDefaultValue 缺失** | 提前写好含 `db_type` 的 `common_site_config.json` |
| 4 | **No module named pandas** | 镜像内用 `env/bin/pip` 补装（该 app 漏声明依赖） |
| 5 | **容器有依赖删不掉** | `rm -f -a` 一次性删 + `--depend` 兜底 |
| 6 | **workdir /app 不存在** | compose 里不写 `working_dir`（Docker 会自动建、Podman 不会） |

---

## 四、关键设计说明

### 为什么中文包必须打进镜像

多容器架构下 backend / websocket / frontend **必须共用同一个镜像**；且 `sites/` 是挂载目录，每次重建都会覆盖。只有装进镜像（`apps/` 与 `env/` 在镜像里）才能持久保留。

### 为什么要补装 pandas / numpy

erpnext_china 的 `pyproject.toml` 只声明了 5 个依赖，但 `button_permission.py` 在**模块顶层** `import pandas`。Frappe 安装时同步 DocType 会立即加载控制器，走到 `Button Permission` 就抛 `ImportError`，安装停在 **44%**（不是巧合，就是该文件在列表里的位置）。

**必须装进 `env` 虚拟环境**——用系统 `pip install pandas` 装完，bench 运行时看不到。

### 为什么 MCP 用 HTTP 模式且指向 frontend

- **stdio 模式不能做常驻服务**：靠标准输入通信，容器 detached 启动后 stdin 立即关闭，进程随即退出。
- **`ERPNEXT_URL` 必须走 `erp_frontend:8080`（Nginx）**：Frappe 按 Host 头定位站点，直连 `erp_backend:8000` 时 Host 与站点名不匹配会报站点找不到；Nginx 会统一补上 `X-Frappe-Site-Name`。

---

## 五、维护命令

```bash
# 状态 / 日志
podman ps --format "{{.Names}}\t{{.Status}}"
podman logs -f erp_backend
podman logs -f erp_mcp

# 进容器
podman exec -it erp_backend bash
podman exec -it erp_backend bash -lc "cd /home/frappe/frappe-bench && bench --site frontend list-apps"

# 清缓存
podman exec -it erp_backend bash -lc "cd /home/frappe/frappe-bench && bench --site frontend clear-cache"

# 备份
podman exec erp_backend bash -lc "cd /home/frappe/frappe-bench && bench --site frontend backup --with-files"
```

---

## 六、访问

- 地址：**http://<你的服务器IP>:8089**
- 账号：**Administrator / admin**（⚠️ 上线前务必修改）

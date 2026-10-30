# ERPNext 中文版 —— v6 修复包

本包用于修复 v5 部署完成后暴露的两个问题，**不改动你已建好的站点和数据**。

---

## 一、修复的两个问题

### 问题 1：`node not found` 导致前端资源没构建

部署日志里的报错：

```
--- 构建前端资源 + 清缓存 ---
ValueError: Invalid version string: 'bin/sh: 1: node: not found'
```

**后果**：`erpnext_china` 虽然显示"安装成功"，但它的前端资源没有链接到
`sites/assets/`，于是：

- `/assets/erpnext_china/dist/js/erpnext_china.bundle.js` → 404
- `/assets/erpnext_china/dist/css/business.bundle.css` → 404
- 表现为**中文包的自定义字段/按钮/表单脚本不生效**

**原因**：镜像用 nvm 安装 node，PATH 只在交互式 shell 里生效；
非登录 shell 执行 `bench build` 时找不到 node。

**修复**：`bash fix-assets.sh`

---

### 问题 2：MCP 容器秒退（`Up Less than a second`）

两个叠加的错误，都在配置侧：

| # | 问题 | 说明 |
|---|---|---|
| 1 | ❌ 包名写成 `mcp-erpnext` | npm 上**不存在**这个包；正确是 **`@casys/mcp-erpnext`**（带作用域） |
| 2 | ❌ 用 stdio 模式跑常驻容器 | MCP 的 stdio 模式靠标准输入通信；容器以 detached 方式启动时 stdin 立即关闭，进程随之退出 → 表现就是"起来一瞬间就没了" |

**修复**（已在 `docker-compose.yaml` 改好）：

```yaml
command: ["sh", "-c", "exec npx -y @casys/mcp-erpnext --http --port=3012"]
environment:
  - ERPNEXT_URL=http://erp_frontend:8080
```

> ⚠️ 另一处关键点：`ERPNEXT_URL` 必须走 **`erp_frontend:8080`（Nginx）**，
> 而不是 `erp_backend:8000`。因为 Frappe 按 Host 头定位站点，
> 直连后端容器时 Host 是 `erp_backend:8000`，与站点名不匹配会报站点找不到；
> Nginx 会统一补上 `X-Frappe-Site-Name`，所以走它更可靠。

---

## 二、执行步骤

```bash
# 1) 用本包的 docker-compose.yaml 覆盖你的
cp docker-compose.yaml /你的部署目录/docker-compose.yaml

# 2) 修复前端资源（会先打印诊断，再自动选方案）
cd /你的部署目录
bash fix-assets.sh

# 3) 重新拉起 MCP
podman-compose up -d erp_mcp
podman logs -f erp_mcp        # 看到监听 3012 即成功

# 4) 体检
bash verify.sh
```

`fix-assets.sh` 是**幂等**的，可以反复执行。

---

## 三、`fix-assets.sh` 的三级方案

| 方案 | 做法 | 适用 |
|---|---|---|
| **A** | 动态定位 node（nvm 目录 / 常见路径），设置 PATH 后重跑 `bench build` | 首选，最干净 |
| **B** | 从镜像内把已构建好的 `sites/assets` 复制到挂载目录 | A 失败时兜底 |
| **C** | 直接重建 `sites/assets/<app>` 软链指向 `apps/<app>/<app>/public` | 最后手段 |

脚本会**先打印诊断信息**（当前资源状态、node/yarn 位置、PATH），
即使三个方案都没成功，那几行诊断输出也足够定位原因。

---

## 四、启用 AI 助手的两种方式

### 方式一：容器常驻 HTTP（本包默认，适合多人/长期）

```yaml
erp_mcp:
  command: ["sh", "-c", "exec npx -y @casys/mcp-erpnext --http --port=3012"]
  ports:
    - "127.0.0.1:3012:3012"     # 默认只绑本机
```

AI 客户端（支持 HTTP/streamable MCP 的）连 `http://<服务器IP>:3012`。

> 默认绑定 `127.0.0.1` 是刻意的：MCP 服务持有 ERP API 凭据，
> 直接对公网开放风险很高。要远程访问请改成 `"3012:3012"` 并用防火墙限制来源 IP。

### 方式二：客户端本机 stdio（Claude Desktop 等）

AI 客户端和 node 都装在你自己的电脑上，用 `mcp-client-config.json`：

```json
{
  "mcpServers": {
    "erpnext": {
      "command": "npx",
      "args": ["-y", "@casys/mcp-erpnext"],
      "env": {
        "ERPNEXT_URL": "http://<ERP服务器IP>:8089",
        "ERPNEXT_API_KEY": "...",
        "ERPNEXT_API_SECRET": "..."
      }
    }
  }
}
```

Claude Desktop 配置文件位置：
- macOS：`~/Library/Application Support/Claude/claude_desktop_config.json`
- Linux：`~/.config/Claude/claude_desktop_config.json`
- Windows：`%APPDATA%\Claude\claude_desktop_config.json`

---

## 五、生成 API 凭据

1. 登录 ERPNext → 右上角头像 → **My Settings**
2. 找到 **API Access** → **Generate Keys**
3. 复制 Key 和 Secret，填进 `docker-compose.yaml` 的
   `MCP_ERP_API_KEY` / `MCP_ERP_API_SECRET`（或直接写值）

> ⚠️ **不要用 Administrator 账号**。新建一个专用用户，只授予必要的读权限。
> 凭据泄露等于把整个 ERP 交给对方。

---

## 六、顺带修掉的一处安全项

原 compose 把数据库端口映射成 `5439:5432`，等于**把 PostgreSQL 暴露到所有网卡**。
本包改为：

```yaml
ports:
  - "127.0.0.1:5439:5432"
```

只允许本机连接。如果你确实要远程连数据库，请自行加防火墙规则。

---

## 七、仍建议尽快补上的两件事

### 7.1 启用 worker / scheduler

你的部署只有 backend / websocket / frontend，**没有后台任务容器**：

| 缺失 | 后果 |
|---|---|
| worker | 邮件、批量操作、数据导入导出不执行 |
| scheduler | 自动提醒、重复单据、**自动备份**不执行 |

`docker-compose.yaml` 末尾已经写好 3 个服务（`erp_worker_short` /
`erp_worker_long` / `erp_scheduler`），**把行首注释去掉**再
`podman-compose up -d` 即可。

### 7.2 公网访问加 HTTPS

目前是明文 HTTP，财务数据与登录凭据都会裸奔。
建议前置 **Caddy**（自动签 Let's Encrypt 证书，配置最简）或
Nginx + certbot，转发到 `127.0.0.1:8089`。

---

## 八、常用命令

```bash
podman ps --format "{{.Names}}\t{{.Status}}"      # 容器状态
podman logs -f erp_backend                        # 后端日志
podman logs -f erp_mcp                            # MCP 日志
podman-compose up -d                              # 按 compose 拉起/更新
podman-compose down                               # 停止（不加 -v，保留数据）
podman exec -it erp_backend bash                  # 进容器
podman exec erp_backend bash -lc "cd /home/frappe/frappe-bench && bench --site frontend list-apps"
```

> ⚠️ **`podman-compose down -v` 会删除数据卷**，即数据库全部数据。慎用。

---

## 九、文件清单

| 文件 | 说明 |
|---|---|
| `docker-compose.yaml` | 已修正 MCP（包名 + HTTP 模式 + ERPNEXT_URL）；DB 端口只绑本机；附 worker/scheduler 注释模板 |
| `fix-assets.sh` | 修复前端资源（三级方案 + 诊断输出） |
| `verify.sh` | 体检 10 项（新增前端资源、MCP 两项） |
| `mcp-client-config.json` | AI 客户端 stdio 配置样例 |
| `README.md` | 本文件 |

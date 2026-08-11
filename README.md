# local-dev

Personal local development sandbox — docker compose recipes for the services SmartData / dbmanager / dbgate 本地开发依赖的全部外围基础设施。每个子目录是一个独立可起停的栈。

> 从 `ucc-workspace` 重命名而来（2026-05-19）。旧名字反映的是早期只服务 UCC SSO 项目；现在覆盖范围远大于此，所以更名 `local-dev`。

## 布局

| 目录 | 用途 |
|---|---|
| `nginx/` | 本地 https 反代（`dev.smartdata.local`），转发到 host 或容器模式发布的 SmartData / dbmanager / dbgate 端口 |
| `db/` | 30 种数据库的 compose 配方：MySQL/PG/Oracle/DM/达梦/TiDB/Hive/ClickHouse/MongoDB/ZooKeeper 等。每个子目录独立 |
| `ai/` | AI 工具栈：n8n / langflow / ollama / openwebui / vllm / context7-mcp |
| `redis/` | 三种拓扑：`single/` / `sentinel/` / `cluster/` |
| `dns/` | adguard 本地 DNS（按需用） |
| `kerberos/` | KDC，给 hive2/hive3 鉴权测试用 |
| `vault/` | HashiCorp Vault 开发模式 |
| `smartdata/` | SmartData 产品容器化开发配置（四服务 + 独立 Trusted Proxy） |
| `archive/` | 已弃用栈的归档：`sso/`（老 UCC SSO）/ `smartfs/` / `mqtt/` / `minio/` / `traefik/` / `docs/`（redis 旧文档） |

## 服务拓扑 (dev.smartdata.local)

> **本表是本地开发拓扑的唯一事实源（SSOT）。** smartdata / dbmanager 等仓的 README 只指向这里，不再各自抄一份；改了下面「权威源」里的文件，回来同步本表，并跑 `make check-topology` 复核。

统一入口 `https://dev.smartdata.local`（`/etc/hosts` 指到 `127.0.0.1`，由本仓 nginx 反代）。
SmartData 有两套互不替代的开发方式：`../smartdata/make dev` 启动 host + tmux，
本仓 `make smartdata-up` 启动容器模式。

| 服务 | 访问路径 | host 端口 | 启动方式 |
|------|----------|-----------|----------|
| dbmanager（管理前端） | `/db/`（登录 `/db/login`） | 3013 | host: `../smartdata/make dev`；container: `make smartdata-up` |
| smartdata API | `/dbapi/` | 8084 | host: `../smartdata/make dev`；container: `make smartdata-up` |
| 通知 SSE | `/dbapi/system/notifications/stream` | 8084 | 同 smartdata |
| dbgate 编辑器前端 | `/dbgatex/` | 5300 | host: `../smartdata/make dev`；container: `make smartdata-up` |
| dbgate 编辑器 API | `/dbgatex/api/`（终端 `/dbgatex/api/terminal`） | 3000 | host: `../smartdata/make dev`；container: `make smartdata-up` |
| smartdata MCP | `/mcp-smartdata/mcp` | 3010 | 可选 `make dev-smartdata-mcp` |

**权威源**（本表的值从这里派生）：

- 路由 / upstream → `nginx/conf.d/default.conf`（本仓）
- 端口 / 启动 → `../smartdata/Procfile.dev` + `../smartdata/Makefile`
- 镜像 / registry → 各仓 `.ci/jenkins/repo/*-build.Jenkinsfile`

## Quickstart

### 起 SmartData 本地反代

让 host 模式或容器模式的 `smartdata`/`dbmanager`/`dbgate` 通过
`https://dev.smartdata.local` 访问。两种模式不要同时占用四个 canonical ports：

```sh
# /etc/hosts
127.0.0.1 dev.smartdata.local

# 起 nginx
make nup        # 反代 80/443，conf 在 nginx/conf.d/default.conf
make ndown
```

证书 `nginx/ssl/selfsigned.{crt,key}` 已 gitignore，初次使用需自己生成（推荐 `mkcert`）。

### 起 SmartData 四服务容器模式

容器化开发配置位于 `smartdata/`，默认挂载三个同级源码仓库：

```sh
cp smartdata/.env.example smartdata/.env
# 按需调整三个 source dir 和本地 env-file 路径
# dbgate-web 参考 ../smartdata/make dev：在宿主机打包，容器只挂载 public
(cd ../dbgate && yarn build:web)
make smartdata-up
make smartdata-ps
make smartdata-down
```

Trusted Proxy 不会被 `make smartdata-up` 隐式启动，使用独立目标：

```sh
make smartdata-trusted-proxy-up
make smartdata-trusted-proxy-down
```

### 起单个数据库

每个 `db/<name>/` 目录都是独立 compose，按需起：

```sh
docker compose -f db/postgres/docker-compose.yml up -d
docker compose -f db/mysql/docker-compose.yml up -d
docker compose -f db/oracle23/docker-compose.yml up -d
docker compose -f db/dm8/docker-compose.yml up -d
```

完整 30 种清单见 `db/` 目录。多数共用 `dev_db_network` 外部网络：

```sh
docker network create dev_db_network
```

### 起 Redis（三选一）

```sh
make redis-up           # 单点
make redis-sentinel-up  # 哨兵
make redis-cluster-up   # 集群
```

### 起 AI 工具

```sh
docker compose -f ai/n8n/docker-compose.yml up -d
docker compose -f ai/ollama/docker-compose.yml up -d
docker compose -f ai/langflow/docker-compose.yml up -d
```

## Makefile 目标

`makefile` wire 了三组高频栈：`nginx`（nup/ndown）、`redis` 三种拓扑
（redis-up/redis-sentinel-up/redis-cluster-up + 对应 down），以及 SmartData
容器模式（smartdata-up/down/restart/logs/config/ps）。`SERVICE=<name>` 可用于
单服务启动、停止和查看日志；Trusted Proxy 有独立目标。

## 约定

- **每个子目录一个独立 compose**，互不依赖
- **`.env.example` checked-in，`.env` 本地填值**（`.env*` 已 gitignore）
- **运行时数据全部 gitignore**：`db/**/data/`、`db/**/hive_data/`、`dns/**/data/`、`kerberos/data/`
- **二进制 jar 不入 git**：`*.jar` ignore；hive 驱动等运行时下载或单独管理
- **SSL 私钥不入 git**：`**/selfsigned.{key,crt}` ignore，本地用 mkcert 重新生成
- **License 测试产物不入 git**：各产品运行时 license 产物按各自仓库的 ignore 规则管理

## 兄弟仓库

| Repo | 关系 |
|---|---|
| `../smartdata` | 主后端；host 模式由 `make dev` 起四服务，container 模式由本仓 `make smartdata-up` 起 |
| `../dbmanager` | Vue 前端，跑在 3013 |
| `../dbgate` | 数据库编辑器 BFF |
| `../ops-workspace` | 生产/线上运维仓（Jenkins/Harbor/Gitea/FRP 配置快照），和本仓互补 |

## 历史

- 2026-05-19：从 `ucc-workspace` 重命名为 `local-dev`，重写 README，整理 gitignore（运行时 state / jar / SSL key / license 产物），归档 `nginx-swarm` + `portainer` + `sso` + `smartfs` + `mqtt` + `minio` + `traefik` + `docs`（最后 6 个落 `archive/`，前 2 个直接删）

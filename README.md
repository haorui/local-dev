# local-dev

Personal local development sandbox — docker compose recipes for the services SmartData / dbmanager / dbgate 本地开发依赖的全部外围基础设施。每个子目录是一个独立可起停的栈。

> 从 `ucc-workspace` 重命名而来（2026-05-19）。旧名字反映的是早期只服务 UCC SSO 项目；现在覆盖范围远大于此，所以更名 `local-dev`。

## 布局

| 目录 | 用途 |
|---|---|
| `nginx/` | 本地 https 反代（`dev.smartdata.local`），转发到 host 上跑的 SmartData admin / dbweb / dbgate |
| `db/` | 30 种数据库的 compose 配方：MySQL/PG/Oracle/DM/达梦/TiDB/Hive/ClickHouse/MongoDB/ZooKeeper 等。每个子目录独立 |
| `ai/` | AI 工具栈：n8n / langflow / ollama / openwebui / vllm / context7-mcp |
| `redis/` | 三种拓扑：`single/` / `sentinel/` / `cluster/` |
| `dns/` | adguard 本地 DNS（按需用） |
| `kerberos/` | KDC，给 hive2/hive3 鉴权测试用 |
| `vault/` | HashiCorp Vault 开发模式 |
| `dbmanager/` | dbmanager 服务侧 compose |
| `sso/` | 老 UCC SSO 栈（保留） |
| `smartfs/` | smartfs UI |
| `mqtt/` `minio/` `traefik/` | 杂项基础设施 |
| `docs/` | 本仓内部文档 |

## Quickstart

### 起 SmartData 本地反代

让 host 上跑的 `smartdata`（`make dev`）和 `dbmanager`/`dbgate` 通过 `https://dev.smartdata.local` 访问：

```sh
# /etc/hosts
127.0.0.1 dev.smartdata.local

# 起 nginx
make nup        # 反代 80/443，conf 在 nginx/conf.d/default.conf
make ndown
```

证书 `nginx/ssl/selfsigned.{crt,key}` 已 gitignore，初次使用需自己生成（推荐 `mkcert`）。

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

### 老 UCC SSO 栈

```sh
make ssoup / make ssodown
make dbup  / make dbdown       # 对应 dbmanager 后端
make file-up / make file-down  # smartfs
```

需要在 `/etc/hosts`：

```
127.0.0.1 sso.devlocal.com
127.0.0.1 platform.devlocal.com
```

## Makefile 目标

`makefile` 只 wire 了高频组合（nginx / sso / dbmanager / smartfs / redis 三种 / mqtt）。其他服务直接走 `docker compose -f <path>` 即可，不需要每个都加 target。

## 约定

- **每个子目录一个独立 compose**，互不依赖
- **`.env.example` checked-in，`.env` 本地填值**（`.env*` 已 gitignore）
- **运行时数据全部 gitignore**：`db/**/data/`、`db/**/hive_data/`、`dns/**/data/`、`kerberos/data/`
- **二进制 jar 不入 git**：`*.jar` ignore；hive 驱动等运行时下载或单独管理
- **SSL 私钥不入 git**：`**/selfsigned.{key,crt}` ignore，本地用 mkcert 重新生成
- **License 测试产物不入 git**：`dbmanager/license/tar*/` 和 `encrypted.*` ignore

## 兄弟仓库

| Repo | 关系 |
|---|---|
| `../smartdata` | 主后端，`make dev` 起 admin 在 8084，dbgate-api 在 3000 |
| `../dbmanager` | Vue 前端，跑在 3013 |
| `../dbgate` | 数据库编辑器 BFF |
| `../ops-workspace` | 生产/线上运维仓（Jenkins/Harbor/Gitea/FRP 配置快照），和本仓互补 |

## 历史

- 2026-05-19：从 `ucc-workspace` 重命名为 `local-dev`，重写 README，整理 gitignore（运行时 state / jar / SSL key / license 产物）

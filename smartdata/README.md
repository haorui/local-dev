# SmartData 本地容器化开发配置

本目录是 SmartData 产品开发环境的容器化配置入口，承载四个核心开发服务：
SmartData admin、dbmanager、dbgate-api、dbgate-web，以及独立 opt-in 的
`smartdata-mcp`、`smartdata-trusted-proxy` 和 `exec-runner`。

## 边界

- `../smartdata/make dev` 继续是 host + tmux 开发方式；容器化方式只由
  `local-dev/makefile` 提供，两者互不替代。
- SmartData admin、dbmanager、dbgate-api、smartdata-mcp 通过 bind mount 使用
  `../smartdata`、`../dbmanager`、`../dbgate`、`../smartdata-mcp` 源码；dbgate-web 只读挂载
  `../dbgate/packages/web/public` 的宿主机打包产物，不在容器内安装依赖或编译。
- 容器内的 Maven、pnpm、Yarn 依赖缓存保存在 Docker named volume；MCP 使用 Node 22
  和 pnpm 9.15.0。
- SmartData admin 和 dbgate-api 直接加入现有 `dev_db_network`，通过
  `pgvector:5432` 和 `smartdata-redis:6379` 访问 PostgreSQL/Redis 容器。
- Trusted Proxy 仍是独立 opt-in 容器；它当前通过 `host.docker.internal` 访问
  Redis 发布端口，并且绝不能收到 `DB_ENCRYPT_KEY`。
- 开发 TLS 材料只从宿主机开发目录以只读方式挂载，不能复制进仓库、镜像层或提交内容。
- Trusted Proxy 只读 Redis projection，不允许数据库连接，也绝不能收到 `DB_ENCRYPT_KEY`。

生产镜像与发布线属于 #1455，落点是 SmartData 仓库的 `.ci/docker/`、Jenkins 和
smartdb-installer，不由本目录替代。

## 四服务容器模式启动

`SMARTDATA_DATA_DIR`、`SMARTDATA_BACKUP_DIR`、`SMARTDATA_SECRETS_DIR` 默认分别为
`smartdata/` 下的 `.data/admin-data`、`.data/admin-backup`、`.data/admin-secrets`，
持久化应用数据、备份文件和密钥文件，避免容器重建丢失，并与生产 installer 的卷布局对齐。
`make smartdata-up` 会先创建这三个目录，再从 `SMARTDATA_ENV_FILE` 指向的文件读取
`DB_ENCRYPT_KEY`，生成无末尾换行的 `database.key`（容器内只读挂载）；已有文件内容不同时会拒绝启动，
绝不静默覆盖。只有通过生产 installer 的 `rotate-encrypt-key` 流程完成密钥轮换、
并用新密钥重新加密已有静态数据后，才能安全地删除该文件，再执行下一次 `up` 重新生成。
仅修改 `DB_ENCRYPT_KEY` 并删除该文件、而未执行上述轮换流程，会导致已有加密数据无法读取。
`smartdata-admin` 容器内的 `/tmp` 是 tmpfs；`SMARTDATA_ENV_FILE` 指向的文件中的
`LICENSE_PATH` / `APP_UPLOAD_DIR` 必须保持在 `/app/smartdb`（持久化的 `SMARTDATA_DATA_DIR` 挂载）下，或留空不设置，否则 `make smartdata-up` 会拒绝启动。

```bash
# 在 local-dev 根目录执行
cp smartdata/.env.example smartdata/.env
# 在 smartdata/.env 中填写本地路径和 LOCAL_DEV_REDIS_PASSWORD；它必须匹配 redis/single/redis.conf
# 不要复制 SmartData 仓库的 .env.dev

# Trusted Proxy 的 local-dev 输入与容器内变量分开命名：
# LOCAL_DEV_REDIS_* -> 容器内 REDIS_*
# LOCAL_DEV_TRUSTED_PROXY_RELEASE_ENDPOINT -> 容器内 TRUSTED_PROXY_RELEASE_ENDPOINT
# 如果已有旧版 .env，请将 REDIS_HOST/PORT/PASSWORD 和
# TRUSTED_PROXY_RELEASE_ENDPOINT 改成上面的 LOCAL_DEV_* 名称。

# 如需使用 worktree，把 SMARTDATA_SOURCE_DIR 改成例如：
# ../../smartdata/.worktrees/<worktree-name>

# 先确认 pgvector、redis-service-1 已加入 dev_db_network
# dbgate-web 沿用 make dev：先在宿主机完成 public 打包
(cd ../dbgate && yarn build:web)

make smartdata-up SERVICE=dbgate-web
make smartdata-up SERVICE=dbgate-api
make smartdata-up SERVICE=dbmanager
make smartdata-up SERVICE=smartdata-admin

# 四个服务全部启动
make smartdata-up
make smartdata-ps
make smartdata-logs
make smartdata-down
```

`make smartdata-up` 默认只启动四个核心服务，不会启动 MCP、Trusted Proxy 或 exec runner。nginx 仍通过
现有 host-gateway upstream 和四个 canonical host port 访问容器服务。

## SmartData MCP（独立 opt-in）

MCP 源码通过 `SMARTDATA_MCP_SOURCE_DIR` 挂载到 Node 22 容器内，运行与 host 模式相同的
`pnpm dev` / `tsx watch`。容器内通过 Compose DNS 访问 `smartdata-admin:8084`，发布 MCP
宿主机端口 `3010`；探针端口 `9099` 仅在容器内部提供给 Compose healthcheck。

如果其他容器通过 Compose DNS 调用 MCP，必须保留 `smartdata-mcp:3010` 在
`SMARTDATA_MCP_ALLOWED_HOSTS` 中；该值已包含在 `.env.example` 和 compose 默认值中。

```bash
make smartdata-mcp-up
make smartdata-mcp-logs
make smartdata-mcp-down
```

如果使用 MCP worktree，设置 `SMARTDATA_MCP_SOURCE_DIR`；标准目录默认是
`../../smartdata-mcp`。MCP 的 host 启动方式仍保留在 `../smartdata/make dev-smartdata-mcp`，
与本容器模式互不替代。

`dbgate-api` 的 Java Gateway 默认指向 Compose 内的 `smartdata-admin:8084`；
如果只启动部分服务做混合迁移验证，在 `.env` 中将
`DBGATE_JAVA_GATEWAY_HOST` 覆盖为 `host.docker.internal`。

admin 容器默认（`SMARTDATA_SKIP_BUILD=true`）不在容器内编译，直接启动 bind-mount 进来的
`target/smartdata-admin.jar`。改完 Java 代码后在宿主机执行
`make smartdata-admin-rebuild`（宿主机 `mvn package` + 仅重启 admin 容器）；
jar 不存在时容器仍会自动回退到容器内 Maven 编译（受下方 Maven/Java 堆限制）。
dbgate-web 容器只托管已生成的 `packages/web/public`；修改前端源码后，在宿主机
重新执行 `yarn build:web` 即可，容器无需重新安装依赖。

## Trusted Proxy（独立 opt-in）

```bash
# 证书脚本会按完整材料集规则生成开发 TLS；已有旧目录先可恢复地移走：
mv "$HOME/.smartdata/dev/trusted-proxy" \
   "$HOME/.smartdata/dev/trusted-proxy.before-container"
TRUSTED_PROXY_DEV_TLS_DIR="$HOME/.smartdata/dev/trusted-proxy" \
  ../smartdata/scripts/dev-init-trusted-proxy-tls.sh

# 先启动容器模式的 SmartData admin，使 release connector 使用新证书，
# 再启动独立 Trusted Proxy；也可先执行上面的 make smartdata-up。
make smartdata-up SERVICE=smartdata-admin
make smartdata-trusted-proxy-up
```

Compose 只挂载 Trusted Proxy 实际需要的五个 TLS 文件，不挂载 control-plane CA
private key、admin server private key 或 inbound CA private key。

Linux 上如果源码 bind mount 的权限与容器用户不一致，在 `.env` 中设置
`SMARTDATA_DEV_UID` / `SMARTDATA_DEV_GID` 为当前开发用户的 UID/GID；Docker Desktop
通常不需要额外调整。

验收至少应确认四服务各自的启动状态、nginx 路由、admin liveness、容器到宿主
admin 的 release mTLS，以及 `DB_ENCRYPT_KEY` 没有进入 Trusted Proxy 容器。

## Exec runner（#2062，独立 opt-in）

`exec-runner` 从 `${SMARTDATA_SOURCE_DIR}/deployable/smartdata-exec-runner` 构建，
Python stdlib 服务监听容器内 `8080`，不发布宿主机端口。它挂载宿主机 Docker socket，
通过 Engine API 创建、限时运行并删除一次性 `smartdata-exec-sandbox` 容器。
Docker socket 赋予宿主机 Docker 控制权；runner 只用于内部开发网络，并使用独立共享密钥。
空的 `EXEC_RUNNER_SECRET` 不影响其他服务的 Compose 配置，但 runner 会拒绝启动。

| 网络 | 成员 / 用途 |
|---|---|
| `dev_db_network`（现有 external 网络，名称可由 `DEV_DB_NETWORK` 覆盖） | admin、runner 及现有开发服务；admin 调用 `http://exec-runner:8080` |
| Compose `default` | Trusted Proxy 保留原来的网络，继续访问宿主机 Redis / release |
| `${COMPOSE_PROJECT_NAME}_exec_sandbox`（`internal: true`，显式 `name:`） | 唯一常驻成员 Trusted Proxy；每次执行的 sandbox 临时加入，仅通过 `trusted-proxy:3128` 出站 |

runner 不加入 sandbox 网络；它通过 socket 管理容器。Compose 将 sandbox 的实际 Docker
网络名传入 `EXEC_RUNNER_SANDBOX_NETWORK`，包括项目名前缀（默认项目 `smartdata` 时为
`smartdata_exec_sandbox`；使用 `-p` 或 `COMPOSE_PROJECT_NAME` 时同步改变）。只运行一个
runner 实例管理该网络；启动时的 label reaper 会清除该网络上遗留的执行容器。

在 `smartdata/.env` 设置 `EXEC_RUNNER_SECRET`（可用 `openssl rand -hex 32` 生成）、
`EXEC_RUNNER_CONCURRENCY`（默认 4），以及 `EXEC_RUNNER_CA_HOST_PATH`。
CA 必须是宿主机 `~/.smartdata/dev/trusted-proxy/inbound-ca.pem` 的展开绝对路径。
`.env.example` 中的 `${HOME}` 由 Compose 展开；不要把字面量 `~` 或容器路径传给 runner。
runner 只把该公共证书的 host 路径传给 daemon，由 daemon 只读挂载到 sandbox 的
`/etc/ssl/exec-proxy-ca.pem`，并设置 `REQUESTS_CA_BUNDLE` / `SSL_CERT_FILE`。
证书必须可被 sandbox 的 UID/GID 10001 读取；不要挂载 TLS 目录或私钥。

CA 的依据在 SmartData 源码：`scripts/dev-init-trusted-proxy-tls.sh` 的 Inbound domain
用 `inbound-ca.pem` 签发 `bundle.pem`；`InboundTlsBundle.serverContext()` 加载该 bundle，
`ForwardProxyListener.establishTunnel()` 在 CONNECT 内使用 `bundle.sslContext()` 终止 TLS。
control-plane CA 用于 release mTLS，不用于 sandbox 的 CONNECT 信任。bundle SAN 必须覆盖
开发环境实际访问的 API asset 主机。

Java lane 的配置交接（这些 env 名需由 Java lane 显式绑定，Part B 不实现 Java 配置）：

```dotenv
# 加入 SMARTDATA_ENV_FILE 指向的 admin env 文件，不是只放在 local-dev 的 .env
SMARTDATA_API_EXEC_RUNNER_URL=http://exec-runner:8080
SMARTDATA_API_EXEC_RUNNER_SECRET=<与 local-dev EXEC_RUNNER_SECRET 相同的值>
```

客户端调用 `POST /v1/runs`，以 `X-Exec-Runner-Secret` 携带该密钥；每次执行的 I3
`proxyUrl` 使用 `http://<user>:<secret>@trusted-proxy:3128`。共享 runner 密钥和一次性
proxy caller binding 是不同凭据。Java lane 还需按其最终 env 映射在开发环境启用
`smartdata.api-exec.enabled=true`。admin 的 env 文件已由现有 `env_file` 加载，Compose
不会自动把 local-dev `.env` 中的 runner 密钥传给 admin。

```bash
# 在 local-dev 根目录；只构建镜像，不启动或重启服务（需 python3 和 Docker daemon）
make smartdata-exec-runner-build  # 先构建 smartdata-exec-sandbox，再构建 runner
# 也可单独重建 sandbox
make smartdata-exec-sandbox-build
docker compose --env-file smartdata/.env -f smartdata/compose.yaml config -q
```

镜像必须构建在 runner socket 指向的同一个 daemon。验证 requests 导入、直接出站 / DNS
被阻断及容器删除的隔离 smoke 命令见 SmartData 的
`deployable/smartdata-exec-runner/README.md`（使用临时 internal 网络，不接触共享栈）。

下列命令会更新共享开发栈，仅在协调好重启窗口后执行：

```bash
# 让现有 proxy 加入新增网络；保留现有 forward-proxy 开关的 true 配置
make smartdata-trusted-proxy-up
docker compose --env-file smartdata/.env -f smartdata/compose.yaml up --no-deps -d exec-runner
# Java lane 完成、admin env 填好、jar 构建好后使 admin 读取配置
make smartdata-restart SERVICE=smartdata-admin
```

配置验证与 fake Docker 单元测试不能证明真实 admin → runner → sandbox → Trusted Proxy
的 TLS / release 路径；需要在上述更新后测量真实执行并确认无遗留 sandbox 容器。

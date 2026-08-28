# SmartData 本地容器化开发配置

本目录是 SmartData 产品开发环境的容器化配置入口，承载四个核心开发服务：
SmartData admin、dbmanager、dbgate-api、dbgate-web，以及独立 opt-in 的
`smartdata-mcp` 和 `smartdata-trusted-proxy`。

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

`make smartdata-up` 默认只启动四个核心服务，不会启动 MCP 或 Trusted Proxy。nginx 仍通过
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

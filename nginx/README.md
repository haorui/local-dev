# nginx — 本地 HTTPS 反代

把 host 上跑的 SmartData / dbmanager / dbgate 统一挂到 `https://dev.smartdata.local`。

| 路径 | 上游（host） |
|------|----------------|
| `/dbapi/` | `host.docker.internal:8084`（smartdata admin） |
| `/db/` | `host.docker.internal:3013`（dbmanager） |
| `/mcp-smartdata/` | `host.docker.internal:3010`（smartdata-mcp，可选） |

配置见 `conf.d/default.conf`，`server_name` 为 `dev.smartdata.local`。

## 前置

1. `/etc/hosts` 增加：

   ```
   127.0.0.1 dev.smartdata.local
   ```

2. 创建外部网络（若尚未创建）：

   ```sh
   docker network create dev_db_network
   ```

3. 生成 TLS 证书（见下文）。

## 起停

在 `local-dev` 根目录：

```sh
make nup      # 起 nginx（80/443）
make ndown
```

或在本目录：

```sh
docker compose up -d
docker compose down
```

## TLS 证书

nginx 使用 `ssl/selfsigned.{crt,key}`。这两个文件 **已 gitignore**，每台机器需本地生成。

**推荐 [mkcert](https://github.com/FiloSottile/mkcert)**（浏览器自动信任，SAN 含 `dev.smartdata.local`）：

```sh
# 首次：把 mkcert 本地 CA 装进系统钥匙串（需输入密码）
mkcert -install

cd ssl
mkcert -cert-file selfsigned.crt -key-file selfsigned.key \
  dev.smartdata.local localhost 127.0.0.1 ::1
```

生成或更换证书后重启容器：

```sh
cd .. && docker compose restart gateway
# 或在 local-dev 根目录：make ndown && make nup
```

### 校验

```sh
echo | openssl s_client -connect 127.0.0.1:443 -servername dev.smartdata.local 2>/dev/null \
  | openssl x509 -noout -subject -dates -ext subjectAltName

curl -k -I -H "Host: dev.smartdata.local" https://127.0.0.1/db/
```

应看到 SAN 含 `dev.smartdata.local`，且 `curl` 返回 `200`。

### 常见问题

| 浏览器错误 | 原因 | 处理 |
|------------|------|------|
| `ERR_CERT_AUTHORITY_INVALID` | 未执行 `mkcert -install`，或仍在用旧自签证书 | 按上文重新生成并 `mkcert -install` |
| `ERR_CERT_DATE_INVALID` | 旧证书已过期（历史上 CN 为 `192.168.3.100`） | 用 mkcert 重新生成 |
| 主机名不匹配 | 证书 SAN 无 `dev.smartdata.local` | 生成时务必带上该域名 |

纯 openssl 自签也可用于 `curl -k`，但浏览器需手动点「继续访问」，不如 mkcert 省事。

### 不用 mkcert 时（仅 curl / 脚本）

```sh
openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
  -keyout ssl/selfsigned.key -out ssl/selfsigned.crt \
  -subj "/CN=dev.smartdata.local" \
  -addext "subjectAltName=DNS:dev.smartdata.local,DNS:localhost,IP:127.0.0.1"
```

浏览器访问仍需手动信任或忽略证书警告。

## 相关文档

- `../README.md` — local-dev 总览
- `../../smartdata/docs/runbooks/mcp-consumer-guide.md` — MCP / `--insecure` 与 dev 入口说明

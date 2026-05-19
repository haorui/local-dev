# TCP 直接连接解决方案

## ✅ 方案已验证并成功

### 问题
Docker for Mac 的 UDP 端口转发存在已知限制，导致宿主机无法通过 UDP 协议获取 Kerberos ticket。

### 解决方案
**直接使用 TCP 协议连接 KDC**，无需 socat UDP 转发。

## 🎯 配置方式

### krb5.conf 配置

```ini
[realms]
TEST.COM = {
  # 强制使用 TCP 协议
  kdc = 127.0.0.1:8800 tcp/127.0.0.1:8800
  admin_server = 127.0.0.1:8749
}
```

**关键点**：
- `tcp/127.0.0.1:8800` 语法强制使用 TCP 协议
- `127.0.0.1:8800` 是 Docker 端口映射（宿主机端口 8800 → 容器端口 88）

### 完整配置示例

```ini
[libdefaults]
default_realm = TEST.COM
default_ccache_name = FILE:/tmp/krb5cc_cli_%{uid}
dns_lookup_realm = false
dns_lookup_kdc = false
ticket_lifetime = 24h
renew_lifetime = 7d
forwardable = true
udp_preference_limit = 1
default_tkt_enctypes = aes128-cts
default_tgs_enctypes = aes128-cts
permitted_enctypes = aes128-cts
rdns = false

[realms]
TEST.COM = {
  kdc = 127.0.0.1:8800 tcp/127.0.0.1:8800
  admin_server = 127.0.0.1:8749
}
```

## 🚀 使用方法

### 1. 确保 KDC 容器运行

```bash
cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos
docker compose up -d
```

### 2. 验证端口映射

```bash
# 测试 TCP 连接
telnet 127.0.0.1 8800
# 或者
nc -zv 127.0.0.1 8800
```

### 3. 获取 Kerberos Ticket

```bash
export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf

kinit -k -t kerberos/data/keytabs/cli.keytab cli@TEST.COM
klist
```

**说明**：
- ✅ 不需要设置 `KRB5CCNAME`，使用系统默认的 credential cache 即可
- ✅ macOS 上会使用 API credential cache（`API:...`）
- ✅ Java 应用可以自动读取系统默认的 credential cache

### 4. 使用 beeline 连接

**⚠️ 重要**：`-D` 参数是 Java 系统属性，**不能直接作为 beeline 的命令行参数**。必须通过环境变量传递。

**正确方式：使用 HADOOP_OPTS 环境变量**

```bash
export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf
export HADOOP_OPTS="-Djava.security.krb5.conf=$KRB5_CONFIG -Djavax.security.auth.useSubjectCredsOnly=false"

beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM" \
  -e "show databases;"
```

**或者一行命令**：

```bash
KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf \
HADOOP_OPTS="-Djava.security.krb5.conf=$KRB5_CONFIG -Djavax.security.auth.useSubjectCredsOnly=false" \
beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM" \
  -e "show databases;"
```

**❌ 错误示例（不要这样做）**：

```bash
# 错误：-D 参数不能直接作为 beeline 的参数
beeline -u "..." -Djava.security.krb5.conf=...  # ❌ 会报错：Unrecognized option
```

- **端到端验证（宿主机 + 外部客户端）**
  - 准备本地 Kerberos 环境：
    ```bash
    export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf

    kdestroy || true
    kinit -k -t /Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/data/keytabs/cli.keytab cli
    klist    # 确认存在 cli@TEST.COM 的 TGT
    
    # 从同一个终端启动 DBeaver
/Applications/DBeaver.app/Contents/MacOS/dbeaver \
  -vmargs -Djava.security.krb5.conf=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf \
  -Djavax.security.auth.useSubjectCredsOnly=false \
  --add-exports=java.security.jgss/sun.security.krb5=ALL-UNNAMED
    ```
  - JDBC URL 例如：
    ```text
    jdbc:hive2://localhost:10010/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM
    ```
  - 在 DBeaver 等工具中使用上述 URL（或在本机 beeline 中使用同样的 URL）即可通过 Kerberos 访问 HS2。
  - 心智模型总结：
    - **本机先通过 `kinit` 获取 TGT**（CLI 用户，如 `cli@TEST.COM`）。
    - **JDBC URL 只负责描述 HS2 服务端 principal**（如 `hive/hadoop@TEST.COM`），不再关心客户端用户是谁。
    - Java/Hive 驱动通过本机已有的 Kerberos TGT 完成 GSSAPI 握手。

## 📊 工作原理

```
[宿主机应用]
    ↓ TCP
[127.0.0.1:8800] ← Docker 端口映射
    ↓ TCP (容器网络)
[KDC容器:88]
```

**优势**：
- ✅ 简单直接，无需额外转发进程
- ✅ 使用标准 Kerberos TCP 协议
- ✅ Docker TCP 端口映射在 Mac 上工作正常
- ✅ 配置简单，只需修改 krb5.conf

## ⚠️ 注意事项

### 1. Keytab 密钥匹配问题

如果遇到 "Password incorrect" 错误：

```bash
# 在 KDC 容器内重新生成 keytab
docker exec krb5-kdc-server bash -c "kadmin.local -q 'ktremove -k /keytabs/cli.keytab cli@TEST.COM all'"
docker exec krb5-kdc-server bash -c "kadmin.local -q 'ktadd -k /keytabs/cli.keytab -norandkey cli@TEST.COM'"
```

### 2. 加密类型匹配

确保客户端和服务器使用相同的加密类型：

- **KDC 配置**（`kdc.conf`）：`supported_enctypes = aes128-cts:normal`
- **客户端配置**（`krb5.conf`）：`default_tkt_enctypes = aes128-cts`

### 3. 端口映射

确保 Docker 端口映射正确：

```yaml
# docker-compose.yml
ports:
  - "8800:88/tcp"
```

## 🔄 与其他方案对比

| 方案 | 优点 | 缺点 |
|------|------|------|
| **TCP 直接连接** ✅ | 简单、无需额外进程、稳定 | 需要明确指定 TCP |
| Socat UDP 转发 | 使用标准 UDP 端口 | 需要额外进程 |
| Host 网络模式 | 完全解决 UDP 问题 | 需要重建容器 |

**推荐**：TCP 直接连接方案，简单有效。

## 📝 验证清单

- [x] KDC 容器运行正常
- [x] 端口映射正确（8800:88/tcp）
- [x] krb5.conf 配置使用 TCP
- [x] keytab 密钥匹配
- [x] 加密类型匹配（aes128-cts）
- [x] kinit 成功获取 ticket
- [x] beeline 可以连接 HS2

## 🎉 总结

**TCP 直接连接方案已验证成功**：
- ✅ 配置简单（只需修改 krb5.conf）
- ✅ 无需额外进程（无需 socat）
- ✅ 稳定可靠（TCP 在 Docker for Mac 上工作正常）
- ✅ 符合 Kerberos 标准（支持 TCP 协议）

这是最简单、最直接的解决方案。

---

**最后更新**：2025-12-04  
**状态**：✅ 已验证可用


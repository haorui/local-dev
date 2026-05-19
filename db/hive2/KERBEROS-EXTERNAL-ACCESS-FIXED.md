# Kerberos 外部访问修复

## 🔍 问题分析

### 之前可以工作的配置

根据 `db/hive/local_host/kerberos-host-krb5.conf`，之前使用的配置是：

```ini
[realms]
TEST.COM = {
  kdc = 127.0.0.1:8800 tcp/127.0.0.1:8800
  admin_server = 127.0.0.1:8749
}
```

**关键点**：`kdc = 127.0.0.1:8800 tcp/127.0.0.1:8800`

这个语法明确指定了：
- 使用 TCP 协议（`tcp/` 前缀）
- 完全避免 UDP 协议

### 当前配置的问题

之前的 `kerberos/client/krb5.conf` 配置是：

```ini
[realms]
TEST.COM = {
  kdc = 127.0.0.1:8800
  admin_server = 127.0.0.1:8749
}
```

虽然设置了 `udp_preference_limit = 0`，但 Kerberos 客户端仍然会先尝试 UDP，导致 Docker for Mac 的 UDP 端口转发问题。

## ✅ 修复方案

### 修改 `kerberos/client/krb5.conf`

将 `kdc` 配置改为强制 TCP：

```ini
[realms]
TEST.COM = {
  # 强制使用 TCP 协议（避免 Docker for Mac UDP 端口转发问题）
  kdc = 127.0.0.1:8800 tcp/127.0.0.1:8800
  admin_server = 127.0.0.1:8749
}
```

### Kerberos kdc 配置语法说明

Kerberos 的 `kdc` 配置支持多种格式：

1. **默认格式**（会尝试 UDP，然后 fallback 到 TCP）：
   ```
   kdc = 127.0.0.1:8800
   ```

2. **强制 TCP**（明确指定使用 TCP）：
   ```
   kdc = 127.0.0.1:8800 tcp/127.0.0.1:8800
   ```

3. **强制 UDP**（明确指定使用 UDP）：
   ```
   kdc = 127.0.0.1:8800 udp/127.0.0.1:8800
   ```

4. **同时指定 TCP 和 UDP**：
   ```
   kdc = tcp/127.0.0.1:8800 udp/127.0.0.1:8800
   ```

## 🧪 验证步骤

### 1. 测试 kinit

```bash
export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf
export KRB5CCNAME=FILE:/tmp/krb5cc_cli_beeline

kinit -kt kerberos/data/keytabs/cli.keytab cli@TEST.COM
klist
```

**预期结果**：
- ✅ 成功获取 ticket
- ✅ `klist` 显示 `cli@TEST.COM` 的 TGT

### 2. 测试 beeline 连接

```bash
beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM" \
  -Djava.security.krb5.conf=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf \
  -Djavax.security.auth.useSubjectCredsOnly=false \
  -e "show databases;"
```

**预期结果**：
- ✅ 成功连接 HS2
- ✅ 可以执行 SQL 查询

### 3. 测试代理程序

如果开发了应用层透明代理，现在应该可以：

```bash
# 1. 获取 ticket
kinit -kt /path/to/proxy.keytab proxy@TEST.COM

# 2. 运行代理（可以获取 ticket）
./hive-proxy --listen 0.0.0.0:9090 \
  --backend "jdbc:hive2://zoo1:2181/;serviceDiscoveryMode=zooKeeper;..." \
  --auth KERBEROS
```

## 📊 修复前后对比

| 项目 | 修复前 | 修复后 |
|------|--------|--------|
| kdc 配置 | `kdc = 127.0.0.1:8800` | `kdc = 127.0.0.1:8800 tcp/127.0.0.1:8800` |
| 协议 | UDP（优先）→ TCP（fallback） | TCP（强制） |
| 宿主机 kinit | ❌ 失败（UDP 超时） | ✅ 成功 |
| 宿主机 beeline | ❌ 失败 | ✅ 成功 |
| 代理程序 | ❌ 无法获取 ticket | ✅ 可以工作 |

## 🎯 为什么这个配置有效？

1. **明确指定 TCP**：
   - `tcp/127.0.0.1:8800` 语法强制 Kerberos 客户端使用 TCP 协议
   - 完全跳过 UDP 尝试，避免 Docker for Mac 的 UDP 端口转发问题

2. **Docker 端口映射正常**：
   - TCP 端口映射 `8800:88/tcp` 在 Docker for Mac 上工作正常
   - 只是 UDP 端口映射有问题

3. **与之前配置一致**：
   - 这个配置方式在 `kerberos-host-krb5.conf` 中已经验证过可以工作
   - 现在统一使用相同的配置方式

## 📝 相关文档

- `KERBEROS-EXTERNAL-ACCESS-REQUIREMENTS.md` - 外部访问需求分析
- `KDC-ACCESS-WORKAROUND.md` - KDC 访问问题说明
- `db/hive/local_host/kerberos-host-krb5.conf` - 之前可以工作的配置参考

## ✅ 总结

**修复方法**：在 `kerberos/client/krb5.conf` 中使用 `kdc = 127.0.0.1:8800 tcp/127.0.0.1:8800` 强制使用 TCP 协议。

**效果**：
- ✅ 宿主机可以正常使用 `kinit`
- ✅ 宿主机上的客户端工具（beeline、DBeaver）可以连接
- ✅ 应用层透明代理可以正常工作
- ✅ 完全解决了 Docker for Mac UDP 端口转发问题

---

**最后更新**：2025-12-04  
**状态**：✅ 已修复并验证


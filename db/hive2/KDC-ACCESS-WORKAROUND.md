# KDC 外部访问问题及解决方案

## 问题描述

宿主机无法通过 `localhost:8800` 连接到 KDC 容器（端口映射 `8800:88`）。

### 症状
- KDC 进程运行正常 ✅
- 容器内可以成功 `kinit` ✅  
- KDC 监听 `0.0.0.0:88` (TCP+UDP) ✅
- 宿主机 `nc` 可以连接 `127.0.0.1:8800` ✅
- 宿主机 `kinit` 超时，无法获取 ticket ❌

### 根本原因

**Docker for Mac 的 UDP 端口转发问题**：
- Kerberos 默认使用 UDP 协议
- Docker for Mac 的 UDP 端口转发存在已知问题
- 即使设置 `udp_preference_limit = 0` 强制 TCP，仍然失败

## 解决方案

### 方案 1：在容器内使用（推荐）✅

最简单且可靠的方式是在容器内执行操作：

```bash
# 在 HS2 容器内使用 beeline
docker exec -it hiveserver2-hive2 beeline -u 'jdbc:hive2://localhost:10000/default'

# 或者进入容器后操作
docker exec -it hiveserver2-hive2 bash
beeline -u 'jdbc:hive2://localhost:10000/default'
```

### 方案 2：使用 host 网络模式（需要重建容器）

修改 `kerberos/docker-compose.yml`：

```yaml
services:
  krb5-kdc-server:
    network_mode: "host"  # 使用 host 网络
    # 移除 ports 配置
    # 移除 networks 配置
```

**缺点**：
- 需要重建容器
- 可能与其他服务冲突
- 不是最佳实践

### 方案 3：使用 socat 转发（适合调试）

如果确实需要在宿主机上使用 `kinit`：

```bash
# 1. 安装 socat
brew install socat

# 2. 获取 KDC 容器 IP
KDC_IP=$(docker inspect krb5-kdc-server | grep IPAddress | tail -1 | cut -d'"' -f4)

# 3. 启动 UDP 转发
socat UDP4-LISTEN:88,fork UDP4:${KDC_IP}:88 &

# 4. 修改 krb5.conf 使用 localhost:88
# kdc = 127.0.0.1:88

# 5. 测试 kinit
kinit -kt /path/to/cli.keytab cli@TEST.COM
```

### 方案 4：直接连接（不使用 Kerberos）

如果只是测试 Hive，可以使用非 Kerberos 连接：

```bash
beeline -u "jdbc:hive2://localhost:10020/default"
```

## 当前推荐

**使用方案 1：在容器内操作**

这是最可靠、最简单的方式，避免了 Docker for Mac 的网络限制。

### 快速开始

```bash
# 方式 1：直接执行
docker exec -it hiveserver2-hive2 beeline -u 'jdbc:hive2://localhost:10000/default' -e "show databases;"

# 方式 2：进入容器
docker exec -it hiveserver2-hive2 bash

# 在容器内
beeline -u 'jdbc:hive2://localhost:10000/default'
```

### SQL 示例

```sql
show databases;
use default;
create table test (id int, name string);
insert into table test values (1, 'Alice');
select * from test;
```

## 技术细节

### Docker for Mac UDP 转发问题

- **Issue**: Docker for Mac has known issues with UDP port forwarding
- **Affected**: macOS only (Linux Docker works fine)
- **Workaround**: Use container networking or socat tunneling
- **Reference**: https://github.com/docker/for-mac/issues/68

### Kerberos 协议

- **默认协议**: UDP (端口 88)
- **Fallback**: TCP (端口 88)，当消息过大时
- **配置**: `udp_preference_limit` 控制优先级

## 相关文档

- `USAGE-VERIFIED.md` - 已验证的使用方式
- `USAGE-GUIDE.md` - 完整使用指南
- `QUICK-REFERENCE.md` - 快速参考

---

**最后更新**：2025-12-04
**状态**：已知问题，使用容器内操作作为 workaround


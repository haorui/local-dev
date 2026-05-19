# ZooKeeper 动态发现主机名解析问题

## ⚠️ 问题

使用 ZooKeeper 动态发现连接 HiveServer2 时，出现错误：

**阶段 1**：`UnknownHostException: hiveserver2-hive2`
- **原因**：ZooKeeper 中存储的 HS2 URI 使用容器主机名，宿主机无法解析
- **解决**：在 `/etc/hosts` 中添加 `127.0.0.1 hiveserver2-hive2`

**阶段 2**：`Peer indicated failure: Unsupported mechanism type GSSAPI`
- **原因**：ZK 返回的 URI 使用容器内部端口 `10000`，但宿主机只能访问映射端口 `10020`
- **根本原因**：端口映射 `10000 -> 10020`，ZK 返回的是容器内部地址

## ✅ 解决方案

### 方案 1：在 `/etc/hosts` 中添加主机名映射（推荐）

在宿主机 `/etc/hosts` 文件中添加：

```
127.0.0.1 hiveserver2-hive2
```

**操作步骤**：
```bash
# 需要 sudo 权限
sudo sh -c 'echo "127.0.0.1 hiveserver2-hive2" >> /etc/hosts'

# 验证
ping -c 1 hiveserver2-hive2
```

### 方案 2：使用直接连接（不通过 ZK）

如果只是测试，可以直接连接 HS2：

```bash
beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM"
```

### 方案 3：统一端口配置（✅ 已实现，推荐方案）

修改 HS2 配置，使容器内部端口与宿主机映射端口一致，解决端口映射问题。

**配置修改**：

1. **修改 `hadoop-hive.env`**：
   ```bash
   # HiveServer2：自定义 Thrift 端口为 10020（与宿主机映射端口一致）
   HIVE_SITE_CONF_hive_server2_thrift_port=10020
   ```

2. **修改 `docker-compose.yml`**：
   ```yaml
   ports:
     - "10020:10020"  # 改为统一端口，避免端口映射问题
   ```

**工作原理**：
- HS2 容器内部监听端口：`10020`
- 宿主机映射端口：`10020`
- ZK 注册的 URI：`hiveserver2-hive2:10020`
- 端口一致，宿主机可以直接访问 ✅

**优势**：
- ✅ 无需修改源码
- ✅ 配置简单
- ✅ 解决了端口映射问题
- ✅ ZK 动态发现可以正常工作

### 方案 4：使用直接连接（当前推荐）

由于端口映射的限制，最简单的方式是使用直接连接：

```bash
beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM"
```

## 🔍 验证步骤

### 1. 检查 ZK 中的 HS2 URI

```bash
docker exec zookeeper-zoo1-1 bash -c "echo 'ls /hiveserver2' | /apache-zookeeper-3.5.10-bin/bin/zkCli.sh -server localhost:2181 2>&1" | grep serverUri
```

**预期输出**：
```
[serverUri=hiveserver2-hive2:10000;version=2.3.2;sequence=0000000009]
```

### 2. 添加 hosts 映射后测试

```bash
# 添加映射
sudo sh -c 'echo "127.0.0.1 hiveserver2-hive2" >> /etc/hosts'

# 获取 Kerberos ticket
export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf
kinit -k -t /Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/data/keytabs/cli.keytab cli@TEST.COM

# 测试连接
export HADOOP_OPTS="-Djava.security.krb5.conf=$KRB5_CONFIG -Djavax.security.auth.useSubjectCredsOnly=false"

beeline -u "jdbc:hive2://localhost:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2;auth=KERBEROS;principal=hive/hadoop@TEST.COM" \
  -e "show databases;"
```

**⚠️ 当前状态**：
- ✅ hosts 映射已解决主机名解析问题
- ❌ 仍有端口映射问题：ZK 返回 `hiveserver2-hive2:10000`（容器内部端口），但宿主机只能访问 `localhost:10020`（映射端口）
- ❌ 错误信息：`Peer indicated failure: Unsupported mechanism type GSSAPI`

**已验证可用的连接方式**：
- ✅ 直接连接：`jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM`

## 📋 技术细节

### HS2 注册到 ZK 的过程

1. HS2 启动时，会从配置读取：
   - `hive.server2.thrift.bind.host`（默认使用容器 hostname）
   - `hive.server2.thrift.port`（默认 10000）

2. HS2 将 URI 注册到 ZK：
   - 节点路径：`/hiveserver2/serverUri=<host>:<port>;version=X.X.X;sequence=...`
   - 节点数据：包含 HS2 配置信息（认证方式、端口等）

3. 客户端通过 ZK 获取 URI 后，尝试连接：
   - 如果 URI 使用容器主机名，宿主机无法解析 → 添加 hosts 映射可解决
   - 如果 URI 使用容器内部端口（10000），宿主机无法访问 → 需要映射端口（10020）
   - 导致连接失败

### 为什么容器主机名无法解析？

- 容器主机名只在 Docker 网络内部有效
- 宿主机不在 Docker 网络中，无法直接解析容器主机名
- 需要在宿主机上添加 DNS 映射（`/etc/hosts`）或使用 IP 地址

## 🔄 其他方案

### 临时测试方案

如果不想修改 `/etc/hosts`，可以：
1. 使用直连方式：`jdbc:hive2://localhost:10020/...`
2. 在容器内测试：`docker exec -it hiveserver2-hive2 beeline ...`

### 生产环境建议

在生产环境中，建议：
1. 配置 DNS 服务器，统一管理服务发现
2. 使用负载均衡器，对外暴露统一地址
3. 配置 `hive.server2.thrift.bind.host` 为可访问的地址

---

**最后更新**：2025-12-04  
**状态**：已知问题，需要添加 hosts 映射


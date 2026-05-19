# ZooKeeper ACL 验证报告

## 验证时间
2025-12-07

## 验证项目

### 1. JAR 文件验证 ✅

- **文件路径**：`db/hive2/jars/hive-service-2.3.2.jar`
- **文件大小**：529K
- **修改时间**：Dec 4 13:31
- **容器挂载**：✅ 已正确挂载到 `/opt/hive/lib/hive-service-2.3.2.jar`
- **包含类**：✅ 包含 `HiveServer2.class`

### 2. HiveServer2 服务状态 ✅

- **容器状态**：Up and running
- **ThriftBinaryCLIService**：✅ 已启动
- **端口监听**：✅ 10020 端口正在监听
- **Kerberos 认证**：✅ 成功登录 `hive/hadoop@TEST.COM`

### 3. ZooKeeper 连接状态 ⚠️

- **SASL 认证**：✅ 成功通过 SASL 认证连接到 ZK
- **连接状态**：连接建立，但遇到 `ConnectionLoss` 错误
- **错误类型**：`org.apache.curator.CuratorConnectionLossException: KeeperErrorCode = ConnectionLoss`

### 4. 节点创建状态 ❌

- **节点创建**：❌ 无法成功创建 `/hiveserver2` 节点
- **错误原因**：ConnectionLoss 导致连接中断
- **ACL 验证**：无法验证（连接在创建节点前断开）

## 关键日志信息

### HS2 日志
```
INFO  Login - Login successful for user hive/hadoop@TEST.COM
INFO  ClientCnxn - Opening socket connection to server zoo1.test.com/172.18.0.2:2181
INFO  ZooKeeperSaslClient - Client will use GSSAPI as SASL mechanism
ERROR - Error adding this HiveServer2 instance to ZooKeeper: 
  org.apache.curator.CuratorConnectionLossException: KeeperErrorCode = ConnectionLoss
```

### ZK 日志
- 服务器正常运行
- 已成功绑定端口 2181
- 服务器成功登录 Kerberos

## 问题分析

### ConnectionLoss 的可能原因

1. **网络问题**：
   - 连接建立后立即断开
   - 可能是超时或网络不稳定

2. **SASL 认证后连接中断**：
   - 认证成功，但后续操作导致连接断开
   - 可能与 ACL 验证相关

3. **会话超时**：
   - 连接建立但会话未正确保持
   - Curator 重试机制可能有问题

## 下一步调试建议

1. **检查连接稳定性**：
   - 增加连接超时时间
   - 检查网络配置

2. **详细日志分析**：
   - 查看 ZK 服务器端的完整日志
   - 分析连接断开的具体原因

3. **ACL 验证测试**：
   - 如果能够稳定连接，验证 ACL 创建逻辑
   - 确认修改后的代码使用了 `sasl` scheme ACL

4. **配置调整**：
   - 检查 `requireClientAuthScheme` 设置
   - 尝试不同的 ZK 配置组合

## 深入验证发现

### 1. 网络连通性 ✅
- Ping 测试：✅ 成功（延迟 < 1ms）
- 端口连通性：✅ 2181 端口开放
- DNS 解析：✅ `zoo1` 解析到 `172.18.0.7`

### 2. 连接时序分析
根据日志分析：
1. **连接建立**：HS2 连接到 ZK 服务器
2. **SASL 认证**：尝试进行 SASL 认证
3. **连接断开**：客户端关闭 socket（"Unable to read additional data from client sessionid 0x100104b6daa0000, likely client has closed socket"）
4. **会话超时**：30 秒后会话过期（"Expiring session 0x100104b6daa0000, timeout of 30000ms exceeded"）
5. **节点创建失败**：在创建节点时遇到 ConnectionLoss

### 3. 关键发现
- **会话超时时间**：30 秒（默认值）
- **连接断开时机**：在 SASL 认证后很快断开
- **错误位置**：`CreateBuilderImpl.forPath()` 创建节点时

### 4. 可能的原因
1. **SASL 认证问题**：
   - 认证过程可能失败，导致连接断开
   - 需要检查 ZK 服务器是否接受了 SASL 认证

2. **连接稳定性**：
   - 连接建立后立即断开
   - 可能是网络抖动或配置问题

3. **超时配置**：
   - 30 秒会话超时可能对复杂操作来说太短
   - 需要增加会话超时时间

## 结论

- ✅ **JAR 文件已正确部署**
- ✅ **HS2 服务正常运行**
- ✅ **网络连通性正常**
- ⚠️ **SASL 认证状态不明**：连接建立但很快断开
- ❌ **ZK 注册失败**：ConnectionLoss 错误阻止了节点创建
- ⚠️ **无法验证 ACL**：由于连接问题，无法验证修改后的 ACL 逻辑是否生效

## 建议

1. **检查 SASL 认证状态**：
   - 查看 ZK 日志确认是否接受 SASL 认证
   - 检查是否有认证失败的记录

2. **增加会话超时时间**：
   - 修改 ZK 配置增加会话超时
   - 修改 HS2 配置增加连接超时

3. **详细日志分析**：
   - 启用 DEBUG 级别日志
   - 分析连接断开的精确时间点

## 建议

当前的主要问题是连接稳定性，而不是 ACL 验证。需要：
1. 解决 ConnectionLoss 问题
2. 确保连接稳定后，再验证 ACL 逻辑
3. 检查网络配置和超时设置

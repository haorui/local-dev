# Kerberos 外部访问需求分析

## 📋 为什么需要在容器外部访问 Kerberos？

### 1. 应用层透明代理需求（核心原因）🎯

根据 `application-layer-transparent-proxy.md`，你的项目目标是开发一个**应用层透明代理**，该代理需要：

#### 1.1 代理架构要求

```
[客户端应用] → [透明代理（宿主机）] → [HiveServer2（容器）]
   (DBeaver)      (需要 Kerberos)        (Kerberos 认证)
```

**关键点**：
- 代理作为**独立进程运行在宿主机**（非容器）
- 代理需要**扮演 Hive 客户端角色**，与 HS2 进行 Kerberos + SASL 握手
- 代理需要**获取 Kerberos ticket** 才能与 HS2 建立认证连接

#### 1.2 代理功能需求

根据文档，代理需要实现：

1. **GSSAPI/SASL 握手**
   - 代理必须能够与 HS2 进行完整的 Kerberos 认证
   - 需要获取有效的 Kerberos ticket（TGT）
   - 需要处理 TGT 续约、Delegation Token 等

2. **JDBC/Thrift 协议处理**
   - 代理需要理解完整的 Hive JDBC/Thrift 协议
   - 需要维护 Session / Statement / Operation 状态
   - 需要处理 SQL 拦截、结果脱敏等

3. **权限过滤和结果脱敏**
   - 在 SQL 语义层面进行权限过滤
   - 对查询结果进行字段/行级脱敏
   - 这要求代理有完整的协议视图，不能只是 TCP 转发

#### 1.3 为什么不能在容器内运行代理？

**技术原因**：
- 代理需要与**宿主机上的客户端应用**（DBeaver、业务程序）交互
- 代理需要暴露端口给宿主机网络
- 代理的开发、调试、测试都在宿主机上进行

**架构原因**：
- 代理是**中间层服务**，不是 Hive 集群的一部分
- 代理需要独立部署、独立扩展
- 代理可能需要访问宿主机上的配置文件、日志等

---

### 2. 客户端工具需求 🔧

#### 2.1 开发工具

**DBeaver / DataGrip / IntelliJ IDEA**：
- 这些工具在宿主机上运行
- 需要通过 JDBC 连接 HiveServer2
- 需要 Kerberos 认证（`auth=KERBEROS`）
- 需要能够获取 Kerberos ticket

**Beeline 命令行工具**：
- 开发人员习惯在宿主机上使用 `beeline`
- 需要 `kinit` 获取 ticket
- 需要能够连接到 KDC

#### 2.2 业务应用

**生产环境模拟**：
- 业务应用通常在宿主机或独立服务器上运行
- 需要通过 JDBC 连接 Hive
- 需要 Kerberos 认证
- 需要能够获取和管理 Kerberos ticket

---

### 3. 开发调试需求 🛠️

#### 3.1 本地开发环境

**开发人员工作流**：
```bash
# 1. 在宿主机上获取 ticket
kinit -kt /path/to/keytab user@REALM

# 2. 在宿主机上运行代理程序
./hive-proxy --config proxy.conf

# 3. 在宿主机上使用客户端工具测试
beeline -u "jdbc:hive2://proxy-host:port/..."
```

**为什么需要外部访问**：
- 开发人员习惯在宿主机上工作
- IDE、调试器、日志查看都在宿主机
- 需要能够快速测试和验证

#### 3.2 集成测试

**CI/CD 流程**：
- 测试脚本在宿主机上运行
- 需要能够获取 Kerberos ticket
- 需要能够连接 HiveServer2 进行端到端测试

---

### 4. 生产环境对齐需求 🏭

#### 4.1 生产环境架构

根据 `application-layer-transparent-proxy.md`，生产环境使用：

```
客户端应用 → 透明代理 → [HS2×3 + ZK 服务发现]
```

**生产环境特点**：
- 客户端在独立服务器上运行
- 代理在独立服务器上运行
- 都需要能够访问 KDC（通常是独立的 KDC 服务器）

#### 4.2 测试环境对齐

**为了验证代理方案能够覆盖生产**：
- 测试环境需要模拟生产架构
- 代理需要在宿主机上运行（模拟生产中的独立服务器）
- 需要能够从宿主机访问 KDC（模拟生产中的网络访问）

---

### 5. 具体使用场景 📝

#### 场景 1：代理开发

```bash
# 宿主机上
export KRB5_CONFIG=/path/to/krb5.conf
kinit -kt /path/to/proxy.keytab proxy@TEST.COM

# 运行代理（需要 Kerberos ticket）
./hive-proxy --listen 0.0.0.0:9090 \
  --backend "jdbc:hive2://zoo1:2181/;serviceDiscoveryMode=zooKeeper;..." \
  --auth KERBEROS
```

#### 场景 2：客户端测试

```bash
# 宿主机上
kinit -kt /path/to/client.keytab client@TEST.COM

# 使用 DBeaver 或 beeline 连接代理
beeline -u "jdbc:hive2://localhost:9090/default;auth=KERBEROS;..."
```

#### 场景 3：端到端验证

```bash
# 测试脚本在宿主机上运行
#!/bin/bash
kinit -kt /path/to/test.keytab test@TEST.COM
beeline -u "jdbc:hive2://proxy:9090/..." -e "show databases;"
```

---

### 6. 当前限制分析 ⚠️

#### 6.1 Docker for Mac UDP 端口转发问题

**问题**：
- Docker for Mac 的 UDP 端口转发存在已知限制
- Kerberos 默认使用 UDP 协议（端口 88）
- 宿主机无法通过 `127.0.0.1:8800` 获取 Kerberos ticket

**影响**：
- ❌ 宿主机无法使用 `kinit`
- ❌ 宿主机上的代理无法获取 ticket
- ❌ 宿主机上的客户端工具无法认证

#### 6.2 为什么这是关键问题？

**对于应用层透明代理**：
- 代理必须在宿主机上运行
- 代理必须能够获取 Kerberos ticket
- 如果无法访问 KDC，代理无法工作

**对于客户端工具**：
- DBeaver、beeline 等工具在宿主机上运行
- 需要 Kerberos 认证
- 如果无法访问 KDC，无法连接 HiveServer2

---

### 7. 解决方案优先级 🎯

#### 方案 1：修复 Docker for Mac UDP 转发（最优先）✅

**目标**：让宿主机能够正常访问 KDC

**方法**：
1. 使用 `socat` UDP 转发（临时方案）
2. 使用 `host` 网络模式（需要重建容器）
3. 使用 TCP 强制模式（需要 KDC 支持）

**优点**：
- 完全解决外部访问问题
- 支持所有使用场景
- 最接近生产环境

#### 方案 2：在容器内运行代理（临时方案）⚠️

**方法**：
- 将代理打包成容器
- 在容器内获取 ticket
- 通过端口映射暴露给宿主机

**缺点**：
- 不符合生产架构
- 开发调试不便
- 无法完全模拟生产环境

#### 方案 3：使用独立的 KDC 服务器（长期方案）🔮

**方法**：
- 在宿主机或独立服务器上部署 KDC
- 容器和宿主机都连接到这个 KDC

**优点**：
- 完全模拟生产环境
- 避免 Docker 网络限制
- 支持多客户端并发

---

### 8. 推荐解决方案 🚀

#### 8.1 短期方案：socat UDP 转发

```bash
# 1. 安装 socat
brew install socat

# 2. 获取 KDC 容器 IP
KDC_IP=$(docker inspect krb5-kdc-server | grep IPAddress | tail -1 | cut -d'"' -f4)

# 3. 启动 UDP 转发
socat UDP4-LISTEN:88,fork UDP4:${KDC_IP}:88 &

# 4. 修改 krb5.conf
# kdc = 127.0.0.1:88

# 5. 测试
kinit -kt /path/to/keytab user@TEST.COM
```

#### 8.2 中期方案：host 网络模式

修改 `kerberos/docker-compose.yml`：

```yaml
services:
  krb5-kdc-server:
    network_mode: "host"
    # 移除 ports 和 networks 配置
```

**注意**：需要重建容器，可能与其他服务冲突

#### 8.3 长期方案：独立 KDC 服务器

- 在宿主机或独立服务器上部署 KDC
- 容器和宿主机都连接到这个 KDC
- 完全模拟生产环境

---

### 9. 验证清单 ✅

为了确认外部访问需求已满足，需要验证：

- [ ] 宿主机可以执行 `kinit` 获取 ticket
- [ ] 宿主机上的代理可以获取 ticket
- [ ] 宿主机上的 beeline 可以连接 HS2（使用 Kerberos）
- [ ] 宿主机上的 DBeaver 可以连接 HS2（使用 Kerberos）
- [ ] 代理可以成功与 HS2 建立 Kerberos 会话
- [ ] 端到端测试（客户端 → 代理 → HS2）正常工作

---

### 10. 总结 📊

**为什么需要外部访问 Kerberos**：

1. **应用层透明代理**必须在宿主机上运行，需要 Kerberos 认证
2. **客户端工具**（DBeaver、beeline）在宿主机上运行，需要 Kerberos 认证
3. **开发调试**需要在宿主机上进行，需要能够获取 ticket
4. **生产环境对齐**需要模拟生产架构，代理和客户端都在独立服务器上

**当前问题**：
- Docker for Mac 的 UDP 端口转发限制阻止了外部访问
- 这是**关键阻塞问题**，必须解决才能继续开发

**下一步行动**：
1. 实施 UDP 转发方案（socat 或 host 网络）
2. 验证宿主机可以获取 ticket
3. 验证代理可以正常工作
4. 验证客户端工具可以连接

---

**最后更新**：2025-12-04  
**优先级**：🔴 高（阻塞应用层透明代理开发）


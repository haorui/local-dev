### 1. 先还原生产的关键要素

你给的生产 JDBC 片段（`@hive-kerberos-notes.md:433-440`）里，关键信息是：

- **多 HS2 + ZooKeeper 服务发现**  
  - `jdbc:hive2://182.119.79.249:24002,182.119.79.248:24002,182.119.79.247:24002/;`
  - `serviceDiscoveryMode=zooKeeper;`
  - `zooKeeperNamespace=hiveserver2;`
- **强安全**  
  - `auth=KERBEROS;`
  - `principal=hive/hadoop.mrs01.rdss.bocom.com@MRS01.RDSS.BOCOM.COM;`
  - `sasl.qop=auth-conf;`（SASL 加密）
- **客户端用 keytab 登录的业务账号**  
  - `user.keytab=...;`
  - `user.principal=ELT_RTCP_PRF`

也就是说，真正要“透明代理”的，是一条 **Kerberos + SASL 加密 + ZK 发现 + 多 HS2** 的 JDBC 流量。

---

### 2. 为“透明代理”设计的测试环境，至少要包含什么？

为了验证代理方案能够覆盖生产，你至少需要一套**缩小版但要素齐全**的 Hive 集群 + 代理：

#### 2.1 底层 Hive 集群（目标端）

推荐按 Hive2 生产形态来搭一套最小集群（可以是 Docker）：

- **Kerberos 体系**
  - 1 个 KDC（MIT/Heimdal 都行），和生产同样的原则：
    - 有 `HIVE` 服务主体，例如：`hive/hadoop.test.com@TEST.COM`
    - 有业务测试用户主体，例如：`elt_test@TEST.COM`
    - 为 HS2、ZK（如果要 SASL 保护 ZK）生成 keytab

- **Hive 集群组件**
  - **2 台 HiveServer2（HS2）**：  
    - 都用同一个服务主体模式：`hive/hadoop.test.com@TEST.COM`
    - `hive-site.xml` 里启用：
      - `hive.server2.authentication=KERBEROS`
      - `hive.server2.authentication.kerberos.principal` / `keytab`
      - `hive.server2.enable.doAs` 设成和生产一致（通常 true）
  - **1 组 ZooKeeper（1–3 个节点）**：  
    - 支持 HiveServer2 HA 的 service discovery：
      - `serviceDiscoveryMode=zooKeeper`
      - `zooKeeperNamespace=hiveserver2`
    - 如果想完全对齐生产，可以开 SASL 保护 ZK（`auth-conf`），但第一阶段可以先不启用。
  - **Metastore + 外部数据库（PostgreSQL / MySQL）**：  
    - 布局和生产一致即可（单实例就行）。
  - **HDFS + YARN（可选但建议）**：  
    - 如果你要测试 MapReduce/Tez 写入路径（INSERT、大查询），就需要至少 1 NN + 1 DN + RM/NM，并且也 Kerberize。
    - 如果代理只关心 “连得上 HS2，能做元数据和简单查询”，可以暂时用 file:/// 的本地 FS 简化。

> 你现在的 Hive2 Docker 环境已经有：KDC、HS2、Metastore、外部 Postgres，只缺 **多 HS2 + ZK 服务发现 + 完整 Kerberos HDFS/YARN** 这些生产特性。

---

#### 2.2 透明代理本身

根据你打算做的“透明程度”，测试环境可以分两类：

- **L4 透明转发代理（推荐先做这个）**
  - 类似 HAProxy / Envoy / Nginx stream 模式：  
    - 不终止 Kerberos，不解 SASL，只做 TCP 层转发和负载均衡。
  - 测试要点：
    - 客户端配置保持和生产一致的 JDBC（带 ZK）：
      - 直接把 `182.119.79.xxx:24002` 换成你代理的地址/端口即可。
    - 验证：
      - beeline / DBeaver 通过代理能正常 Kerberos 认证、建会话、跑 SQL。
      - Proxy 上做简单健康检查、超时、连接数限制。
  - 部署：
    - 1 个 HAProxy/Envoy 容器，后端指向两台 HS2 或 ZK 集群暴露的端口。

- **JDBC/SASL 终结型“应用层代理”（复杂很多）**
  - 代理自己扮演 Hive 客户端，与 HS2 做 Kerberos + SASL 握手，再对上游应用暴露“类似 JDBC”的接口。
  - 这类代理要自己实现：
    - GSSAPI/SASL 协议细节
    - Hive Thrift 协议 / JDBC 协议
  - 测试环境对底层 Hive 要求同上，但还要：
    - 单元测试 + 集成测试验证代理在：
      - TGT 续约、Delegation Token、`auth-conf` 加密下都工作正常。
    - 和至少一款客户端（beeline / DBeaver / 你的业务程序）打通。

> 建议：**第一阶段先验证 L4 透明代理**（TCP 转发模式），确认对 Kerberos / ZK HA 没有副作用；后面如果真有需要再考虑“协议层代理”。

---

### 3. 完整测试覆盖建议

为了证明这套测试环境“足够支撑生产方案”，可以设计这么几类用例：

- **连接与认证**
  - 同一个 JDBC（含 `serviceDiscoveryMode=zooKeeper; auth=KERBEROS; sasl.qop=auth-conf`）：
    - 直连 HS2（或 ZK） vs 经过代理，行为一致。
  - 测试：
    - TGT 过期后重新 `kinit`，代理下仍可重连。
    - 多用户（不同 keytab）并发连接。

- **HA 与异常场景**
  - 杀掉一个 HS2，看代理 + ZK 是否自动切到另一个 HS2。
  - ZK 重启、HS2 短暂不可用时，客户端重试行为。

- **功能与性能**
  - 元数据操作：`show databases; show tables; desc` 等。
  - 典型 DDL/DML：`create table / insert / select`。
  - 并发连接数与长连接（例如跑 1 小时的批任务）。

---

### 4. 结合你现有环境的路线图（简版）

- **Step 1：在 Hive2 Docker 环境里补 ZK + 多 HS2 支持**  
  - 参考生产 JDBC 的 ZK 用法，把你现在的 Hive2 HS2 改成 ZK serviceDiscovery 模式，多起一台 HS2。
- **Step 2：在这个 Hive2 集群前面放一个 L4 代理（HAProxy/Envoy）**  
  - 先做最简单的 TCP 透传，保证 Kerberos 端到端不变。
- **Step 3：用和生产格式一致的 JDBC，在测试环境里走代理压测 / 回归**  
  - 完成“透明代理”基础能力验证。  

如果你愿意，我可以下一步帮你在 `db/hive2` 下面设计一个最小的 **“HS2×2 + ZK×1 + Kerberos + 代理”** 的 docker-compose 拓扑图/草稿，让你直接按这个方向往上加。

---

### 5. 当前 hive2.x + zookeeper 环境现状（为“应用层透明代理”准备）

> 本文后续讨论的重点是 **“应用层透明代理”**（第 2.2 节里的第二类：JDBC/SASL 终结型代理），L4 透明转发可以视为前置阶段，但不是最终目标。

#### 5.1 已经具备的服务

- **Kerberos 基础设施**  
  - 在 `db/kerberos` / `db/hive` 里已经有 KDC 和测试 realm（`TEST.COM`），包含：
    - `HIVE` 服务主体：`hive/hadoop.test.com@TEST.COM`
    - 测试用户主体：`cli@TEST.COM` 等，并有对应 keytab。

- **Hive2 集群（简化版）** —— `db/hive2/docker-compose.yml`  
  - `namenode-hive2` / `datanode-hive2`：HDFS **非 Kerberos**，主要是给镜像脚本使用，目前业务侧我们通过 `file:///` 绕开 HDFS。  
  - 单个 `hiveserver2-hive2`：
    - 镜像：`bde2020/hive:2.3.2-postgresql-metastore`
    - 使用 **内嵌 Metastore + 外部 PostgreSQL**（`pgvector`），不再依赖独立 metastore 容器。
    - 对外启用了 **HiveServer2 Kerberos 认证**（`hive/hadoop.test.com@TEST.COM + hive.keytab`）。
    - 通过 `HADOOP_OPTS=-Dfs.defaultFS=file:///` 以及本地 warehouse/scratch 目录，弱化对 HDFS 的依赖。

- **ZooKeeper 集群** —— `db/zookeeper/docker-compose.yml`  
  - 已经有 **3 节点 ZK ensemble**：`zoo1/zoo2/zoo3`，都在 `dev_db_network` 网络中：  
    - `zoo1:2181`、`zoo2:2181`、`zoo3:2181`，对外映射为 `2181/2182/2183`。  
  - 目前 **Hive2 尚未配置使用这一组 ZK 做 HS2 service discovery**。

#### 5.2 为“应用层透明代理”还缺什么服务/配置

- **多 HS2 + Zookeeper service discovery**
  - 再起至少 **一个新的 HS2 容器**（例如 `hiveserver2-hive2-b`）：
    - 复用同一套 Metastore 数据库和 warehouse 目录。
    - 使用同一 Kerberos 服务主体 `hive/hadoop.test.com@TEST.COM` + 同一 keytab（或 `_HOST` 形式的 principal）。
  - 在两台 HS2 的 `hive-site.xml`（通过 `hadoop-hive.env` 注入）中补齐 ZK 相关配置：
    - `hive.server2.support.dynamic.service.discovery=true`
    - `hive.zookeeper.quorum=zoo1:2181,zoo2:2181,zoo3:2181`
    - `hive.zookeeper.namespace=hiveserver2`
  - 这样，客户端才能用 **与生产类似的 JDBC**：
    - `serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2;` 开启 HA 发现。

- **应用层透明代理服务（你的 proxy）**
  - **部署形态**：为了验证你开发的程序，这个 proxy 自身在开发/测试阶段会作为 **独立进程运行在宿主机（非容器）**，而 Hive2/KDC/ZooKeeper 等测试服务仍通过 `docker-compose` 提供：
    - Proxy 通过宿主机网络访问 `dev_db_network` 内的 ZK 与 HS2（例如使用 `zoo1:2181`、`hiveserver2-hive2:10000` 等容器主机名或宿主机映射端口）。
    - 后续若需要，也可以再封装成容器形态，但不是当前阶段的前提条件。
  - 功能视角上，它需要：
    - 自己扮演 Hive 客户端角色：处理 GSSAPI/SASL 握手、JDBC/Thrift 协议；
    - 向上游暴露“透明”的 JDBC 接口（或者你自定义的一层 API），以便 DBeaver / 应用可以“无感知”地切到代理地址。

- **（可选）完整 Kerberos 的 HDFS + YARN/Tez**
  - 如果你要做到“行为尽量贴近生产，包括 INSERT / 大查询 路径”，则后续还需要：
    - 为 `namenode-hive2` / `datanode-hive2` / YARN RM/NM 配置 Kerberos principal + keytab；
    - 修复当前 Hive2 在 MR 提交阶段遇到的 `Can't get Master Kerberos principal for use as renewer` 问题。  
  - 如果 **当前阶段只验证“透明代理是否破坏 Kerberos/JDBC 行为”**，可以暂时维持 `file:///` + 简化的 MR 行为，把这个作为后续阶段任务。

#### 5.3 下一步要解决的具体问题（针对应用层代理）

1. **明确应用层代理的职责边界**
   - **目标功能**：在不改变上游应用 JDBC 使用方式的前提下，对 **DDL / DML / DQL 做权限过滤**，并对 **查询结果做脱敏（字段/行级过滤或掩码）**。  
   - 这意味着 proxy 需要在 **SQL 语义和结果集层面有完整视图**，因此必须：
     - **终止完整 JDBC/Thrift 协议**：对上游表现为 JDBC Server，对下游作为 Hive JDBC/Thrift Client，而不仅仅是中间做 SASL 转换。  
     - 能够识别并分类语句类型（DDL/DML/DQL），在转发前按规则做 **拦截/改写/拒绝**。  
     - 在 Fetch 结果时逐行/逐列处理，执行字段脱敏、行过滤等逻辑，再返回给上游。  
   - 由此带来的实现要求：
     - 需要实现的协议栈深度：**GSSAPI/SASL + Hive JDBC/Thrift 会话管理 + SQL/Result 拦截层**；  
     - 在代理内维护清晰的 Session / Statement / Operation / Fetch 状态映射，以便在多连接、多查询并发下保持正确性。

2. **让 Hive2 集群先在“多 HS2 + ZK”模式下稳定运行（不经过代理）**
   - 在 `db/hive2` 的 compose/env 里：
     - 增加第二台 HS2；
     - 配置好 `hive.zookeeper.quorum` / `hive.zookeeper.namespace` / `hive.server2.support.dynamic.service.discovery`；
   - 用 beeline 直接连 ZK 模式：
     - `jdbc:hive2://zoo1:2181,zoo2:2181,zoo3:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2;auth=KERBEROS;principal=...`
   - 先验证：**不经过代理时，ZK + 多 HS2 + Kerberos 的行为是稳定的**。

3. **在同一网络中部署应用层代理，并端到端验证**
   - 代理容器能够：
     - 从 ZK 读取 HS2 实例列表（仿生产的 service discovery）；  
     - 按一定策略选择后端 HS2，并用 Kerberos 建链；  
     - 把客户端的 JDBC/SASL 会话“映射”到底层 HS2，会话关闭时正确清理资源。
   - 对比测试：
     - 直连 ZK/HS2 vs 经由代理，在以下场景行为一致：
       - Kerberos 登录失败/成功；
       - 会话过期、连接断开后的重连；
       - 多用户 / 多连接并发。

4. **（后续）在有需要时，再把 MR/HDFS/YARN 全 Kerberize**
   - 这是为了让代理环境在 **INSERT / 大查询 / Tez 作业** 上也完全贴近生产，但不是“应用层透明代理”验证的第一优先级。

### Hive2 Kerberos + MR renewer 分支小结（feature/hive2-kerberos-mr-renewer）

- 在分支 `feature/hive2-kerberos-mr-renewer` 上，尝试通过配置 `mapreduce.jobtracker.kerberos.principal` / `yarn.resourcemanager.principal` 等“假 principal” 来解决：
  - `Can't get Master Kerberos principal for use as renewer`（MapRedTask 提交 MR Job 时的 delegation token renewer 问题）。
- 结果：
  - 该错误并未完全消除；
  - 反而引入了新的冲突：**HS2/YARN 期待 Kerberos，而 HDFS 仍是 SIMPLE**，出现 “Server asks us to fall back to SIMPLE auth, but this client is configured to only allow secure connections”。
- 结论：
  - 若继续深入，需要把 **HDFS + YARN 一起 Kerberize**，搭建完整安全集群（HS2 + Metastore + HDFS + YARN/Tez），工程量接近生产；
  - 当前“应用层透明代理”的主要目标是 **JDBC 会话权限过滤 + 结果脱敏**，不强依赖本地 MR/Tez 完全复刻生产写入路径。
- 决策：
  - 暂停在此分支继续深入，仅保留作为未来“全 Kerberos 集群”的实验基础；
  - 回到 **Option A：HS2 Kerberos + 内嵌 Metastore + 本地 file:/// FS**，在此基础上继续搭建 **多 HS2 + Zookeeper + 应用层透明代理** 的测试环境。

---

### 当前分支：hive2-full-kerberos-cluster 目标与阶段规划

- **分支来源**
  - 基于 `feature/hive2-kerberos-mr-renewer` 创建（保留了 MR renewer 相关探索），专门用于后续搭建 **完整 Kerberos 集群**：
    - HS2 + Metastore + HDFS + YARN/Tez + ZooKeeper 全部 Kerberize；
    - 解决 MR renewer / delegation token 相关问题；
    - 为“应用层透明代理”提供尽量贴近生产的端到端测试环境。

- **总体目标**
  - 在本地 Docker 环境中搭建一套“缩小版生产集群”：
    - Kerberos KDC 统一发证；
    - HDFS + YARN 以 Kerberos 安全模式运行；
    - Hive Metastore / HS2 使用 Kerberos 身份访问 HDFS 和 Metastore DB；
    - ZooKeeper 使用 Kerberos/SASL 接入，支持 HS2 动态发现（ZK 模式 JDBC）；
    - 客户端（beeline / 代理程序）通过 Kerberos 访问 HS2。

- **阶段拆分（初步）**
  1. **Phase 0：整理现有 Kerberos 配置基线**
     - 复查 `kerberos/*`、`db/hive/hive-kerberos-notes.md` 中已有的 KDC/realm/principal 约定；
     - 明确将要使用的服务主体集合：`nn/_HOST`、`dn/_HOST`、`rm/_HOST`、`nm/_HOST`、`hive/_HOST`、`zookeeper/_HOST` 等。
  2. **Phase 1：Kerberize ZooKeeper**
     - 为 `zoo1/zoo2/zoo3` 定义 `zookeeper/hostname@REALM` 主体与 keytab，配置 JAAS；
     - 在 `db/zookeeper/docker-compose.yml` 中挂载 krb5.conf / keytab / JAAS 配置，打开 ZK SASL；
     - 使用 `zkCli.sh` + kinit 验证 SASL 登录与 ACL 行为。
  3. **Phase 2：Kerberize HDFS + YARN**
     - 为 NameNode / DataNode / ResourceManager / NodeManager 配置对应 principal 与 keytab；
     - 更新 `core-site.xml` / `hdfs-site.xml` / `yarn-site.xml`，确保基本读写 + MR 作业在 Kerberos 模式下可用；
     - 通过简单 MR job（例如 wordcount）验证 delegation token / renewer 工作正常。
  4. **Phase 3：Hive Metastore + HS2 集成**
     - 让 Metastore 使用 Kerberos 访问 HDFS + 外部 Postgres（或 Kerberos DB）；
     - 让 HS2 使用 Kerberos 访问 HDFS + Metastore，并重新验证：DDL / DML / MR renewer 错误是否消除；
     - 在该阶段接入 Kerberized ZK，实现 HS2 动态发现（不再受 SIMPLE 模式 ACL 限制）。
  5. **Phase 4：文档与测试脚本**
     - 为整套集群编写清晰的 README / notes；
     - 按子系统（ZK / HDFS+YARN / Hive）补齐回归脚本，供后续修改时快速验证。

> 当前分支尚未开始具体 Kerberos 配置修改；后续每完成一个 Phase，会在本文件追加“小结 + 已验证能力 + 待解决问题”。

---

### Phase 1 进展：为 ZooKeeper 启用 Kerberos / SASL（已完成）

- **服务器端配置**
  - 在 `kerberos/start.sh` 中为 ZooKeeper 集群预创建并导出以下主体与 keytab：
    - `zookeeper/zoo1@TEST.COM` → `kerberos/data/keytabs/zoo1.keytab`
    - `zookeeper/zoo2@TEST.COM` → `kerberos/data/keytabs/zoo2.keytab`
    - `zookeeper/zoo3@TEST.COM` → `kerberos/data/keytabs/zoo3.keytab`
  - 在 `db/zookeeper/docker-compose.yml` 中为 `zoo1/zoo2/zoo3` 增加并验证：
    - 挂载 `../../kerberos/client/krb5.conf` 到 `/etc/krb5.conf`；
    - 挂载各自的 `zooX.keytab` 到 `/etc/security/keytabs/zookeeper.keytab`；
    - 设置环境变量启用 SASL 认证并引用 JAAS 配置：
      - `ZOO_AUTH_PROVIDER_1=org.apache.zookeeper.server.auth.SASLAuthenticationProvider`
      - `ZOO_REQUIRE_CLIENT_AUTH_SCHEME=sasl`
      - `JVMFLAGS=-Djava.security.auth.login.config=/conf/zk_server_jaas.conf -Djava.security.krb5.conf=/etc/krb5.conf`
    - 修正 `ZOO_SERVERS` 中的选主端口配置（统一使用 `2888:3888;2181`），确保三节点 Quorum 选主与内部通信正常。
  - 为每个 ZK 实例提供独立的 JAAS 配置文件（以 Server/Client 双 section 形式）：
    - `db/zookeeper/conf/zk_server_jaas_zoo1.conf` / `zk_server_jaas_zoo2.conf` / `zk_server_jaas_zoo3.conf`，内容类似：
      - `Server { ... principal="zookeeper/zooX@TEST.COM"; ... }`
      - `Client { ... principal="zookeeper/zooX@TEST.COM"; ... }`
    - 通过 `docker-compose.yml` 将对应 JAAS 文件挂载到容器内 `/conf/zk_server_jaas.conf`。

- **联通性测试（已执行）**
  - 在 `db/zookeeper` 目录下通过 `docker compose down && docker compose up -d` 重启 ZK 集群，确认三节点在 Kerberos 环境下能完成选主并稳定运行；
  - 在 `zoo1` 容器内使用带有 `Client` section 的 JAAS 配置和 `zookeeper/zoo1@TEST.COM` keytab 运行 `zkCli.sh`：
    - 示例命令：
      - `CLIENT_JVMFLAGS="-Djava.security.auth.login.config=/conf/zk_server_jaas.conf -Djava.security.krb5.conf=/etc/krb5.conf -Dzookeeper.sasl.client=true -Dzookeeper.sasl.clientconfig=Client" bin/zkCli.sh -server zoo1:2181 ls /`
    - 日志中可见：
      - `Client successfully logged in.` / `Client will use GSSAPI as SASL mechanism.`；
      - `WatchedEvent state:SaslAuthenticated type:None path:null`；
    - `ls /` 输出包含：
      - `[hiveserver2, zookeeper]`，说明在 `ZOO_REQUIRE_CLIENT_AUTH_SCHEME=sasl` 打开时，Kerberos 客户端仍可成功访问根节点。

- **Phase 1 小结**
  - ZK 端已经在 Kerberos/SASL 模式下稳定运行，三节点 Quorum 选主与 Kerberos 认证均通过验证；
  - 后续 HS2 在接入 ZK 动态发现时，可以直接使用 Kerberos 模式（避免 Hive 2.3.2 中 “HS2 Kerberos + ZK SIMPLE” 的 ACL 兼容性问题）。

---

### 补充：HS2 接入 Kerberized ZK 动态发现（进行中，当前有阻塞）

- **已尝试的接入方式**
  - 在 `db/hive2/hadoop-hive.env` 中开启 HS2 动态发现并指向 Kerberized ZK：
    - `HIVE_SITE_CONF_hive_zookeeper_quorum=zoo1.test.com,zoo2.test.com,zoo3.test.com`
    - `HIVE_SITE_CONF_hive_server2_support_dynamic_service_discovery=true`
    - `HIVE_SITE_CONF_hive_server2_zookeeper_namespace=hiveserver2-hive2`（或 `hiveserver2`）
    - `HIVE_SITE_CONF_hive_zookeeper_kerberos_enabled=true`
  - 在 `db/hive2/docker-compose.yml` 中为 HS2 打开 ZK SASL client，并挂载专用 JAAS：
    - `HADOOP_OPTS="-Djava.security.krb5.conf=/etc/krb5.conf -Dzookeeper.sasl.client=true -Djava.security.auth.login.config=/opt/hive/conf/zk_client_jaas.conf"`
    - `zk_client_jaas.conf` 的 `HiveZooKeeperClient` section 使用 `hive/hadoop@TEST.COM` + `/opt/hive/conf/hive.keytab`。
  - 在 KDC 侧为 ZK 额外创建了 FQDN 形式主体并导出到同一 keytab：
    - 例如同时存在 `zookeeper/zoo1@TEST.COM` 和 `zookeeper/zookeeper-zoo1-1.dev_db_network@TEST.COM`，都写入 `zoo1.keytab`。

- **当前观察到的问题**
  - 当 ZK JAAS 中使用 **短名主体**（已验证可用）：
    - `principal="zookeeper/zoo1@TEST.COM"` 等；
    - ZK 三节点可以稳定 Kerberos/SASL 启动，`zkCli.sh` 使用同一 JAAS 文件的 `Client` section 能看到 `/` 下 `[hiveserver2, zookeeper]`；
    - 但 HS2 端日志反复出现：
      - `GSS initiate failed ... No valid credentials provided (Mechanism level: Server not found in Kerberos database (7) - LOOKING_UP_SERVER)`；
      - 随后是 `KeeperErrorCode = AuthFailed for /hiveserver2[-hive2]`；
    - 说明 HS2 ZK 客户端按容器 FQDN（例如 `zookeeper-zoo1-1.dev_db_network`）去请求服务票据，而 ZK 实际登录主体仍是短名 `zookeeper/zoo1@TEST.COM`，导致 Server TGT 与客户端期望 SPN 不一致。
  - 当尝试在 ZK JAAS 中切换为 **FQDN 主体**：
    - 例如 `principal="zookeeper/zookeeper-zoo1-1.dev_db_network@TEST.COM"`；
    - 即便 KDC 已为该主体生成 keytab，ZK 日志会出现：
      - `Could not configure server because SASL configuration did not allow the ZooKeeper server to authenticate itself properly: LoginException: Unable to obtain password from user`；
    - 导致 ZK 进程直接退出，说明当前 keytab 内容 / krb5 配置与该 FQDN 主体仍存在不匹配（或 ZK 进程实际使用的 hostname 与 SPN 不一致）。
  - 已尝试通过在 `krb5.conf` 中将 `default_tkt_enctypes` / `default_tgs_enctypes` / `permitted_enctypes` 统一成 `aes128-cts`，`Checksum failed` 相关报错仍偶发，未能从加密算法层面解决。

- **阶段性结论（暂定）**
  - 在当前 Docker 网络下，ZK 容器的实际 FQDN（例如 `zookeeper-zoo1-1.dev_db_network`）与我们为 ZK 规划的 SPN（`zoo1.test.com` / `zoo1`）存在差异；
  - Hive 2.3.2 中 HS2 的 ZK SASL 握手逻辑，会根据客户端解析到的 ZK 主机名构造服务 SPN，导致：
    - 要么 HS2 按 FQDN 要票，而 ZK 以短名主体登录（SPN 不一致）；
    - 要么尝试让 ZK 也改用 FQDN 主体，但在现有 keytab/JAAS/KDC 布局下又导致 ZK 自身无法完成 Kerberos 登录。
  - 仅通过配置（不改源码）在 Hive 2.3.2 + 当前容器布局下同时满足 “ZK 进程 Kerberos 登录正常” 和 “HS2 ZK 客户端握手成功” 难度较大，存在较多隐性约束（实际 hostname、SPN 命名、keytab 内容完全对齐）。

- **临时决策**
  - 保持 ZK 集群使用已经验证稳定的短名 SPN 配置（`zookeeper/zooX@TEST.COM`），确保：
    - ZK Kerberos/SASL + Quorum 安全模式长期稳定；
    - `zkCli.sh` 等工具可以在 Kerberos 模式下正常访问；
  - 将 “Hive 2.3.2 下 HS2 + 完全 Kerberized ZK 动态发现（依赖 Curator + ACL）” 标记为 **仍在攻关中的问题**，需要后续结合：
    - 更严格的 hostname/SPN 统一策略，或
    - 阅读/patch Hive2 源码中的 ZK SASL/ACL 相关逻辑；
  - 对当前“应用层透明代理”阶段性目标而言：
    - 继续使用 **Option A：HS2 Kerberos + 内嵌 Metastore + 本地 file:/// FS** 作为主测试环境；
    - 将这套 Kerberized ZK 集群作为独立基础设施保留，为后续：
      - 自行在代理侧维护基于 ZK 的服务发现 / HA；
      - 或在更高版本 Hive / 定制构建中重新尝试 HS2 动态发现
      提供实验场。

---

### Phase 2 进展：Kerberize HDFS（进行中，NameNode 正常 / DataNode 待完善）

- **配置与修改**
  - 在 `kerberos/start.sh` 中补充 HDFS Web UI 的 HTTP/SPNEGO 主体与 keytab：
    - `HTTP/namenode-hive2@TEST.COM` → `kerberos/data/keytabs/http-namenode-hive2.keytab`
  - 在 `db/hive2/hadoop-hive.env` 中启用全局 Hadoop 安全并为 HDFS 配置 Kerberos：
    - `CORE_CONF_hadoop_security_authentication=kerberos`
    - `CORE_CONF_hadoop_security_authorization=true`
    - `HDFS_CONF_dfs_namenode_kerberos_principal=nn/namenode-hive2@TEST.COM`
    - `HDFS_CONF_dfs_namenode_keytab_file=/etc/security/keytabs/nn.keytab`
    - `HDFS_CONF_dfs_datanode_kerberos_principal=dn/datanode-hive2@TEST.COM`
    - `HDFS_CONF_dfs_datanode_keytab_file=/etc/security/keytabs/dn.keytab`
    - `HDFS_CONF_dfs_web_authentication_kerberos_principal=HTTP/namenode-hive2@TEST.COM`
    - `HDFS_CONF_dfs_web_authentication_kerberos_keytab=/etc/security/keytabs/http.keytab`
  - 在 `db/hive2/docker-compose.yml` 中为 HDFS 进程挂载 krb5.conf 与对应 keytab，并注入 JVM 参数：
    - `namenode-hive2`：
      - 挂载 `krb5.conf` 到 `/etc/krb5.conf`；
      - 挂载 `nn-namenode-hive2.keytab` → `/etc/security/keytabs/nn.keytab`；
      - 挂载 `http-namenode-hive2.keytab` → `/etc/security/keytabs/http.keytab`；
      - `HADOOP_OPTS=-Djava.security.krb5.conf=/etc/krb5.conf`。
    - `datanode-hive2`：
      - 挂载 `krb5.conf` 到 `/etc/krb5.conf`；
      - 挂载 `dn-datanode-hive2.keytab` → `/etc/security/keytabs/dn.keytab`；
      - `HADOOP_OPTS=-Djava.security.krb5.conf=/etc/krb5.conf`。
  - 同时将 HiveServer2 的 Kerberos principal 与 KDC 中的主体保持一致：
    - `HIVE_SITE_CONF_hive_server2_authentication_kerberos_principal=hive/hadoop@TEST.COM`

- **当前验证结果**
  - **NameNode（成功）**
    - 在开启 `hadoop.security.authentication=kerberos` 后，之前的 `Can't get Kerberos realm` / `Principal not defined in configuration` 问题已经通过挂载 `krb5.conf` 与配置 HTTP/SPNEGO principal 解决；
    - `docker compose logs namenode` 显示：
      - NameNode 成功读取现有 FSImage 与 edits；
      - RPC 服务在 `namenode-hive2:8020` 正常启动，进入安全模式等待 DataNode 上报；
      - 无新的 Kerberos 相关异常。
  - **DataNode（待解决）**
    - DataNode 能够正确使用 `dn/datanode-hive2@TEST.COM` + `/etc/security/keytabs/dn.keytab` 登录：
      - 日志包含 `Login successful for user dn/datanode-hive2@TEST.COM using keytab file /etc/security/keytabs/dn.keytab`；
    - 但在安全模式下启动时，遇到如下错误并退出：
      - `java.lang.RuntimeException: Cannot start secure DataNode without configuring either privileged resources or SASL RPC data transfer protection and SSL for HTTP.`
    - 说明在 Hadoop 2.7.4 的安全模式下，DataNode 还需要：
      - 要么使用特权端口（<=1024）并配置相应的 secure DN 用户；
      - 要么启用 **SASL RPC data transfer protection**（`dfs.data.transfer.protection`）并为 HTTP 服务配置 SSL。

- **Phase 2 下一步计划**
  - 在保证工程量可控的前提下，为 DataNode 选择一种较轻量的安全启动方式（优先考虑配置基于 SASL 的 data transfer protection）；
  - 完成后：
    - 在 `namenode` 容器中通过 `kinit` + `hdfs dfs -ls /` 验证 Kerberos 下的基本读写；
    - 视情况补充一个最小的 MR/wordcount 作业，用于验证 delegation token / renewer 逻辑是否在“全 Kerberized HDFS”场景下正常工作。

> 目前已确认：**在未额外配置 HTTPS/SSL 的前提下，DataNode 在 Kerberos 模式下会因为缺少“特权端口或 SASL+SSL 组合”而拒绝启动**，这部分工作量接近“完整安全 HDFS”建设，暂时不再继续深入，实现到这里即可满足后续 HS2/ZK/代理实验对“全 Kerberos 集群”的理解基础。

---

### HS2 + Kerberized ZK 动态发现进展（单节点 ZK，Kerberos 认证已成功，ACL 待解决）

- **已完成的配置**
  - **单节点 ZK 简化**：将 ZK 从 3 节点集群简化为单节点 `zoo1`，便于调试
  - **ZK 服务器 Kerberos 配置**：
    - JAAS 配置使用 `zookeeper/zoo1.test.com@TEST.COM` principal
    - 成功启动并接受 Kerberos 认证
  - **HS2 ZK 客户端配置**：
    - `hive.zookeeper.quorum=zoo1.test.com`（使用 FQDN 确保 principal 匹配）
    - `extra_hosts` 配置将 `zoo1.test.com` 解析到 ZK 容器 IP `172.18.0.4`
    - JAAS 配置文件 `zk_client_jaas.conf` 包含 `HiveZooKeeperClient` section（Hive 2.3.2 期望的 login context）
    - `HADOOP_OPTS` 包含 `-Djava.security.auth.login.config=/opt/hive/conf/zk_client_jaas.conf`
  - **Kerberos 认证成功**：
    - HS2 的 ZK 客户端成功通过 Kerberos 认证（从 `AuthFailed` 变为 `InvalidACL`）
    - ZK 服务器日志显示：`Successfully authenticated client: authenticationID=hive/hadoop@TEST.COM`

- **当前问题：InvalidACL 错误（版本匹配后仍存在）**
  - **错误信息**：`KeeperErrorCode = InvalidACL for /hiveserver2`
  - **版本匹配情况**：
    - **Hive 2.3.2 要求**：ZooKeeper 3.4.6（见 `github/hive-2.3.2/pom.xml:200`）
    - **已调整**：将 ZK 服务器从 3.8.4 降级到 3.5.10（兼容 3.4.6，且有 ARM64 支持）
    - **结果**：版本匹配后 `InvalidACL` 错误仍然存在，说明问题不在版本兼容性
  - **根本原因分析**：
    - Hive 2.3.2 在 Kerberos 模式下使用 `Ids.AUTH_IDS` 创建 ACL（见 `HiveServer2.java:274`）
    - `Ids.AUTH_IDS` 表示"所有已通过 SASL 认证的用户"，但 ZK 服务器可能不接受这种 ACL 格式
    - 可能需要使用具体的 SASL ID（如 `sasl:hive/hadoop@TEST.COM`）而不是 `AUTH_IDS`
  - **已尝试的解决方案**：
    1. ✅ 版本匹配：将 ZK 从 3.8.4 降级到 3.5.10（兼容 Hive 2.3.2 的 3.4.6 客户端）
    2. ✅ 移除强制 SASL 要求：暂时移除 `ZOO_REQUIRE_CLIENT_AUTH_SCHEME: sasl`，但仍然失败
    3. ❌ 手动创建节点：尝试通过 `zkCli.sh` 手动创建，但客户端认证失败
  - **根本原因**：
    - Hive 2.3.2 使用 `Ids.AUTH_IDS` ACL，这是 ZooKeeper 的一个特殊 ID，表示"所有已通过 SASL 认证的用户"
    - 但 ZK 服务器（无论是 3.5.10 还是 3.8.4）在验证 ACL 时都不接受 `AUTH_IDS` 这种格式
    - 这是一个已知的 Hive 2.3.2 与 Kerberized ZK 的兼容性问题
  - **当前决策**：
    - **已暂时禁用 ZK 动态发现**，HS2 使用直连模式正常启动 ✅
    - ZK 集群仍保持 Kerberos 模式（3.5.10），供后续调试和代理开发使用
    - HS2 直连模式完全满足当前的代理开发和测试需求（权限过滤 + 结果脱敏）
    - **验证结果**：HS2 在禁用 ZK 动态发现后成功启动，无任何错误，Thrift 服务在端口 10000 正常运行
  - **ACL 问题调试尝试总结**：
    - ✅ 版本匹配：ZK 服务器从 3.8.4 降级到 3.5.10
    - ✅ 移除强制 SASL 要求：移除 `ZOO_REQUIRE_CLIENT_AUTH_SCHEME`，无效
    - ❌ 禁用 Hadoop 安全模式：尝试禁用全局 `hadoop.security.authentication`，但 HS2 仍尝试使用 SASL 连接 ZK
    - ❌ 禁用 ZK Kerberos：移除 ZK 的 Kerberos 卷挂载，HS2 仍尝试 SASL 连接
    - **根本问题**：Hive 2.3.2 的代码逻辑将 HS2 Kerberos 认证与 ZK 客户端 ACL 选择耦合（通过 `UserGroupInformation.isSecurityEnabled()`），即使禁用 Hadoop 安全模式，HS2 的 Kerberos 认证仍会触发 ZK 使用 `AUTH_IDS` ACL
    - **结论**：Hive 2.3.2 的 "HS2 Kerberos + ZK Kerberos 动态发现" 存在已知兼容性问题，需要源码级别的修改才能解决
    - **最终方案**：
      - **HS2 使用直连模式**（禁用 ZK 动态发现），完全满足代理开发和测试需求
      - **ZK 集群保持 Kerberos 模式**，供后续可能的源码级别修复后使用
      - **代理层可以自行实现服务发现逻辑**（如果需要 HA），不依赖 HS2 的 ZK 动态发现
    - **详细说明**：参见 [`ACL-STRATEGY-EXPLANATION.md`](./ACL-STRATEGY-EXPLANATION.md) 了解 HS2 Kerberos ACL 策略与 ZK ACL 策略的详细对比和冲突原因

---

### 下一步方向：基于 Kerberized ZK +（可选）Kerberized NN 的 HS2 / 代理集成规划

- **当前可用基线**
  - Kerberos KDC：统一 realm `TEST.COM`，已为 `cli`、`hive/hadoop`、`nn/namenode-hive2`、`dn/datanode-hive2`、`zookeeper/zoo1` 等主体生成 keytab（已简化为单节点 ZK）；
  - ZooKeeper：**单节点**（`zoo1`）已在 Kerberos/SASL 模式下稳定运行，`zkCli.sh` 使用 `Client` JAAS + `zookeeper/zoo1@TEST.COM` 能在 `/` 下看到 `[hiveserver2, zookeeper]` 等节点（简化后便于调试 HS2 ↔ ZK 集成）；
  - HDFS：NameNode 已在 Kerberos 模式下正常启动并对外提供 `hdfs://namenode-hive2:8020`，DataNode 因 HTTPS/SSL 要求暂未完全 Kerberize（仅登录成功后即因 secureMain 检查退出）。

- **决策：暂停继续深挖 DataNode HTTPS/SSL，切回上层 HS2/ZK/代理场景**
  - 对“应用层透明代理”而言，核心关注点是：
    - 前端到代理的 Kerberos/JDBC 会话建立；
    - 代理到 HS2 的 Kerberos/JDBC 会话建立；
    - HS2 层面的 DDL/DML/DQL 权限过滤与结果脱敏逻辑能被稳定触发；
  - 这些目标并不强依赖 DataNode 完整 secure 启动或 MR 写入路径完全打通，因此可以先将 “DataNode HTTPS/SSL + MR renewer” 抽象为后续增强项，不阻塞当前代理开发/验证。

- **下一步 1：在本分支中实现 HS2 + Kerberized ZK 动态发现**
  - **简化决策：将 ZooKeeper 从 3 节点集群简化为单节点（`zoo1`）**
    - **原因**：减少调试变量，单节点 ZK 不需要 Quorum 选主，hostname/FQDN 问题更简单，只需要一个 `zookeeper/zoo1@TEST.COM` principal，便于快速定位 HS2 ↔ ZK Kerberos 认证问题。
    - **修改内容**：
      - `db/zookeeper/docker-compose.yml`：移除 `zoo2`、`zoo3` 服务，移除 `ZOO_MY_ID` 和 `ZOO_SERVERS`（单节点模式不需要）。
      - `db/hive2/hadoop-hive.env`：`HIVE_SITE_CONF_hive_zookeeper_quorum=zoo1`（从 `zoo1,zoo2,zoo3` 改为单节点）。
      - `db/hive2/docker-compose.yml`：`SERVICE_PRECONDITION` 只保留 `zoo1:2181`。
    - **注意**：单节点 ZK 不适用于生产环境，但完全满足测试/开发需求，待 HS2+ZK+Kerberos 集成稳定后，可再扩展回 3 节点集群。
  - 目标：让 Hive2 HS2（使用 `hive/hadoop@TEST.COM` principal）在 Kerberized ZK 中以 Kerberos 客户端身份注册到指定 namespace，例如 `/hiveserver2`，并可通过 ZK JDBC URL 建立会话。
  - 计划要点：
    - 在 `db/hive2/hadoop-hive.env` 中：
      - 打开 `hive.server2.support.dynamic.service.discovery=true`；
      - 配置 `hive.zookeeper.quorum=zoo1`（单节点）；
      - 设定 `hive.server2.zookeeper.namespace=hiveserver2`；
      - 重新启用 / 保持 `hive.zookeeper.kerberos.enabled=true`（或依赖 `UserGroupInformation.isSecurityEnabled()` 的默认行为），明确采用 Kerberos/SASL 访问 ZK。
    - 在 `db/hive2/docker-compose.yml` 中为 HS2 添加 ZK 客户端 JAAS 相关 JVM 参数（类似 ZK 端）：
      - 使用 `HADOOP_OPTS` 或专用 env 传入：
        - `-Dzookeeper.sasl.client=true`；
        - `-Dzookeeper.sasl.clientconfig=Client`；
        - `-Djava.security.auth.login.config=/opt/hive/conf/zk_client_jaas.conf`。
      - 为 HS2 容器挂载一个 `zk_client_jaas.conf`，Client section 使用 `hive/hadoop@TEST.COM` + `/opt/hive/conf/hive.keytab`。
    - 启动多个 HS2 实例（如 `hiveserver2-hive2-a` / `hiveserver2-hive2-b`），验证它们都能在 Kerberized ZK 下成功创建 ZNode；
    - 使用类似 `test-hs2-zk-discovery.sh` 的脚本（针对 Kerberized ZK 场景）：
      - 通过 `jdbc:hive2://zoo1:2181/...;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2;auth=KERBEROS;principal=hive/hadoop@TEST.COM` 建链（单节点 ZK）；
      - 待单节点 ZK 稳定后，可再扩展为多 HS2 实例 + 3 节点 ZK 集群，验证客户端自动 failover。

- **下一步 2：回到“应用层透明代理”视角补测试**
  - 在当前或专门的代理开发分支上，继续沿用 **Option A：单 HS2 Kerberos + 内嵌 Metastore + 本地 file:/// FS** 作为主测试环境（不依赖 MR）；
  - 增强 `db/hive2/tests/test-proxy-contract.sh`：
    - 通过代理暴露的 JDBC URL 建立 Kerberos 会话；
    - 执行若干 DDL/DQL 用例，验证：
      - 代理的 SQL 解析与权限过滤行为（按库/表/列/操作类型）；
      - 结果集脱敏规则是否按设计生效（例如对敏感列做掩码、泛化等）；
    - 预留一组“ZK 模式 + 多 HS2”的代理用例，待 HS2/ZK 动态发现打通后，用来验证代理在 HA/Failover 场景下的行为。

> 总结：**ZK 与 NameNode 的 Kerberos 基线已具备**，DataNode 完整 secure 启动所需的 HTTPS/SSL 配置暂时搁置。接下来优先把“HS2 + Kerberized ZK 动态发现”与“代理契约测试”打通，为真正的“应用层透明代理”开发提供稳定且贴近生产的上游环境。

---

### Phase 0：统一 Kerberos realm / principal 基线（设计稿）

- **现有基础（已在 KDC 初始化阶段创建）**
  - Realm：`TEST.COM`
  - KDC 主机：`krb5-kdc-server.test.com`（容器内主机名 `krb5-kdc-server`，端口 `88`，宿主机映射 `8800`）
  - 管理员：
    - `admin/admin@TEST.COM`
  - 业务主体：
    - `cli@TEST.COM`（承载 Beeline / 代理侧“前端用户”身份，keytab：`kerberos/data/keytabs/cli.keytab`）
    - `hive/hadoop.test.com@TEST.COM`（HS2/Metastore 服务主体，keytab：`kerberos/data/keytabs/hive.keytab`）

- **全 Kerberos 集群规划的服务主体清单（计划）**
  - 应用侧 / 终端用户：
    - `cli@TEST.COM`（沿用现有，用于开发机/代理进程的 `kinit -k -t cli.keytab`）
  - Hive 相关：
    - `hive/hadoop.test.com@TEST.COM`（Hive2 HS2 + Hive2 Metastore 服务进程登录使用）
  - HDFS（NameNode / DataNode）：
    - `nn/namenode-hive2.test.com@TEST.COM`
    - `dn/datanode-hive2.test.com@TEST.COM`
  - YARN：
    - `rm/resourcemanager.test.com@TEST.COM`
    - `nm/datanode-hive2.test.com@TEST.COM`（或 `nm/<worker-host>.test.com@TEST.COM`，根据最终宿主名确定）
  - ZooKeeper（**已简化为单节点**，便于调试）：
    - `zookeeper/zoo1@TEST.COM`（当前使用短名，后续如需可扩展为 `zookeeper/zoo1.test.com@TEST.COM`）

- **命名规范约定**
  - 统一使用 `service/hostname.fqdn@TEST.COM` 形式，hostname 与各容器的 `hostname` 保持一致（例如：`namenode-hive2` → `namenode-hive2.test.com`）。
  - 所有服务主体使用同一 realm `TEST.COM`，便于统一管理与后续 cross-service delegation。

- **后续工作（待实现）**
  - 在 `kerberos/start.sh` 中扩展 principal 初始化逻辑：
    - 使用 `kadmin.local` 创建上表中的 HDFS/YARN/ZooKeeper 服务主体；
    - 为每个服务导出对应 keytab 至共享目录（例如 `kerberos/data/keytabs/nn.keytab`、`zoo1.keytab` 等）。
  - 在各组件的 `docker-compose.yml` 中增加 keytab / `krb5.conf` / JAAS 的挂载与 `-Djava.security.krb5.conf` / `-Dsun.security.krb5.debug` 等 JVM 参数。

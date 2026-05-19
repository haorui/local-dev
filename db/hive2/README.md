### 1. hive2 环境当前结构（简要）

- **服务组成（`db/hive2/docker-compose.yml`）**
  - `namenode-hive2`：HDFS NameNode，`fs.defaultFS=hdfs://namenode:8020`
  - `datanode-hive2`：HDFS DataNode
  - `metastore-hive2`：Hive Metastore（Thrift 9083）
  - `hiveserver2-hive2`：HiveServer2（JDBC 10020 → 10000）
- **Metastore 后端库（`hadoop-hive.env`）**
  - `jdbc:postgresql://postgres9/metastore`
  - 用户：`postgres`
  - 密码：`123456`
- **自动建表相关配置**
  ```env
  HIVE_SITE_CONF_datanucleus_autoCreateSchema=true
  HIVE_SITE_CONF_hive_metastore_schema_verification=false
  HIVE_SITE_CONF_datanucleus_schema_autoCreateTables=true
  HIVE_SITE_CONF_datanucleus_schema_autoCreateColumns=true
  HIVE_SITE_CONF_datanucleus_schema_validateTables=false
  HIVE_SITE_CONF_datanucleus_schema_validateColumns=false
  ```
  用于让 DataNucleus 在空库里自动建 Hive Metastore 表。

---

### 2. 手动初始化 Metastore 表结构（推荐方式）

如果你想**显式、一次性初始化 schema**，可以用 Hive 自带的 `schematool`，不依赖自动建表：

1. 进入 `metastore-hive2` 容器：

   ```bash
   cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/hive2
   docker compose exec metastore bash
   ```

2. 运行 schema 初始化（Postgres）：

   ```bash
   schematool \
     -initSchema \
     -dbType postgres \
     -userName postgres \
     -passWord 123456 \
     -url jdbc:postgresql://postgres9/metastore
   ```

   - 这会在 `metastore` 数据库里执行对应的 `hive-schema-*.postgres.sql`，创建包括 `VERSION`、`DBS`、`TBLS` 等所有 Metastore 表。
   - 如果库里已有残留/半拉子结构，可以先清空库或 `DROP DATABASE metastore; CREATE DATABASE metastore;` 后再执行。

3. 初始化完成后，你可以把自动建表相关的配置收紧（更接近生产）：

   ```env
   HIVE_SITE_CONF_datanucleus_autoCreateSchema=false
   HIVE_SITE_CONF_datanucleus_schema_autoCreateTables=false
   HIVE_SITE_CONF_datanucleus_schema_autoCreateColumns=false
   HIVE_SITE_CONF_datanucleus_schema_validateTables=true
   HIVE_SITE_CONF_datanucleus_schema_validateColumns=true
   HIVE_SITE_CONF_hive_metastore_schema_verification=true
   ```

   然后 `docker compose restart metastore hiveserver2`，此时 Metastore 会只**校验已存在的表结构**，不再自动改 schema。

---

### 3. 手动执行 SQL 的入口（可选）

- 上面 `schematool` 实际就是帮你执行容器内的 SQL 脚本：
  - 路径大致为：`/opt/hive/scripts/metastore/upgrade/postgres/hive-schema-2.3.0.postgres.sql` 等。
- 如需“完全手动”，可以把这些 SQL 拷贝出来，在宿主机用 `psql` 连到 `postgres9/metastore` 执行，但本质仍是同一套官方脚本。

---

### 4. Hive 2.x + Kerberos 模式（HS2 Kerberos + Metastore simple + 本地 file:///）

- **整体思路**
  - 仅对 `hiveserver2-hive2` 开启 Kerberos 认证，对外客户端使用 `auth=KERBEROS`。
  - Metastore 保持 `hive.metastore.sasl.enabled=false` 的 simple 模式，避免 Hive 2.3.2 老版本 Metastore 中 `HadoopThriftAuthBridge` 的 Kerberos bug。
  - 数据与 scratch 目录落在容器本地 `file:///` 上，并通过 volume 挂载到宿主机，减少 HDFS 在 arm64 环境下的兼容性干扰。

- **关键配置（`hadoop-hive.env`）**
  - **Metastore 仍为 simple**：
    - `HIVE_SITE_CONF_hive_metastore_sasl_enabled=false`
  - **HS2 Kerberos 认证**：
    - `HIVE_SITE_CONF_hive_server2_authentication=KERBEROS`
    - `HIVE_SITE_CONF_hive_server2_authentication_kerberos_principal=hive/hadoop.test.com@TEST.COM`
    - `HIVE_SITE_CONF_hive_server2_authentication_kerberos_keytab=/opt/hive/conf/hive.keytab`
  - **本地文件系统仓库与 scratch**：
    - `HIVE_SITE_CONF_hive_metastore_warehouse_dir=file:/user/hive/warehouse`
    - `HIVE_SITE_CONF_hive_exec_scratchdir=file:/tmp/hive`
    - `HIVE_SITE_CONF_hive_exec_local_scratchdir=/tmp/hive/local`

- **关键配置（`docker-compose.yml`）**
  - `metastore-hive2`：
    - `HADOOP_OPTS: "-Djava.security.krb5.conf=/etc/krb5.conf -Dfs.defaultFS=file:///"`  
      → Metastore 进程 JVM 明确使用本地 file FS。
    - `volumes` 中挂载：
      - `./data/hive-warehouse:/user/hive/warehouse`（持久化本地仓库目录）。
  - `hiveserver2-hive2`：
    - 通过环境变量只对 HS2 打开 Kerberos：
      - `CORE_CONF_hadoop_security_authentication=kerberos`
      - `CORE_CONF_hadoop_security_authorization=true`
    - `HADOOP_OPTS: "-Djava.security.krb5.conf=/etc/krb5.conf -Dfs.defaultFS=file:///"`  
      → HS2 进程 JVM 同样使用本地 file FS。
    - `volumes`：
      - `../../kerberos/client/krb5.conf:/etc/krb5.conf:ro`
      - `../../kerberos/data/keytabs/hive.keytab:/opt/hive/conf/hive.keytab:ro`
      - `./data/hive-warehouse:/user/hive/warehouse`

- **启动顺序**
  1. 确保 Kerberos KDC 已启动（`db/kerberos`）：
     ```bash
     cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/server
     docker compose up -d
     ```
  2. 启动 Hive 2.x 集群：
     ```bash
     cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/hive2
     docker compose up -d
     docker compose ps
     ```
     看到 `metastore-hive2` / `hiveserver2-hive2` 均为 `Up` 即可。

- **宿主机 beeline 通过 Kerberos 连接 HS2（建议步骤）**
  1. 使用 KDC 导出的 `cli.keytab` 获取 TGT：
     ```bash
     cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace
     export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/hive/local_host/kerberos-host-krb5.conf

     kinit -kt kerberos/data/keytabs/cli.keytab cli@TEST.COM
     klist
     ```
  2. 使用 beeline 连接 HiveServer2（HS2 Kerberos）：
     ```bash
     beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop.test.com@TEST.COM" -e "show databases;"
     ```
     - 若环境中 `beeline` 不在 PATH，可在 Hadoop/Hive 安装目录下以绝对路径调用。
     - 如果出现 `GSS initiate failed` / `No valid credentials provided`，优先检查：
       - `KRB5_CONFIG` 是否指向 `kerberos-host-krb5.conf`。
       - `klist` 中是否有 `cli@TEST.COM` 的 TGT。

- **验证简单 DDL/DML（示例）**
  - 连接成功后，在 beeline 中执行：
    ```sql
    create database if not exists kerb_hive2;
    use kerb_hive2;

    create table if not exists users (
      id   int,
      name string
    );

    insert into table users values
      (1, 'Alice'),
      (2, 'Bob');

    select * from users;
    ```
  - 对应的数据文件会出现在宿主机：
    - `db/hive2/data/hive-warehouse/kerb_hive2.db/users/*`
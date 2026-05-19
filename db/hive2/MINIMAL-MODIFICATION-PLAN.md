# Hive 2.3.2 最小化修改计划

## 修改目标

修复 `InvalidACL` 错误：将 `Ids.AUTH_IDS`（`auth` scheme）改为 `sasl:principal@REALM` ACL。

## 关键发现

### 代码结构问题

- `zooKeeperAclProvider` 是**类成员变量**（第 265 行）
- 它无法访问方法参数 `hiveConf`（在 `addServerInstanceToZooKeeper` 方法中）
- **解决方案**：将 ACLProvider 移到方法内部创建

## 最小化修改方案

### 修改文件

**唯一文件**：`service/src/java/org/apache/hive/service/server/HiveServer2.java`

### 修改内容

#### 1. 添加导入（约第 88 行之后）

```java
import org.apache.zookeeper.data.Id;
import org.apache.hadoop.security.SecurityUtil;
```

#### 2. 删除类成员变量（第 265-287 行）

删除整个 `private final ACLProvider zooKeeperAclProvider = ...` 块。

#### 3. 在方法内部创建 ACLProvider（第 306 行之后）

在 `addServerInstanceToZooKeeper` 方法中，`setUpZooKeeperAuth(hiveConf);` 之后，创建 `zooKeeperClient` 之前添加：

```java
// Create ACLProvider with access to hiveConf for dynamic ACL selection
ACLProvider zooKeeperAclProvider = new ACLProvider() {
  @Override
  public List<ACL> getDefaultAcl() {
    List<ACL> nodeAcls = new ArrayList<ACL>();
    if (UserGroupInformation.isSecurityEnabled()) {
      nodeAcls.addAll(Ids.READ_ACL_UNSAFE);
      
      // Check if ZK Kerberos is enabled
      String zkKerberosEnabledStr = hiveConf.get("hive.zookeeper.kerberos.enabled", "false");
      boolean zkKerberosEnabled = "true".equalsIgnoreCase(zkKerberosEnabledStr);
      
      if (zkKerberosEnabled) {
        // Use sasl scheme ACL for Kerberized ZooKeeper
        String principal = hiveConf.getVar(ConfVars.HIVE_SERVER2_KERBEROS_PRINCIPAL);
        if (principal != null && !principal.isEmpty()) {
          try {
            principal = SecurityUtil.getServerPrincipal(principal, "0.0.0.0");
          } catch (Exception e) {
            LOG.warn("Failed to normalize principal: " + principal, e);
          }
          nodeAcls.add(new ACL(Perms.ALL, new Id("sasl", principal)));
        } else {
          String ugiPrincipal = UserGroupInformation.getLoginUser().getUserName();
          nodeAcls.add(new ACL(Perms.ALL, new Id("sasl", ugiPrincipal)));
        }
      } else {
        // Use AUTH_IDS for non-Kerberized ZooKeeper (backward compatible)
        nodeAcls.add(new ACL(Perms.ALL, Ids.AUTH_IDS));
      }
    } else {
      nodeAcls.addAll(Ids.OPEN_ACL_UNSAFE);
    }
    return nodeAcls;
  }

  @Override
  public List<ACL> getAclForPath(String path) {
    return getDefaultAcl();
  }
};
```

## 修改步骤

### 步骤 1：备份源码

```bash
cd /Users/haoruili/Documents/workspaces/github/hive-2.3.2
cp service/src/java/org/apache/hive/service/server/HiveServer2.java \
   service/src/java/org/apache/hive/service/server/HiveServer2.java.backup
```

### 步骤 2：检查编译环境

```bash
java -version  # 需要 JDK 8
mvn -version   # 需要 Maven 3.x
```

### 步骤 3：修改源码

按照上述修改内容进行修改。

### 步骤 4：编译

```bash
cd /Users/haoruili/Documents/workspaces/github/hive-2.3.2
mvn clean package -pl service -am -DskipTests -Dmaven.javadoc.skip=true
```

### 步骤 5：提取 JAR

```bash
mkdir -p /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/hive2/jars
cp service/target/hive-service-2.3.2.jar \
   /Users/haoruili/Documents/workspaces/sso/ucc-workspace/db/hive2/jars/
```

### 步骤 6：更新 docker-compose.yml

在 `hiveserver2` 服务中添加：

```yaml
volumes:
  - ./jars/hive-service-2.3.2.jar:/opt/hive/lib/hive-service-2.3.2.jar:ro
```

## 检查清单

### 修改前

- [ ] 源码文件存在
- [ ] 备份已创建
- [ ] 编译环境就绪

### 修改后

- [ ] 导入已添加
- [ ] 类成员变量已删除
- [ ] 方法内部 ACLProvider 已创建
- [ ] 编译成功
- [ ] JAR 文件生成

---

**下一步**：开始实施修改


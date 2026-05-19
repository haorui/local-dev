# Beeline Kerberos 连接使用说明

## ⚠️ 常见错误

### 错误：`Unrecognized option: -Djava.security.krb5.conf=...`

**原因**：
- `-D` 参数是 Java 系统属性，不能直接作为 beeline 的命令行参数
- beeline 会将 `-D` 参数当作自己的选项处理，导致报错

**错误示例**：
```bash
beeline -u "jdbc:hive2://..." \
  -Djava.security.krb5.conf=/path/to/krb5.conf \  # ❌ 错误！
  -Djavax.security.auth.useSubjectCredsOnly=false  # ❌ 错误！
```

## ✅ 正确方式

### 方式 1：使用 HADOOP_OPTS 环境变量（推荐）

```bash
export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf
export HADOOP_OPTS="-Djava.security.krb5.conf=$KRB5_CONFIG -Djavax.security.auth.useSubjectCredsOnly=false"

beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM"
```

### 方式 2：一行命令

```bash
KRB5_CONFIG=/path/to/krb5.conf \
HADOOP_OPTS="-Djava.security.krb5.conf=/path/to/krb5.conf -Djavax.security.auth.useSubjectCredsOnly=false" \
beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM"
```

### 方式 3：完整示例（包含 kinit）

```bash
# 1. 设置环境变量
export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf
export KRB5CCNAME=FILE:/tmp/krb5cc_cli_beeline
export HADOOP_OPTS="-Djava.security.krb5.conf=$KRB5_CONFIG -Djavax.security.auth.useSubjectCredsOnly=false"

# 2. 获取 Kerberos ticket
kinit -k -t kerberos/data/keytabs/cli.keytab cli@TEST.COM
klist  # 验证

# 3. 连接 HiveServer2
beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM" \
  -e "show databases;"
```

## 📋 原理说明

### Beeline 工作原理

1. `beeline` 是一个 shell 脚本，它会启动 Java 进程
2. Java 系统属性（`-D` 参数）需要在 Java 进程启动时传递
3. `HADOOP_OPTS` 环境变量会被 beeline 脚本读取并传递给 Java 进程

### 环境变量说明

- **`KRB5_CONFIG`**：Kerberos 配置文件路径（用于 `kinit` 等命令行工具）
- **`KRB5CCNAME`**：Kerberos ticket 缓存位置
- **`HADOOP_OPTS`**：传递给 Hadoop/Hive JVM 的系统属性

## 🔧 其他工具的使用方式

### DBeaver

DBeaver 使用 `-vmargs` 参数传递 JVM 参数：

```bash
/Applications/DBeaver.app/Contents/MacOS/dbeaver \
  -vmargs \
  -Djava.security.krb5.conf=/path/to/krb5.conf \
  -Djavax.security.auth.useSubjectCredsOnly=false \
  --add-exports=java.security.jgss/sun.security.krb5=ALL-UNNAMED
```

### Java 应用

在 Java 代码中：

```java
System.setProperty("java.security.krb5.conf", "/path/to/krb5.conf");
System.setProperty("javax.security.auth.useSubjectCredsOnly", "false");
```

或在启动时：

```bash
java -Djava.security.krb5.conf=/path/to/krb5.conf \
     -Djavax.security.auth.useSubjectCredsOnly=false \
     -jar your-app.jar
```

## ✅ 验证清单

- [ ] 已设置 `KRB5_CONFIG` 环境变量
- [ ] 已设置 `HADOOP_OPTS` 环境变量（包含 `-Djava.security.krb5.conf`）
- [ ] 已通过 `kinit` 获取 ticket
- [ ] beeline 命令**没有**使用 `-D` 参数
- [ ] beeline 可以成功连接

## 📚 相关文档

- `TCP-DIRECT-CONNECTION-SOLUTION.md` - TCP 直接连接方案
- `QUICK-REFERENCE.md` - 快速参考
- `USAGE-GUIDE.md` - 完整使用指南

---

**最后更新**：2025-12-04  
**状态**：✅ 已修复并验证


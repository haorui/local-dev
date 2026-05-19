# Socat UDP 转发解决方案

## ✅ 方案已实施并验证

### 问题
Docker for Mac 的 UDP 端口转发存在已知限制，导致宿主机无法通过 `127.0.0.1:8800` 获取 Kerberos ticket。

### 解决方案
使用 `socat` 在宿主机上创建 UDP 转发：
- **本地监听**：`localhost:88` (UDP)
- **转发目标**：`KDC容器IP:88` (UDP)

## 🚀 使用方法

### 1. 启动 UDP 转发

```bash
cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos
./start-socat-forward.sh
```

**脚本功能**：
- 自动检查并安装 `socat`（如果未安装）
- 检查 KDC 容器是否运行
- 自动获取 KDC 容器 IP
- 启动 UDP 转发
- 保存 PID 到 `/tmp/socat-kdc.pid`

### 2. 停止 UDP 转发

```bash
cd /Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos
./stop-socat-forward.sh
```

或者手动停止：
```bash
kill $(cat /tmp/socat-kdc.pid)
```

### 3. 配置 krb5.conf

`kerberos/client/krb5.conf` 已配置为使用 `localhost:88`：

```ini
[realms]
TEST.COM = {
  kdc = 127.0.0.1:88
  admin_server = 127.0.0.1:8749
}
```

### 4. 测试 Kerberos 认证

```bash
# 设置环境变量
export KRB5_CONFIG=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf
export KRB5CCNAME=FILE:/tmp/krb5cc_cli_beeline

# 获取 ticket
kinit -kt kerberos/data/keytabs/cli.keytab cli@TEST.COM

# 验证
klist
```

### 5. 测试 beeline 连接

```bash
beeline -u "jdbc:hive2://localhost:10020/default;auth=KERBEROS;principal=hive/hadoop@TEST.COM" \
  -Djava.security.krb5.conf=/Users/haoruili/Documents/workspaces/sso/ucc-workspace/kerberos/client/krb5.conf \
  -Djavax.security.auth.useSubjectCredsOnly=false \
  -e "show databases;"
```

## 📊 工作原理

```
[宿主机应用] 
    ↓ UDP
[localhost:88] ← socat UDP 转发
    ↓ UDP (Docker 网络)
[KDC容器:88]
```

**优势**：
- ✅ 完全绕过 Docker for Mac UDP 端口转发问题
- ✅ 使用标准 Kerberos 端口 88
- ✅ 对应用透明，无需修改应用代码
- ✅ 简单易用，一键启动/停止

## 🔧 技术细节

### Socat 命令

实际执行的命令：
```bash
socat UDP4-LISTEN:88,fork,reuseaddr UDP4:${KDC_IP}:88
```

**参数说明**：
- `UDP4-LISTEN:88`：在本地 88 端口监听 UDP
- `fork`：为每个连接创建子进程
- `reuseaddr`：允许端口重用
- `UDP4:${KDC_IP}:88`：转发到 KDC 容器

### 日志

- **日志文件**：`/tmp/socat-kdc.log`
- **PID 文件**：`/tmp/socat-kdc.pid`

查看日志：
```bash
tail -f /tmp/socat-kdc.log
```

## ⚠️ 注意事项

1. **端口占用**：
   - 确保本地 88 端口未被占用
   - 如果被占用，脚本会自动停止旧的 socat 进程

2. **KDC 容器状态**：
   - 确保 KDC 容器正在运行
   - 如果容器重启，需要重新运行启动脚本（IP 可能变化）

3. **开机自启动**（可选）：
   - 可以将 `start-socat-forward.sh` 添加到系统启动项
   - 或者使用 `launchd` / `systemd` 管理

## 🎯 验证清单

- [x] socat 已安装
- [x] UDP 转发已启动
- [x] krb5.conf 配置正确
- [x] kinit 可以获取 ticket
- [x] beeline 可以连接 HS2
- [x] 代理程序可以获取 ticket

## 📝 相关文档

- `KERBEROS-EXTERNAL-ACCESS-REQUIREMENTS.md` - 外部访问需求分析
- `KERBEROS-EXTERNAL-ACCESS-FIXED.md` - 配置修复说明
- `KDC-ACCESS-WORKAROUND.md` - KDC 访问问题说明

## 🔄 与其他方案对比

| 方案 | 优点 | 缺点 |
|------|------|------|
| **Socat UDP 转发** ✅ | 简单、透明、无需重建容器 | 需要额外进程 |
| Host 网络模式 | 完全解决 UDP 问题 | 需要重建容器，可能冲突 |
| 强制 TCP | 配置简单 | macOS 客户端支持不完善 |
| 容器内操作 | 稳定可靠 | 不符合生产架构 |

**推荐**：使用 Socat UDP 转发方案，简单有效。

---

**最后更新**：2025-12-04  
**状态**：✅ 已实施并验证可用

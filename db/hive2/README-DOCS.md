# Hive2 文档说明

本目录包含 HiveServer2 + Kerberized ZooKeeper 环境的核心文档。

## 📚 文档列表

### 使用指南

1. **USAGE-GUIDE.md** - 完整使用指南
   - 环境概述
   - 快速开始
   - 连接方式（3种）
   - 基本操作
   - 故障排查
   - 高级用法

2. **USAGE-VERIFIED.md** - 已验证的使用指南
   - 当前状态
   - 推荐使用方式
   - 验证服务状态
   - 已修复的问题列表

3. **QUICK-REFERENCE.md** - 快速参考
   - 一键启动命令
   - 常用命令速查
   - 配置信息速查

4. **quick-start.sh** - 快速开始脚本
   - 自动检查服务
   - 自动获取 Kerberos ticket
   - 显示连接命令

### 技术文档

5. **SOLUTION-ANALYSIS.md** - 解决方案分析
   - 问题回顾
   - 实施的修复方案
   - 源码修改是否必需
   - 推荐方案

6. **ACL-STRATEGY-EXPLANATION.md** - ACL 策略技术说明
   - ZooKeeper ACL 机制详解
   - 不同 scheme 的区别
   - Kerberos 环境下的 ACL 策略

7. **MINIMAL-MODIFICATION-PLAN.md** - 源码修改计划
   - 修改目标
   - 修改内容
   - 编译步骤

### 其他文档

8. **README.md** - 主要说明文档
   - Hive 2.x 环境结构
   - 手动初始化 Metastore
   - Kerberos 模式配置

9. **ISKERBEROSAUTHMODE-EXPLANATION.md** - Kerberos 认证模式说明
   - 技术细节
   - 实现方式

10. **WHY-AUTH-IDS-NOT-SUPPORTED.md** - Auth scheme 技术说明
    - 为什么 auth scheme 在某些情况下不工作
    - 技术分析

11. **progress.md** - 历史进度记录
    - 其他分支的尝试记录
    - 技术决策记录

12. **application-layer-transparent-proxy.md** - 应用层透明代理方案
    - 其他主题的技术文档

## 📋 使用建议

### 快速开始
1. 阅读 `USAGE-VERIFIED.md` 了解当前状态
2. 运行 `./quick-start.sh` 快速启动
3. 参考 `QUICK-REFERENCE.md` 进行日常操作

### 深入了解
1. 阅读 `SOLUTION-ANALYSIS.md` 了解技术方案
2. 阅读 `ACL-STRATEGY-EXPLANATION.md` 了解 ACL 机制
3. 阅读 `MINIMAL-MODIFICATION-PLAN.md` 了解源码修改

### 故障排查
1. 参考 `USAGE-GUIDE.md` 的故障排查章节
2. 检查 `USAGE-VERIFIED.md` 的已知问题

## 🗂️ 文档组织

```
db/hive2/
├── README-DOCS.md                          # 本文件
├── USAGE-GUIDE.md                          # 完整使用指南 ⭐
├── USAGE-VERIFIED.md                       # 已验证使用指南 ⭐
├── QUICK-REFERENCE.md                      # 快速参考 ⭐
├── quick-start.sh                          # 快速启动脚本 ⭐
├── SOLUTION-ANALYSIS.md                    # 解决方案分析
├── ACL-STRATEGY-EXPLANATION.md             # ACL 策略说明
├── MINIMAL-MODIFICATION-PLAN.md            # 源码修改计划
├── README.md                               # 主要说明
├── ISKERBEROSAUTHMODE-EXPLANATION.md       # Kerberos 认证说明
├── WHY-AUTH-IDS-NOT-SUPPORTED.md           # Auth scheme 说明
├── progress.md                             # 历史进度
└── application-layer-transparent-proxy.md  # 应用层代理方案
```

⭐ 标记为最常用的文档

---

**最后更新**：2025-12-04


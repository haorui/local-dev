## 适用场景

適合小型應用或開發測試環境。

    •	使用場景：適用於單節點 Redis 即可滿足的應用，對可用性和數據安全性要求不高的小型應用場景，如開發、測試環境。
    •	優點：簡單，單機性能高，配置容易。
    •	缺點：單點故障，無法滿足高可用性需求，不具備故障自動恢復功能。

以下是 Redis CLI 常用的指令和操作語法，包含基本操作、鍵管理、數據結構操作、複製和集群操作等：

基本操作

# 連接 Redis 伺服器

redis-cli -h <hostname> -p <port> -a <password>

# Ping Redis 伺服器以確認連接

PING

# 返回 PONG 表示正常

鍵管理

# 設置鍵值

SET <key> <value>

# 取得鍵值

GET <key>

# 檢查鍵是否存在

EXISTS <key>

# 刪除鍵

DEL <key>

# 設置鍵的過期時間（以秒為單位）

EXPIRE <key> <seconds>

# 查看鍵的剩餘存活時間（以秒為單位）

TTL <key>

# 重命名鍵

RENAME <key> <newkey>

# 獲取指定模式的所有鍵

KEYS <pattern>

# 示例：KEYS "user:\*" 列出所有以 user: 開頭的鍵

字符串 (String)

# 設置鍵的值

SET <key> <value>

# 設置鍵的值和過期時間

SETEX <key> <seconds> <value>

# 增加鍵的值（整數）

INCR <key>

# 增加鍵的值（指定數量）

INCRBY <key> <amount>

# 減少鍵的值

DECR <key>

# 減少鍵的值（指定數量）

DECRBY <key> <amount>

# 追加值到鍵的末尾

APPEND <key> <value>

哈希 (Hash)

# 設置哈希字段的值

HSET <key> <field> <value>

# 取得哈希字段的值

HGET <key> <field>

# 取得所有字段和值

HGETALL <key>

# 刪除哈希字段

HDEL <key> <field>

# 查看哈希字段是否存在

HEXISTS <key> <field>

# 增加哈希字段的數值

HINCRBY <key> <field> <increment>

列表 (List)

# 在列表頭部插入元素

LPUSH <key> <value1> [value2 ...]

# 在列表尾部插入元素

RPUSH <key> <value1> [value2 ...]

# 取得列表範圍內的元素

LRANGE <key> <start> <stop>

# 彈出列表頭部元素

LPOP <key>

# 彈出列表尾部元素

RPOP <key>

# 取得列表長度

LLEN <key>

集合 (Set)

# 添加元素到集合

SADD <key> <member1> [member2 ...]

# 移除集合中的元素

SREM <key> <member>

# 檢查元素是否存在於集合

SISMEMBER <key> <member>

# 獲取集合中的所有元素

SMEMBERS <key>

# 獲取集合的元素個數

SCARD <key>

# 返回兩個集合的交集

SINTER <key1> <key2>

# 返回兩個集合的聯集

SUNION <key1> <key2>

有序集合 (Sorted Set)

# 添加元素及其分數到有序集合

ZADD <key> <score1> <member1> [score2 member2 ...]

# 取得指定範圍內的元素

ZRANGE <key> <start> <stop> [WITHSCORES]

# 根據分數範圍取得元素

ZRANGEBYSCORE <key> <min> <max>

# 取得成員的分數

ZSCORE <key> <member>

# 刪除元素

ZREM <key> <member1> [member2 ...]

事務操作

# 開啟事務

MULTI

# 執行事務內的命令

命令...

# 提交事務

EXEC

# 放棄事務

DISCARD

複製 (Replication)

# 配置主從複製

SLAVEOF <master-ip> <master-port>

# 停止成為從屬

SLAVEOF NO ONE

集群操作 (Cluster)

# 啟用集群模式

CLUSTER INFO

# 檢查節點信息

CLUSTER NODES

# 添加節點到集群

CLUSTER MEET <node-ip> <node-port>

# 集群重分片

CLUSTER RESHARD

Redis Sentinel 指令

# 獲取哨兵信息

SENTINEL INFO

# 獲取主節點信息

SENTINEL MASTER <master-name>

# 獲取從節點信息

SENTINEL SLAVES <master-name>

# 檢查監控的主節點列表

SENTINEL MASTERS

這些是 Redis 常用的命令，可以根據需要在 Redis CLI 中運行這些指令來管理和操作 Redis 實例及其數據。

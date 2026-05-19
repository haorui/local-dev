## Cluster 适用场景

適合大數據量和分布式場景，支持高可用且具備數據分片功能。

    •	使用場景：適用於對大數據量、高吞吐量要求的場景，特別是分布式的中大型應用，如大型網站、電商系統、金融系統等。
    •	架構：通過分片（sharding）和多主多從結構來支持大數據量，具備高可用性，並自動處理節點失效。
    •	優點：數據分片、擴展性強，能支持海量數據的存儲和讀寫，且具備高可用性。
    •	缺點：集群管理相對複雜，對多鍵操作有一定限制，不適合需要強一致性的場景。

## 初始化 Redis Cluster

docker exec -it redis-node-1 redis-cli --cluster create \
 redis-node-1:7000 redis-node-2:7001 redis-node-3:7002 \
 redis-node-4:7003 redis-node-5:7004 redis-node-6:7005 \
 --cluster-replicas 1

docker exec -it redis-node-1 redis-cli -p 7000 -a Zonesec2024. --cluster create \
 redis-node-1:7000 redis-node-2:7001 redis-node-3:7002 \
 redis-node-4:7003 redis-node-5:7004 redis-node-6:7005 \
 --cluster-replicas 1

## 进阶

Sentinel 配合 Cluster 模式
• 適用場景：在需要分片的同時，也想提升整個集群的高可用性。
• 使用方式：通常每個分片的主從結構都被 Sentinel 監控，用於高可用切換；在某些 Redis 集群場景中，也可直接使用 Redis Cluster 的內建高可用。

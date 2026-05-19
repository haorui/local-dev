### 部署

docker-compose up -d

### 验证

docker exec -it emqx1 sh -c "emqx ctl cluster status"

.PHONY: mqttup
mqttup:
	docker compose -f ./mqtt/docker-compose.yml up -d

.PHONY: mqttdown
mqttdown:
	docker compose -f ./mqtt/docker-compose.yml down

# ucc sso
.PHONY: ssoup
ssoup:
	docker compose -f ./sso/docker-compose.yml up -d

.PHONY: ssodown
ssodown:
	docker compose -f ./sso/docker-compose.yml down
# db
.PHONY: dbup
dbup:
	docker compose -f ./dbmanager/docker-compose.yml up -d

.PHONY: dbdown
dbdown:
	docker compose -f ./dbmanager/docker-compose.yml down

# smartfs-ui
.PHONY: file-up
file-up:
	docker compose -f ./smartfs/docker-compose.yml up -d

.PHONY: file-down
file-down:
	docker compose -f ./smartfs/docker-compose.yml down

# prod
.PHONY: prod-up
prod-up:
	docker compose -f ./sso/docker-compose.prod.yml up -d

.PHONY: prod-down
prod-down:
	docker compose -f ./sso/docker-compose.prod.yml down

# nginx
.PHONY: nup
nup:
	docker compose -f ./nginx/docker-compose.yml up -d

.PHONY: ndown
ndown:
	docker compose -f ./nginx/docker-compose.yml down

# nginx swarm
.PHONY: nsup
nsup:
	docker stack deploy -c ./nginx-swarm/docker-compose.yml nginx -d

.PHONY: nsdown
nsdown:
	docker stack rm nginx

.PHONY: redis-up
redis-up:
	docker compose -p redis -f ./redis/single/docker-compose.yml up -d

.PHONY: redis-down
redis-down:
	docker compose -p redis -f ./redis/single/docker-compose.yml down

.PHONY: redis-cluster-up
redis-cluster-up:
	docker compose -p redis-cluster -f ./redis/cluster/docker-compose.yml up -d
.PHONY: redis-cluster-down
redis-cluster-down:
	docker compose -p redis-cluster -f ./redis/cluster/docker-compose.yml down

.PHONY: redis-sentinel-up
redis-sentinel-up:
	docker compose -p redis-sentinel -f ./redis/sentinel/docker-compose.yml up -d

.PHONY: redis-sentinel-down
redis-sentinel-down:
	docker compose -p redis-sentinel -f ./redis/sentinel/docker-compose.yml down

# dbmanager backend
.PHONY: dbup
dbup:
	docker compose -f ./dbmanager/docker-compose.yml up -d

.PHONY: dbdown
dbdown:
	docker compose -f ./dbmanager/docker-compose.yml down

# nginx local reverse proxy
.PHONY: nup
nup:
	docker compose -f ./nginx/docker-compose.yml up -d

.PHONY: ndown
ndown:
	docker compose -f ./nginx/docker-compose.yml down

# redis — three topologies
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

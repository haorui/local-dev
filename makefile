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

# SmartData container-mode development. This is intentionally independent from
# ../smartdata/make dev, which remains the host/tmux development workflow.
SMARTDATA_NETWORK ?= dev_db_network
SMARTDATA_SERVICES := smartdata-admin dbmanager dbgate-api dbgate-web
SMARTDATA_SERVICE_ARGS = $(if $(SERVICE),$(SERVICE),$(SMARTDATA_SERVICES))
SMARTDATA_COMPOSE = DEV_DB_NETWORK=$(SMARTDATA_NETWORK) docker compose --env-file ./smartdata/.env -f ./smartdata/compose.yaml

.PHONY: smartdata-up
smartdata-up:
	@test -f ./smartdata/.env || (echo 'smartdata/.env is missing; copy smartdata/.env.example first' >&2; exit 1)
	@docker network inspect "$(SMARTDATA_NETWORK)" >/dev/null 2>&1 || (echo "Docker network '$(SMARTDATA_NETWORK)' is missing; start the selected db/Redis stack first" >&2; exit 1)
	@$(SMARTDATA_COMPOSE) up --build -d $(SMARTDATA_SERVICE_ARGS)

.PHONY: smartdata-down
smartdata-down:
	@test -f ./smartdata/.env || (echo 'smartdata/.env is missing; copy smartdata/.env.example first' >&2; exit 1)
	@$(SMARTDATA_COMPOSE) stop $(SMARTDATA_SERVICE_ARGS)

.PHONY: smartdata-restart
smartdata-restart:
	@$(MAKE) smartdata-down SERVICE='$(SERVICE)'
	@$(MAKE) smartdata-up SERVICE='$(SERVICE)'

.PHONY: smartdata-logs
smartdata-logs:
	@test -f ./smartdata/.env || (echo 'smartdata/.env is missing; copy smartdata/.env.example first' >&2; exit 1)
	@$(SMARTDATA_COMPOSE) logs -f $(SMARTDATA_SERVICE_ARGS)

.PHONY: smartdata-config
smartdata-config:
	@test -f ./smartdata/.env || (echo 'smartdata/.env is missing; copy smartdata/.env.example first' >&2; exit 1)
	@$(SMARTDATA_COMPOSE) config --quiet

.PHONY: smartdata-ps
smartdata-ps:
	@test -f ./smartdata/.env || (echo 'smartdata/.env is missing; copy smartdata/.env.example first' >&2; exit 1)
	@$(SMARTDATA_COMPOSE) ps $(SMARTDATA_SERVICES)

# Trusted Proxy remains a separate opt-in container, outside smartdata-up.
.PHONY: smartdata-trusted-proxy-up
smartdata-trusted-proxy-up:
	@test -f ./smartdata/.env || (echo 'smartdata/.env is missing; copy smartdata/.env.example first' >&2; exit 1)
	@$(SMARTDATA_COMPOSE) up --build -d trusted-proxy

.PHONY: smartdata-trusted-proxy-down
smartdata-trusted-proxy-down:
	@test -f ./smartdata/.env || (echo 'smartdata/.env is missing; copy smartdata/.env.example first' >&2; exit 1)
	@$(SMARTDATA_COMPOSE) stop trusted-proxy

# topology SSOT drift check (manual, low-frequency)
.PHONY: check-topology
check-topology:
	@bash scripts/check-topology.sh

## 环境变量

```
cp env.example .env
```

## 开发环境

```
docker compose --env-file .env up -d
```

## 生产环境

```
docker compose --env-file .env -f docker-compose.yml -f docker-compose.override.yml up -d
```

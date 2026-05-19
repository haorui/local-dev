## 环境变量

```
cp env.example .env
```

## Docker, Docker Compose 和 NVIDIA Container Toolkit

```
docker compose up -d --scale ollama=2
```

## 运行模型

```
docker exec -it ollama ollama run gpt-oss:20b
docker exec -it ollama ollama stop gpt-oss:20b
```

## 测试

```
curl http://localhost:11434/api/chat -d '{
"model": "gpt-oss:20b",
"messages": [
{ "role": "user", "content": "帮我写一篇100字探险小说" }
]
}'
```

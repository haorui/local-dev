# 认证中心开发目录

## 开发环境

### 依赖服务

创建docker网络,保证容器之间可以互相访问

```sh
docker network create uccserver
```

redis,使用docker或其他方式启动redis

```sh
docker run -d --name redis -p 6379:6379 redis:7.2-alpine3.18
```

本地hosts

```hosts
127.0.0.1 sso.devlocal.com
127.0.0.1 platform.devlocal.com
```

修改.env为本机的IP

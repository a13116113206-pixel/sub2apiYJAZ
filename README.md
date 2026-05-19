# 宝塔 + sub2api 一键安装

在新 Linux 服务器上一条命令安装宝塔面板，并用 Docker Compose 部署 sub2api 官方完整栈：

- sub2api
- PostgreSQL
- Redis

脚本会自动生成管理员密码、数据库密码和固定密钥，并把访问地址、安全组端口、账号密码写到一个固定文件里。

## 一键安装

国内服务器更推荐先下载再执行，方便看到网络报错。执行后脚本会先问两个问题：

```text
1. 国内服务器 / 国外服务器
2. 使用本机 IP / 填写域名
```

```bash
curl -fsSL --connect-timeout 20 -m 120 https://cdn.jsdelivr.net/gh/a13116113206-pixel/-sub2api@main/install_bt_sub2api.sh -o install_bt_sub2api.sh && sudo bash install_bt_sub2api.sh
```

GitHub raw 直连版：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/a13116113206-pixel/-sub2api/main/install_bt_sub2api.sh)
```

如果服务器不支持 `<(...)`，用这一条：

```bash
curl -fsSL https://raw.githubusercontent.com/a13116113206-pixel/-sub2api/main/install_bt_sub2api.sh -o install_bt_sub2api.sh && sudo bash install_bt_sub2api.sh
```

## 带域名安装

也可以不走交互，直接指定国内服务器和域名：

```bash
curl -fsSL --connect-timeout 20 -m 120 https://cdn.jsdelivr.net/gh/a13116113206-pixel/-sub2api@main/install_bt_sub2api.sh -o install_bt_sub2api.sh && sudo SERVER_REGION=cn ACCESS_MODE=domain DOMAIN=api.example.com bash install_bt_sub2api.sh
```

## 自定义端口

默认 sub2api 对外端口是 `8080`。想改成 `8088`：

```bash
SUB2API_PORT=8088 bash <(curl -fsSL https://raw.githubusercontent.com/a13116113206-pixel/-sub2api/main/install_bt_sub2api.sh)
```

## 已安装宝塔时跳过宝塔安装

```bash
sudo INSTALL_BT=0 SERVER_REGION=cn ACCESS_MODE=ip bash install_bt_sub2api.sh
```

## 部署完成后看哪里

```text
/root/sub2api-info.txt              sub2api 地址、账号密码、宝塔入口、安全组端口、常用命令
/root/sub2api-install.log           安装日志
/opt/sub2api/                       sub2api 部署目录
/opt/sub2api/.env                   sub2api 环境变量
/opt/sub2api/docker-compose.yml     Docker Compose 配置
/opt/sub2api/postgres_data/         PostgreSQL 数据
/opt/sub2api/redis_data/            Redis 数据
```

查看全部部署信息：

```bash
sudo cat /root/sub2api-info.txt
```

查看宝塔账号密码：

```bash
sudo bt default
```

## 安全组需要开放

必须开放：

```text
TCP 22      SSH
TCP 8888    宝塔面板默认端口，实际以 bt default 为准
TCP 8080    sub2api 默认访问端口
```

可选开放：

```text
TCP 80      域名 HTTP / 反向代理
TCP 443     域名 HTTPS / SSL
```

正式使用域名时，更推荐在宝塔里建站点，用 Nginx 反向代理到：

```text
http://127.0.0.1:8080
```

这样外部可以访问：

```text
https://你的域名
```

## 常用维护命令

```bash
cd /opt/sub2api
docker compose ps
docker compose logs -f
docker compose restart
docker compose pull && docker compose up -d
```

# 宝塔 + sub2api 一键部署说明

## 目标

这个脚本做一件事：在一台新 Linux 服务器上安装宝塔面板，然后用 Docker Compose 部署 `sub2api` 官方完整栈，也就是 `sub2api + PostgreSQL + Redis`，最后把访问地址、账号密码、端口安全组清单都写到固定文件里，避免部署完以后到处找信息。

## 使用方法

把 `install_bt_sub2api.sh` 上传到服务器后执行：

```bash
sudo bash install_bt_sub2api.sh
```

如果你已经有域名，可以这样运行：

```bash
sudo DOMAIN=api.example.com bash install_bt_sub2api.sh
```

如果你想改 sub2api 对外端口：

```bash
sudo SUB2API_PORT=8088 bash install_bt_sub2api.sh
```

如果服务器已经安装过宝塔，不想让脚本安装宝塔：

```bash
sudo INSTALL_BT=0 bash install_bt_sub2api.sh
```

## 部署完成后在哪里看信息

脚本会输出信息，同时写入这些文件：

```text
/root/sub2api-credentials.txt       sub2api 地址、账号密码、宝塔入口、常用命令
/root/sub2api-security-group.txt    需要开放的安全组端口
/root/sub2api-install.log           安装日志
/opt/sub2api/                       sub2api 部署目录
/opt/sub2api/.env                   sub2api 环境变量
/opt/sub2api/docker-compose.yml     Docker Compose 配置
/opt/sub2api/postgres_data/         PostgreSQL 数据
/opt/sub2api/redis_data/            Redis 数据
```

查看账号密码：

```bash
sudo cat /root/sub2api-credentials.txt
```

查看安全组端口：

```bash
sudo cat /root/sub2api-security-group.txt
```

查看宝塔默认账号密码：

```bash
sudo bt default
```

## 需要开放哪些安全组

必须开放：

```text
TCP 22      SSH
TCP 8888    宝塔面板默认端口，实际以 bt default 输出为准
TCP 8080    sub2api 默认访问端口
```

可选开放：

```text
TCP 80      域名 HTTP / 反向代理
TCP 443     域名 HTTPS / SSL
```

云厂商安全组入口一般在：

```text
阿里云: ECS -> 安全组 -> 入方向
腾讯云: CVM -> 安全组 -> 入站规则
AWS: EC2 -> Security Groups -> Inbound rules
Azure: VM -> Networking -> Inbound port rules
Google Cloud: VPC network -> Firewall
```

## IP 和域名兼容

脚本默认支持 IP 访问：

```text
http://服务器公网IP:8080
```

传入 `DOMAIN=你的域名` 后，凭据文件里也会写出域名访问方式：

```text
http://你的域名:8080
```

更推荐的正式做法是：域名解析到服务器 IP，然后在宝塔里建一个站点，用 Nginx 反向代理到：

```text
http://127.0.0.1:8080
```

这样最终可以用：

```text
https://你的域名
```

同时安全组开放 `80` 和 `443`，`8080` 可以只给自己的 IP 开放，或者后续在服务器防火墙里限制。

## 常用维护命令

```bash
cd /opt/sub2api
docker compose ps
docker compose logs -f
docker compose restart
docker compose pull && docker compose up -d
```

## 默认账号

默认管理邮箱：

```text
admin@example.com
```

默认密码由脚本随机生成，查看：

```bash
sudo cat /root/sub2api-credentials.txt
```

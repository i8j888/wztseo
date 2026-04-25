# 万站通 WanZhanTong SEO

Go 高性能蜘蛛池 & 站群系统 v2.10.316

## 特性

- Go 1.26 架构，单机日承载 6 亿+ 蜘蛛请求
- Google 抓取量峰值 1600 万/小时
- 20MB 单二进制，systemd 秒级部署
- 11 行业分组 × 10 套预设模板 × 12 种语言，103 万种指纹变体
- AI 文章生成（Gemini / OpenAI / Claude）
- ClickHouse 日志分析
- Cloudflare 多账户批量管理
- WAF 三阶段防护
- SEO 工具（内容评分 / 关键词密度 / Silo 内链）
- 支持小旋风格式文章批量导入

## 快速部署

```bash
# 下载
wget https://github.com/i8j888/wztseo/raw/main/spider-pool-linux-amd64
chmod +x spider-pool-linux-amd64

# 安装
bash install.sh

# 或手动部署
mkdir -p /opt/spider-pool/config
mv spider-pool-linux-amd64 /opt/spider-pool/spider-pool
cd /opt/spider-pool && ./spider-pool --mode=spider &
./spider-pool --mode=admin &
```

## 端口

| 服务 | 端口 | 说明 |
|------|------|------|
| spider-pool | 8080 | 蜘蛛池前端（Cloudflare Origin Rules 指向此端口） |
| spider-admin | 8081 | 后台管理面板 |

## 后台

访问 `http://服务器IP:8081/admin/` 进入后台，首次访问需要初始化管理员账号。

## 支持的语言

中文、English、ไทย、日本語、한국어、Tiếng Việt、Indonesia、Português、Español、Русский、हिन्दी、Bahasa Melayu

## 联系

- Telegram 群: https://t.me/wztseo_com
- Telegram 频道: https://t.me/wztseo
- 官网: https://wztseo.com

# 万站通 WanZhanTong

高性能站群管理系统 · 智能SEO · AI内容生成 · 多站群管理

## 下载

前往 [Releases](https://github.com/i8j888/wztseo/releases) 下载最新版本。

## 功能特性

- 🌐 无限域名 + 泛子域名管理
- 🔗 外链库系统 + 强引 302 链式重定向
- 🤖 AI 内容生成（Gemini / OpenAI / Claude）
- 🛡 WAF 安全中心 + 规则引擎 + 异常检测
- 📊 ClickHouse 高性能日志分析
- 🎨 8 套主题（7 深色 + 1 亮色）
- 🔒 授权系统 + 设备绑定
- 🔥 防火墙管理（UFW）
- 📡 版本更新推送

## 安装

```bash
cd /opt && tar xzf wanzhan-vX.Y.Z-linux-amd64.tar.gz
cd wanzhan-vX.Y.Z
bash install.sh
cp spider-pool /opt/spider-pool/
systemctl start spider-pool spider-admin
```

首次访问 `http://服务器IP:8081/admin/` 进入安装向导。

## 系统要求

- Linux（Debian 11+ / Ubuntu 22.04+）
- 4GB+ 内存（推荐 8GB+）
- 2 核+ CPU

## 授权

| 版本 | 价格 | 功能 |
|------|------|------|
| 免费版 | 免费 | 3 个域名 + 基础功能 |
| 专业版（年付） | 1,500 USDT/年 | 全功能解锁 |
| 专业版（永久） | 3,000 USDT | 一次买断，终身更新 |

注册即送 **3 天专业版免费试用**。

## 链接

- 🌐 官网: [wztseo.com](https://wztseo.com)
- 📦 下载: [GitHub Releases](https://github.com/i8j888/wztseo/releases)

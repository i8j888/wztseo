# 万站通 WanZhanTong

高性能站群 + 蜘蛛池系统，支持泛目录、AI文章生成、多模板去指纹、Cloudflare批量管理。

## 功能特性

- **泛目录** — 任意URL路径自动匹配，无限目录和页面
- **蜘蛛池** — 吸引搜索引擎蜘蛛，通过外链引导到目标站
- **站群管理** — 批量域名管理，分组模板，去指纹
- **AI文章生成** — 集成 Gemini/OpenAI，批量生成多语言SEO文章
- **AI关键词扩展** — 核心词自动扩展长尾关键词
- **11套预设模板** — 博客/论坛/百科/游戏/电商/杂志/企业/落地页/下载站/新闻/空白
- **12种语言** — 中/英/泰/日/韩/越/印尼/葡/西/俄/印地/马来
- **去指纹** — CSS前缀/配色/Logo/字体/CTA 15840+种变体
- **CTA跳转** — 三合一按钮（顶部+底部+悬浮），蜘蛛不可见，JS加密跳转
- **关键词注入** — 自然嵌入段落内部，智能断点，多语言
- **Cloudflare管理** — 多账户批量DNS/SSL/缓存/WAF
- **WAF防火墙** — SQL注入/XSS防护 + CC防御 + 自定义规则
- **告警通知** — Telegram推送，磁盘/内存/服务监控
- **ClickHouse日志** — 高性能蜘蛛访问日志和统计

## 系统要求

- **架构**: Linux x86_64 (amd64)
- **内存**: 最低 2GB，推荐 8GB+
- **磁盘**: 最低 10GB
- **端口**: 8080（蜘蛛池）、8081（后台管理）

### 支持的系统

| 系统 | 版本 | 状态 |
|------|------|------|
| Debian | 10 / 11 / 12 | ✅ |
| Ubuntu | 20.04 / 22.04 / 24.04 | ✅ |
| CentOS | 7 / 8 / Stream 9 | ✅ |
| Rocky Linux | 8 / 9 | ✅ |
| AlmaLinux | 8 / 9 | ✅ |

## 快速安装

一行命令安装：

```bash
bash <(curl -sL https://raw.githubusercontent.com/i8j888/wztseo/main/install.sh)
```

脚本自动完成：下载二进制 → 系统调优 → 安装 ClickHouse（可选）→ 配置 systemd → 启动服务

安装完成后访问: `http://服务器IP:8081/admin/`

- 默认账号: `admin`
- 默认密码: `admin123`
- 安全码: `1314`

### 更新

同样一行命令，脚本自动检测已安装版本并更新：

```bash
bash <(curl -sL https://raw.githubusercontent.com/i8j888/wztseo/main/install.sh)
```

### 手动部署

如果一键脚本无法使用（网络受限等），可以手动部署：

```bash
# 1. 下载二进制（在能访问GitHub的机器上下载，再传到服务器）
wget https://github.com/i8j888/wztseo/raw/main/spider-pool-linux-amd64

# 2. 上传到服务器（从本地传到服务器）
scp spider-pool-linux-amd64 root@你的服务器IP:/opt/spider-pool/spider-pool

# 3. SSH登录服务器，设置权限
ssh root@你的服务器IP
mkdir -p /opt/spider-pool/data/{templates,keywords,article,body,pic,webname,keyword,link,diy}
chmod +x /opt/spider-pool/spider-pool

# 4. 创建 systemd 服务
# spider-pool 蜘蛛池进程
cat > /etc/systemd/system/spider-pool.service << 'EOF'
[Unit]
Description=WanZhanTong - Spider Process
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/spider-pool
ExecStart=/opt/spider-pool/spider-pool --mode=spider
Environment=GOMEMLIMIT=30GiB
Environment=GOGC=200
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# spider-admin 后台管理进程
cat > /etc/systemd/system/spider-admin.service << 'EOF'
[Unit]
Description=WanZhanTong - Admin Process
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/spider-pool
ExecStart=/opt/spider-pool/spider-pool --mode=admin
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 5. 启动服务
systemctl daemon-reload
systemctl enable spider-pool spider-admin
systemctl start spider-pool spider-admin

# 6. 验证
systemctl status spider-pool
systemctl status spider-admin
```

安装完成后访问: `http://服务器IP:8081/admin/`

> **注意**: 手动部署不包含系统调优和 ClickHouse 安装。如需 ClickHouse（蜘蛛日志统计），请参考 [ClickHouse 官方文档](https://clickhouse.com/docs/en/install) 单独安装。

### 手动更新

```bash
# 停止服务
systemctl stop spider-pool spider-admin

# 备份旧版本
cp /opt/spider-pool/spider-pool /opt/spider-pool/spider-pool.bak

# 替换二进制（从本地上传或直接下载）
scp spider-pool-linux-amd64 root@服务器IP:/opt/spider-pool/spider-pool
# 或在服务器上直接下载:
# wget -O /opt/spider-pool/spider-pool https://github.com/i8j888/wztseo/raw/main/spider-pool-linux-amd64

chmod +x /opt/spider-pool/spider-pool

# 重启服务
systemctl start spider-pool spider-admin
```

数据库和配置会保留，只更新二进制文件。

## 架构

```
                    ┌─────────────────┐
                    │   Cloudflare    │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
     ┌────────▼───────┐  ┌──▼───────┐  ┌──▼──────┐
     │ spider-pool    │  │ spider-  │  │ 其他    │
     │ :8080          │  │ admin    │  │ 域名    │
     │ 蜘蛛池+渲染    │  │ :8081    │  │ ...     │
     └────────┬───────┘  │ 后台管理 │  └─────────┘
              │          └──┬───────┘
     ┌────────▼─────────────▼────────┐
     │        SQLite + ClickHouse    │
     │        数据存储               │
     └───────────────────────────────┘
```

- **spider-pool (8080)** — 处理所有前端请求，渲染页面
- **spider-admin (8081)** — 后台管理API和界面

## 使用指南

### 泛目录模式

系统支持任意URL路径自动匹配：

```
https://example.com/game/slot-123.html      → 游戏类内容页
https://example.com/casino/bonus-456.html   → 赌场类内容页
https://example.com/任意目录/任意页面.html    → 自动匹配内容
```

在模型管理中配置URL规则：
- `/{pinyin}/{id}.html` — 分类拼音+文章ID
- `/detail/{id}.html` — 详情页
- `/{pinyin}/` — 分类列表页

### 蜘蛛池模式

1. 批量添加域名（建议50+）
2. 配置强引设置，吸引搜索引擎蜘蛛
3. 在外链管理中添加目标网站URL
4. 蜘蛛爬到蜘蛛池页面时，顺着外链去爬目标站

### 站群模式

1. 将域名按用途分组（游戏组、百科组、新闻组等）
2. 每组绑定不同模板和内容
3. 系统自动为每个域名生成独特的视觉指纹
4. 模板匹配优先级: 模板管理绑定 → 分组模型匹配 → default兜底

### AI文章生成

1. 在采集管理中配置AI端点（推荐 Gemini Flash）
2. 创建AI生成任务，选择分组和关键词
3. 系统自动批量生成多语言SEO文章
4. 支持AI关键词扩展（核心词→长尾词）

## 管理命令

```bash
# 查看服务状态
systemctl status spider-pool
systemctl status spider-admin

# 重启服务
systemctl restart spider-pool
systemctl restart spider-admin

# 查看实时日志
journalctl -u spider-pool -f
journalctl -u spider-admin -f

# 停止服务
systemctl stop spider-pool spider-admin
```

## 目录结构

```
/opt/spider-pool/
├── spider-pool              # 主程序二进制
├── data/
│   ├── spider-pool.db       # SQLite 数据库（自动创建）
│   ├── templates/           # 模板文件
│   ├── keywords/            # 关键词库
│   └── articles/            # 文章数据
```

## License

MIT License

#!/bin/bash
# 万站通 WanZhanTong 一键安装/更新脚本
# 用法: bash <(curl -sL https://raw.githubusercontent.com/i8j888/wztseo/main/install.sh)

set -e

INSTALL_DIR="/opt/spider-pool"
DATA_DIR="$INSTALL_DIR/data"
BIN_NAME="spider-pool"
GITHUB_REPO="i8j888/wztseo"
VERSION="v2.10.321"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  万站通 WanZhanTong $VERSION 安装程序${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

# ── 检查环境 ──────────────────────────────────────────
[ "$(id -u)" -ne 0 ] && err "请使用 root 用户运行: sudo bash install.sh"

ARCH=$(uname -m)
[ "$ARCH" != "x86_64" ] && err "仅支持 x86_64 架构，当前: $ARCH"

if [ -f /etc/debian_version ]; then
    OS="debian"
    PKG_CMD="apt-get"
elif [ -f /etc/redhat-release ] || [ -f /etc/centos-release ] || [ -f /etc/system-release ]; then
    OS="centos"
    if command -v dnf >/dev/null 2>&1; then
        PKG_CMD="dnf"
    else
        PKG_CMD="yum"
    fi
else
    OS="unknown"
    warn "未识别的系统，将尝试继续"
fi
info "系统: $OS | 架构: $ARCH | 包管理器: ${PKG_CMD:-none}"

# 检查是否为更新
IS_UPDATE=0
if [ -f "$INSTALL_DIR/$BIN_NAME" ]; then
    IS_UPDATE=1
    info "检测到已安装，将执行更新"
fi

# ── 安装依赖 ──────────────────────────────────────────
log "检查依赖..."
if [ "$OS" = "debian" ]; then
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq curl wget ca-certificates >/dev/null 2>&1
elif [ "$OS" = "centos" ]; then
    $PKG_CMD install -y -q curl wget ca-certificates >/dev/null 2>&1
fi

# ── 创建目录 ──────────────────────────────────────────
log "创建目录..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR"/{templates,keywords,article,body,pic,webname,keyword,link,diy}

# ── 下载二进制 ────────────────────────────────────────
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/raw/main/spider-pool-linux-amd64"
TMP_BIN="/tmp/$BIN_NAME-new"

log "下载二进制文件 ($VERSION)..."
if command -v curl >/dev/null 2>&1; then
    curl -L --progress-bar -o "$TMP_BIN" "$DOWNLOAD_URL" || err "下载失败，请检查网络"
elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$TMP_BIN" "$DOWNLOAD_URL" || err "下载失败，请检查网络"
else
    err "需要 curl 或 wget"
fi

# 验证文件
FILE_SIZE=$(stat -c%s "$TMP_BIN" 2>/dev/null || stat -f%z "$TMP_BIN" 2>/dev/null)
[ "$FILE_SIZE" -lt 1000000 ] && err "下载的文件太小 (${FILE_SIZE} bytes)，可能下载失败"
log "下载完成 ($((FILE_SIZE/1048576))MB)"

# ── 停止旧服务 ────────────────────────────────────────
if systemctl is-active --quiet spider-pool 2>/dev/null; then
    log "停止 spider-pool..."
    systemctl stop spider-pool
fi
if systemctl is-active --quiet spider-admin 2>/dev/null; then
    log "停止 spider-admin..."
    systemctl stop spider-admin
fi

# ── 备份旧版本 ────────────────────────────────────────
if [ "$IS_UPDATE" -eq 1 ]; then
    log "备份旧版本..."
    cp "$INSTALL_DIR/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME.bak"
fi

# ── 安装二进制 ────────────────────────────────────────
log "安装二进制..."
mv "$TMP_BIN" "$INSTALL_DIR/$BIN_NAME"
chmod +x "$INSTALL_DIR/$BIN_NAME"

# 修复 SELinux 标签（CentOS/RHEL 系统从 /tmp mv 的文件标签不对）
if command -v restorecon >/dev/null 2>&1; then
    chcon -t bin_t "$INSTALL_DIR/$BIN_NAME" 2>/dev/null
fi

# ── 创建默认配置文件（仅首次安装）────────────────────
if [ ! -f "$INSTALL_DIR/config/config.yaml" ]; then
    log "创建默认配置..."
    mkdir -p "$INSTALL_DIR/config"
    cat > "$INSTALL_DIR/config/config.yaml" << 'CFGEOF'
server:
  listen: ":8080"
  read_timeout: 10
  write_timeout: 30

cache:
  enabled: true
  max_size: 2000
  ttl: 300

log:
  level: "info"

defaults:
  redirect_url: ""
  robots_text: |
    User-agent: *
    Allow: /
    Sitemap: /sitemap.xml

data_dir: "./data"
CFGEOF
fi

# ── 系统调优（仅首次安装）────────────────────────────
if [ "$IS_UPDATE" -eq 0 ]; then
    log "系统调优..."

    # 文件描述符
    if ! grep -q "spider-pool" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf <<'EOF'
# spider-pool
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
    fi

    mkdir -p /etc/systemd/system.conf.d
    cat > /etc/systemd/system.conf.d/limits.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
EOF

    # 内核参数
    if ! grep -q "spider-pool" /etc/sysctl.conf 2>/dev/null; then
        cat >> /etc/sysctl.conf <<'EOF'
# spider-pool
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10000 65535
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535
fs.file-max = 2097152
EOF
        sysctl -p >/dev/null 2>&1
    fi

    # 防火墙放行端口
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        log "防火墙放行 8080/8081 端口..."
        firewall-cmd --permanent --add-port=8080/tcp --add-port=8081/tcp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    elif command -v ufw >/dev/null 2>&1 && ufw status | grep -q "active"; then
        log "防火墙放行 8080/8081 端口..."
        ufw allow 8080/tcp >/dev/null 2>&1
        ufw allow 8081/tcp >/dev/null 2>&1
    fi

    # ── 安装 ClickHouse（可选）────────────────────────
    if ! command -v clickhouse-client >/dev/null 2>&1; then
        echo ""
        read -p "是否安装 ClickHouse？(蜘蛛日志统计，推荐) [Y/n]: " INSTALL_CH
        INSTALL_CH=${INSTALL_CH:-Y}
        if [[ "$INSTALL_CH" =~ ^[Yy]$ ]]; then
            log "安装 ClickHouse..."
            if [ "$OS" = "debian" ]; then
                apt-get install -y -qq apt-transport-https ca-certificates gnupg >/dev/null 2>&1
                GNUPGHOME=$(mktemp -d)
                GNUPGHOME="$GNUPGHOME" gpg --no-default-keyring \
                    --keyring /usr/share/keyrings/clickhouse-keyring.gpg \
                    --keyserver hkp://keyserver.ubuntu.com:80 \
                    --recv-keys 8919F6BD2B48D754 >/dev/null 2>&1
                rm -rf "$GNUPGHOME"
                chmod +r /usr/share/keyrings/clickhouse-keyring.gpg
                echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" \
                    > /etc/apt/sources.list.d/clickhouse.list
                apt-get update -qq >/dev/null 2>&1
                DEBIAN_FRONTEND=noninteractive apt-get install -y -qq clickhouse-server clickhouse-client >/dev/null 2>&1
            elif [ "$OS" = "centos" ]; then
                $PKG_CMD install -y -q yum-utils >/dev/null 2>&1
                yum-config-manager --add-repo https://packages.clickhouse.com/rpm/clickhouse.repo >/dev/null 2>&1
                $PKG_CMD install -y -q clickhouse-server clickhouse-client >/dev/null 2>&1
            fi
            systemctl enable clickhouse-server >/dev/null 2>&1
            systemctl start clickhouse-server
            sleep 2

            # 建库建表
            clickhouse-client <<'SQL' 2>/dev/null
CREATE DATABASE IF NOT EXISTS spider;
CREATE TABLE IF NOT EXISTS spider.logs (
    created_at DateTime,
    spider_type LowCardinality(String),
    domain LowCardinality(String),
    path String,
    ip String,
    ua String,
    template LowCardinality(String),
    terminal LowCardinality(String),
    date Date MATERIALIZED toDate(created_at)
) ENGINE = MergeTree
PARTITION BY date
ORDER BY (date, spider_type, domain, created_at)
TTL date + toIntervalDay(30)
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS spider.logs_heat_hourly (
    hour DateTime,
    spider_type LowCardinality(String),
    root_domain LowCardinality(String),
    cnt UInt64
) ENGINE = SummingMergeTree
ORDER BY (hour, spider_type, root_domain);

CREATE MATERIALIZED VIEW IF NOT EXISTS spider.logs_heat_hourly_mv
TO spider.logs_heat_hourly AS
SELECT
    toStartOfHour(created_at) AS hour,
    spider_type,
    domain AS root_domain,
    count() AS cnt
FROM spider.logs
GROUP BY hour, spider_type, root_domain;
SQL
            log "ClickHouse 安装完成"
        else
            info "跳过 ClickHouse（蜘蛛日志将只写入本地文件）"
        fi
    else
        log "ClickHouse 已安装"
    fi

    # ── 生成 JWT Secret ──────────────────────────────
    JWT_SECRET=$(head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 24)

    # ── 创建 systemd 服务 ────────────────────────────
    log "配置 systemd 服务..."

    cat > /etc/systemd/system/spider-pool.service << SVCEOF
[Unit]
Description=WanZhanTong - Spider Process
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BIN_NAME --mode=spider
Environment=JWT_SECRET=$JWT_SECRET
Environment=GOMEMLIMIT=30GiB
Environment=GOGC=200
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SVCEOF

    cat > /etc/systemd/system/spider-admin.service << SVCEOF
[Unit]
Description=WanZhanTong - Admin Process
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BIN_NAME --mode=admin
Environment=JWT_SECRET=$JWT_SECRET
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable spider-pool spider-admin >/dev/null 2>&1
fi

# ── 启动服务 ──────────────────────────────────────────
log "启动服务..."
systemctl daemon-reload
systemctl start spider-pool
systemctl start spider-admin
sleep 5

# 等待服务就绪
for i in 1 2 3; do
    SP_STATUS=$(systemctl is-active spider-pool 2>/dev/null || echo "failed")
    SA_STATUS=$(systemctl is-active spider-admin 2>/dev/null || echo "failed")
    [ "$SP_STATUS" = "active" ] && [ "$SA_STATUS" = "active" ] && break
    sleep 3
done

# ── 获取服务器IP ──────────────────────────────────────
SERVER_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || curl -s --max-time 3 ip.sb 2>/dev/null || echo "服务器IP")

echo ""
echo -e "${GREEN}============================================${NC}"
if [ "$IS_UPDATE" -eq 1 ]; then
    echo -e "${GREEN}  万站通 WanZhanTong 更新完成 $VERSION${NC}"
else
    echo -e "${GREEN}  万站通 WanZhanTong 安装完成 $VERSION${NC}"
fi
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  spider-pool (8080): $SP_STATUS"
echo "  spider-admin (8081): $SA_STATUS"
echo ""
echo -e "  后台地址: ${CYAN}http://$SERVER_IP:8081/admin/${NC}"
echo "  默认账号: admin"
echo "  默认密码: admin123"
echo "  安全码:   1314"
echo ""
if [ "$IS_UPDATE" -eq 0 ]; then
echo "  下一步:"
echo "    1. 浏览器打开后台地址，完成安装向导"
echo "    2. 修改默认密码"
echo "    3. 添加域名（域名需解析到 $SERVER_IP）"
echo "    4. 选择模板 → 添加内容 → 开始运行"
echo ""
fi
echo "  管理命令:"
echo "    systemctl status spider-pool     # 蜘蛛池状态"
echo "    systemctl status spider-admin    # 后台状态"
echo "    systemctl restart spider-pool    # 重启蜘蛛池"
echo "    systemctl restart spider-admin   # 重启后台"
echo "    journalctl -u spider-pool -f     # 实时日志"
echo ""
echo -e "${GREEN}============================================${NC}"

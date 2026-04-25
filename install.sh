#!/bin/bash
# 万站通 WanZhanTong — 新服务器一键环境安装脚本
# 适用：Debian 11/12/13, Ubuntu 22.04+
# 要求：root, 4GB+ 内存
# 用法：bash install.sh
#
# 完成项：
#   1. 系统更新 + 文件描述符上限 + 内核调优
#   2. 安装 Go 1.26.2
#   3. 安装 ClickHouse + 建库建表
#   4. 安装 Nginx
#   5. 创建 /opt/spider-pool 目录 + 默认 config.yaml
#   6. 创建 systemd 单元（spider-pool / spider-admin）
#   7. 不启动服务（等你 scp 二进制后再 systemctl start）

set -euo pipefail
trap 'echo "⚠️  步骤失败（行 $LINENO），继续安装..."; set +e' ERR

GO_VERSION="1.26.2"
INSTALL_DIR="/opt/spider-pool"
JWT_SECRET=$(openssl rand -hex 32 2>/dev/null || head -c32 /dev/urandom | base64 | tr -d '\n=+/' | cut -c1-64)

# 检查 root
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请用 root 运行：sudo bash install.sh"
  exit 1
fi

# 检查系统
if ! grep -qiE "debian|ubuntu" /etc/os-release; then
  echo "⚠️  脚本只在 Debian/Ubuntu 测过，其它系统请手动按 INSTALL.md 操作"
  read -p "继续？[y/N] " yn
  [ "$yn" = "y" ] || exit 1
fi

echo "════════════════════════════════════════════════════════════════"
echo "  万站通 WanZhanTong — 一键环境安装"
echo "  Go: $GO_VERSION  |  ClickHouse: latest stable"
echo "  安装目录: $INSTALL_DIR"
echo "════════════════════════════════════════════════════════════════"

# ════════ 内存检查 ═══════════════════════════════════════════════════
TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
echo ""
if [ "$TOTAL_MEM_MB" -lt 2048 ]; then
  echo "❌ 内存不足：当前 ${TOTAL_MEM_MB}MB，最低要求 2GB（建议 4GB+）"
  echo "   ClickHouse 需要 ~800MB，蜘蛛池需要 1-4GB"
  exit 1
elif [ "$TOTAL_MEM_MB" -lt 4096 ]; then
  echo "⚠️  内存偏低：当前 ${TOTAL_MEM_MB}MB，建议 4GB 以上"
  echo "   2GB 可以安装但高并发时可能 OOM，按 Ctrl+C 取消或等 5 秒继续..."
  sleep 5
else
  echo "✓ 内存：${TOTAL_MEM_MB}MB"
fi
sleep 1

# ════════ 1. 系统基础 ═══════════════════════════════════════════════
echo ""
echo "▶ [1/6] 系统更新和基础包"
export DEBIAN_FRONTEND=noninteractive
apt update -qq
apt install -y -qq curl wget git build-essential vim htop net-tools sqlite3 \
                   tar gnupg apt-transport-https ca-certificates openssl \
                   >/dev/null

# 文件描述符上限
if ! grep -q "1048576" /etc/security/limits.conf 2>/dev/null; then
  cat >> /etc/security/limits.conf <<'EOF'

# Go 蜘蛛池 — 高并发文件描述符上限
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
fi

mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/spider-pool-limits.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
EOF

# 内核参数
if ! grep -q "spider-pool" /etc/sysctl.conf; then
  cat >> /etc/sysctl.conf <<'EOF'

# Go 蜘蛛池 — TIME_WAIT 复用 + 端口范围 + backlog
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10000 65535
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535
fs.file-max = 2097152
EOF
fi
sysctl -p >/dev/null

systemctl daemon-reload
echo "   ✓ 系统调优完成（文件描述符 1048576 + sysctl 调优）"

# ════════ 2. Go ═════════════════════════════════════════════════════
echo ""
echo "▶ [2/6] 安装 Go $GO_VERSION（用于编译，如果使用预编译二进制可跳过）"
if /usr/local/go/bin/go version 2>/dev/null | grep -q "$GO_VERSION"; then
  echo "   ✓ Go $GO_VERSION 已存在，跳过"
else
  cd /tmp
  wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
  rm "go${GO_VERSION}.linux-amd64.tar.gz"

  if ! grep -q "/usr/local/go/bin" /etc/profile; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
  fi
  export PATH=$PATH:/usr/local/go/bin
  echo "   ✓ Go 安装完成: $(/usr/local/go/bin/go version)"
fi

# ════════ 3. ClickHouse ═══════════════════════════════════════════════
echo ""
echo "▶ [3/6] 安装 ClickHouse"
if systemctl is-active clickhouse-server >/dev/null 2>&1; then
  echo "   ✓ ClickHouse 已在运行，跳过安装"
else
  # 获取 ClickHouse GPG key（多源 fallback，国内服务器 keyserver.ubuntu.com 经常超时）
  KEY_OK=0
  for KEY_URL in \
      "https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key" \
      "https://repo.clickhouse.com/CLICKHOUSE-KEY.GPG"; do
    if curl -fsSL --connect-timeout 10 "$KEY_URL" 2>/dev/null | gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg 2>/dev/null; then
      KEY_OK=1
      echo "   • CH GPG key 获取成功: $KEY_URL"
      break
    fi
  done
  if [ "$KEY_OK" -eq 0 ]; then
    # 最后尝试 keyserver
    GNUPGHOME=$(mktemp -d)
    if GNUPGHOME="$GNUPGHOME" gpg --no-default-keyring \
        --keyring /usr/share/keyrings/clickhouse-keyring.gpg \
        --keyserver hkp://keyserver.ubuntu.com:80 \
        --recv-keys 8919F6BD2B48D754 2>/dev/null; then
      KEY_OK=1
    fi
    rm -rf "$GNUPGHOME"
  fi
  if [ "$KEY_OK" -eq 0 ]; then
    echo "   ❌ ClickHouse GPG key 拉取失败（网络问题）"
    echo "      请手动安装：apt install -y clickhouse-server clickhouse-client"
    exit 1
  fi
  chmod +r /usr/share/keyrings/clickhouse-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" \
    > /etc/apt/sources.list.d/clickhouse.list

  apt update -qq
  echo "clickhouse-server clickhouse-server/default-password password" | debconf-set-selections
  apt install -y -qq clickhouse-server clickhouse-client >/dev/null

  systemctl enable clickhouse-server >/dev/null 2>&1
  systemctl start clickhouse-server
  # 等 CH 真正接受连接，最多等 30s
  for i in $(seq 1 30); do
    if clickhouse-client -q "SELECT 1" >/dev/null 2>&1; then break; fi
    sleep 1
  done
  if ! clickhouse-client -q "SELECT 1" >/dev/null 2>&1; then
    echo "   ❌ ClickHouse 启动后 30s 内未就绪，请手动排查"
    journalctl -u clickhouse-server -n 20 --no-pager
    exit 1
  fi
  echo "   ✓ ClickHouse 安装完成: $(clickhouse-client --version 2>&1)"
fi

# 建库建表（幂等，已存在不报错）
echo "   • 创建 spider 数据库和 logs 表"
clickhouse-client <<'SQL'
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
SQL

CH_TABLES=$(clickhouse-client -q "SHOW TABLES FROM spider" 2>&1)
echo "   ✓ ClickHouse 表已就绪: $CH_TABLES"

# ════════ 4. Nginx / OpenResty ═══════════════════════════════════
echo ""
echo "▶ [4/6] 检查 Web 服务器"
if command -v openresty >/dev/null 2>&1 || ss -tlnp | grep -q openresty; then
  echo "   ✓ 检测到 OpenResty 已在运行，跳过 Nginx 安装"
  echo "   • 请在 OpenResty/宝塔 中配置反向代理到 unix:/tmp/spider-pool.sock"
  WEB_SERVER="openresty"
elif command -v nginx >/dev/null 2>&1 && systemctl is-active nginx >/dev/null 2>&1; then
  echo "   ✓ Nginx 已在运行: $(nginx -v 2>&1)"
  WEB_SERVER="nginx"
elif ss -tlnp | grep -qE ':80 .*nginx|:80 .*openresty|:80 .*caddy|:80 .*apache'; then
  echo "   ✓ 检测到 80 端口已被占用，跳过 Nginx 安装"
  echo "   • 请手动配置现有 Web 服务器反向代理到 unix:/tmp/spider-pool.sock"
  WEB_SERVER="other"
else
  apt install -y -qq nginx >/dev/null 2>&1 || true
  if command -v nginx >/dev/null 2>&1; then
    systemctl enable nginx >/dev/null 2>&1
    systemctl start nginx 2>/dev/null || true
    echo "   ✓ Nginx 安装完成: $(nginx -v 2>&1)"
    WEB_SERVER="nginx"
  else
    echo "   ⚠️  Nginx 安装失败，请手动安装 Web 服务器"
    WEB_SERVER="none"
  fi
fi

# ════════ 5. 蜘蛛池目录 + 配置 ═══════════════════════════════════════
echo ""
echo "▶ [5/6] 创建蜘蛛池目录 + 配置"
mkdir -p "$INSTALL_DIR/data" "$INSTALL_DIR/config"

if [ ! -f "$INSTALL_DIR/config/config.yaml" ]; then
  cat > "$INSTALL_DIR/config/config.yaml" <<'EOF'
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
EOF
  echo "   ✓ 默认 config.yaml 已生成: $INSTALL_DIR/config/config.yaml"
else
  echo "   • config.yaml 已存在，保留不动"
fi

# ════════ 6. systemd 单元 ═══════════════════════════════════════════
echo ""
echo "▶ [6/6] 创建 systemd 单元"

cat > /etc/systemd/system/spider-pool.service <<EOF
[Unit]
Description=Go Spider Pool - Spider Process
After=network.target clickhouse-server.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/spider-pool --mode=spider
Environment=JWT_SECRET=$JWT_SECRET
Environment=GOMEMLIMIT=32GiB
Environment=GOGC=50
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/spider-admin.service <<EOF
[Unit]
Description=Go Spider Pool - Admin Process
After=network.target spider-pool.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/spider-pool --mode=admin
Environment=JWT_SECRET=$JWT_SECRET
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable spider-pool spider-admin >/dev/null 2>&1 || true
echo "   ✓ systemd 单元已创建并 enable（开机自启，等二进制就位后 systemctl start 即可）"

# ════════ 防火墙放行 ═════════════════════════════════════════════════
echo ""
echo "▶ 防火墙端口放行"
if command -v ufw >/dev/null 2>&1; then
  ufw allow 8080/tcp >/dev/null 2>&1 && echo "   ✓ UFW: 8080 (蜘蛛池前端)" || true
  ufw allow 8081/tcp >/dev/null 2>&1 && echo "   ✓ UFW: 8081 (管理后台)" || true
  ufw allow 80/tcp >/dev/null 2>&1 || true
  ufw allow 443/tcp >/dev/null 2>&1 || true
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=8080/tcp >/dev/null 2>&1 || true
  firewall-cmd --permanent --add-port=8081/tcp >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
  echo "   ✓ firewalld: 8080/8081 已放行"
else
  echo "   • 未检测到防火墙，跳过"
fi
echo "   ⚠️  如果使用阿里云/腾讯云，还需要在云控制台安全组中放行 8080 和 8081"

# ════════ 完成 ═══════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ 万站通环境安装完成"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  下一步："
echo ""
echo "  1️⃣  安装二进制："
echo "      cp spider-pool $INSTALL_DIR/"
echo ""
echo "  2️⃣  启动服务："
echo "      systemctl start spider-pool spider-admin"
echo ""
echo "  3️⃣  验证："
echo "      curl -I http://127.0.0.1:8080/"
echo "      curl -I http://127.0.0.1:8081/admin/"
echo ""
echo "  4️⃣  首次访问后台 http://服务器IP:8081/admin/"
echo "      → 安装向导设置管理员账号密码"
echo "      → 授权管理填入 wztseo.com 的 API Key 激活"
echo ""
echo "  5️⃣  配置域名反向代理（Nginx/OpenResty/宝塔）"
echo "      → 参考 INSTALL.md 第 6-7 章"
echo ""
echo "  ⚠️  重新 SSH 登录后 ulimit 才生效（或运行 ulimit -n 1048576）"
echo ""

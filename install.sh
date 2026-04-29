#!/bin/bash
# WanZhanTong (万站通) 一键安装脚本
# 支持: Debian/Ubuntu/CentOS

set -e

INSTALL_DIR="/opt/spider-pool"
DATA_DIR="$INSTALL_DIR/data"
BIN_NAME="spider-pool"
VERSION="v2.10.319"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[WZT]${NC} $1"; }
warn() { echo -e "${YELLOW}[WZT]${NC} $1"; }
err() { echo -e "${RED}[WZT]${NC} $1"; exit 1; }

# 检查 root
[ "$(id -u)" -ne 0 ] && err "请使用 root 用户运行此脚本"

# 检查系统
if [ -f /etc/debian_version ]; then
    OS="debian"
elif [ -f /etc/redhat-release ]; then
    OS="centos"
else
    warn "未识别的系统，将尝试继续安装"
    OS="unknown"
fi

log "系统: $OS | 架构: $(uname -m)"

# 检查架构
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    err "当前仅支持 x86_64 架构，检测到: $ARCH"
fi

# 创建目录
log "创建安装目录..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR/templates"
mkdir -p "$DATA_DIR/keywords"
mkdir -p "$DATA_DIR/articles"

# 检查二进制文件
if [ ! -f "./$BIN_NAME-linux-amd64" ]; then
    err "未找到二进制文件 $BIN_NAME-linux-amd64，请确保在安装包目录下运行"
fi

# 停止旧服务
if systemctl is-active --quiet spider-pool 2>/dev/null; then
    log "停止旧的 spider-pool 服务..."
    systemctl stop spider-pool
fi
if systemctl is-active --quiet spider-admin 2>/dev/null; then
    log "停止旧的 spider-admin 服务..."
    systemctl stop spider-admin
fi

# 复制二进制
log "安装二进制文件..."
cp "./$BIN_NAME-linux-amd64" "$INSTALL_DIR/$BIN_NAME"
chmod +x "$INSTALL_DIR/$BIN_NAME"

# 生成 JWT Secret
JWT_SECRET=$(head -c 32 /dev/urandom | base64 | tr -d '=/+' | head -c 24)

# 创建 systemd 服务
log "配置 systemd 服务..."

cat > /etc/systemd/system/spider-pool.service << EOF
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
EOF

cat > /etc/systemd/system/spider-admin.service << EOF
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
EOF

systemctl daemon-reload

# 启动服务
log "启动服务..."
systemctl enable spider-pool spider-admin
systemctl start spider-pool
systemctl start spider-admin

sleep 2

# 检查状态
SP_STATUS=$(systemctl is-active spider-pool)
SA_STATUS=$(systemctl is-active spider-admin)

echo ""
echo "============================================"
echo -e "  ${GREEN}万站通 WanZhanTong $VERSION 安装完成${NC}"
echo "============================================"
echo ""
echo "  安装目录: $INSTALL_DIR"
echo "  数据目录: $DATA_DIR"
echo ""
echo "  spider-pool (8080): $SP_STATUS"
echo "  spider-admin (8081): $SA_STATUS"
echo ""
echo "  后台地址: http://服务器IP:8081/admin/"
echo "  默认账号: admin"
echo "  默认密码: admin123"
echo "  安全码:   1314"
echo ""
echo "  JWT Secret: $JWT_SECRET"
echo "  (请妥善保管，修改密码后此密钥用于验证登录)"
echo ""
echo "  管理命令:"
echo "    systemctl status spider-pool    # 查看蜘蛛池状态"
echo "    systemctl status spider-admin   # 查看后台状态"
echo "    systemctl restart spider-pool   # 重启蜘蛛池"
echo "    systemctl restart spider-admin  # 重启后台"
echo "    journalctl -u spider-pool -f    # 查看实时日志"
echo ""
echo "  下一步:"
echo "    1. 访问后台修改默认密码"
echo "    2. 添加域名（域名需解析到本服务器IP）"
echo "    3. 选择/创建模板"
echo "    4. 添加文章内容或配置AI生成"
echo ""
echo "============================================"

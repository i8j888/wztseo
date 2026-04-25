#!/bin/bash
# Deploy spider-pool-go to server
# Architecture: Cloudflare → spider-pool:8080 (direct, no nginx)
# Usage: ./deploy.sh [commit message]

SERVER=172.96.142.176
REMOTE_DIR="/opt/spider-pool"
SSH="ssh root@$SERVER"

# ── 1. 自动递增版本号 ──────────────────────────────────────────
LAST_TAG=$(git tag --sort=-v:refname | head -1)
[ -z "$LAST_TAG" ] && LAST_TAG="v2.10.0"
MAJOR=$(echo $LAST_TAG | cut -d. -f1 | tr -d 'v')
MINOR=$(echo $LAST_TAG | cut -d. -f2)
PATCH=$(echo $LAST_TAG | cut -d. -f3)
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
MSG=${1:-"v$NEW_VERSION"}

echo "=== 版本: $LAST_TAG → v$NEW_VERSION ==="

# ── 1.5 构建前端（go:embed all:web/dist 需要最新 dist）──────
if [ -d web ] && [ -f web/package.json ]; then
  if [ -n "$(find web/src -newer web/dist/index.html 2>/dev/null | head -1)" ] || [ ! -f web/dist/index.html ]; then
    echo "=== 检测到前端变更，构建 web/dist ==="
    (cd web && npm run build) || { echo "前端构建失败，退出"; exit 1; }
  else
    echo "=== 前端无变更，跳过 npm build ==="
  fi
fi

# ── 2. git 提交 ────────────────────────────────────────────────
git add .
if git diff --cached --quiet; then
  echo "=== 无变更，跳过 git commit ==="
else
  git commit -m "$MSG"
  echo "=== git commit: $MSG ==="
fi
git tag "v$NEW_VERSION"
echo "=== git tag v$NEW_VERSION ==="

# ── 3. 编译（CGO 需在服务器上做：mattn/go-sqlite3）────────────
echo "=== 上传源码到服务器编译（CGO）==="
tar czf /tmp/sp-src.tar.gz --exclude=.git --exclude=node_modules --exclude=data \
    --exclude=spider-pool-linux --exclude='*.bak*' .
scp -q /tmp/sp-src.tar.gz root@$SERVER:/tmp/
$SSH "set -e
  rm -rf /tmp/sp-build && mkdir /tmp/sp-build && cd /tmp/sp-build
  tar xzf /tmp/sp-src.tar.gz 2>/dev/null
  export PATH=/usr/local/go/bin:\$PATH
  CGO_ENABLED=1 go build -ldflags='-s -w -X main.Version=$NEW_VERSION' -o spider-pool .
  ls -lh spider-pool
"
if [ $? -ne 0 ]; then echo "服务器编译失败，退出"; exit 1; fi

# ── 4. 部署 ────────────────────────────────────────────────────
echo "=== 切换二进制并重启 ==="
$SSH "systemctl stop spider-pool spider-admin && \
      cp /tmp/sp-build/spider-pool $REMOTE_DIR/spider-pool && \
      systemctl start spider-pool && sleep 3 && \
      systemctl start spider-admin && sleep 3 && \
      systemctl is-active spider-pool spider-admin && \
      journalctl -u spider-pool -n 3 --no-pager"

echo ""
echo "=== 部署完成 v$NEW_VERSION ==="

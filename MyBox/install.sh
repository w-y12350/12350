
#!/usr/bin/env bash
set -Eeuo pipefail

REPO="w-y12350/12350"
BRANCH="main"
DEST="/usr/local/bin/mybox"

if [[ "$EUID" -ne 0 ]]; then
  echo "请使用 root 权限运行。"
  exit 1
fi

. /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *)
    echo "MyBox 目前仅支持 Ubuntu / Debian。"
    exit 1
    ;;
esac

apt-get update
apt-get install -y curl ca-certificates

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/mybox.sh"

echo "正在下载 MyBox..."
curl -fLsS --retry 3 "$URL" -o "$TMP"

echo "检查 Shell 语法..."
bash -n "$TMP"

install -m 755 "$TMP" "$DEST"

echo "安装入口已准备好。"
echo "正在初始化 sing-box..."
"$DEST" install

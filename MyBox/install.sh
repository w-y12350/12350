
#!/usr/bin/env bash
set -Eeuo pipefail

REPO="w-y12350/12350"
BRANCH="main"
INSTALL_DIR="/usr/local/bin"

if [[ "${EUID}" -ne 0 ]]; then
  echo "请使用 root 权限运行，或使用 sudo。"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  apt-get update
  apt-get install -y curl
fi

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/mybox.sh"

echo "正在下载 MyBox..."
curl -fL --retry 3 "$URL" -o "$TMP_FILE"

bash -n "$TMP_FILE"

install -m 0755 "$TMP_FILE" "${INSTALL_DIR}/mybox"

echo "MyBox 管理脚本已安装。"
echo "运行命令：mybox"



#!/usr/bin/env bash
# MyBox V1 - sing-box 中文管理工具
# 许可证：GPL-3.0-or-later（仅适用于本项目自身代码；
# 如包含或修改其他 GPL 项目代码，请保留其版权及许可证要求）
set -Eeuo pipefail
umask 077

APP="MyBox"
BASE="/etc/mybox"
CONF="$BASE/config.json"
DB="$BASE/nodes.tsv"
BACKUP="/var/backups/mybox"
BIN="/usr/local/bin/sing-box"
SERVICE="/etc/systemd/system/mybox.service"
LOCK="/run/lock/mybox.lock"

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "请使用 sudo 运行。"
    exit 1
  fi
}

init_dirs() {
  install -d -m 700 "$BASE" "$BACKUP"
  touch "$DB"
  chmod 600 "$DB"
}

require_installed() {
  [[ -x "$BIN" && -f "$CONF" && -f "$DB" ]] || {
    echo "请先选择菜单 1 安装 MyBox。"
    return 1
  }
}

backup_config() {
  [[ -f "$CONF" ]] || return 0
  install -d -m 700 "$BACKUP"
  cp -p "$CONF" "$BACKUP/config-$(date +%Y%m%d-%H%M%S).json"
}

check_file() {
  "$BIN" check -c "$1"
}

# 校验临时配置、备份旧配置、替换并重启；失败时回滚
apply_config() {
  local tmp="$1"
  local saved

  check_file "$tmp" || {
    echo "配置校验失败，未修改现有配置。"
    rm -f "$tmp"
    return 1
  }

  backup_config
  saved="$(mktemp "$BASE/rollback.XXXXXX")"
  cp -p "$CONF" "$saved"

  install -m 600 "$tmp" "$CONF"
  rm -f "$tmp"

  if systemctl restart mybox; then
    rm -f "$saved"
    echo "配置已更新，服务已重启。"
  else
    echo "重启失败，正在恢复旧配置。"
    install -m 600 "$saved" "$CONF"
    rm -f "$saved"
    systemctl restart mybox || true
    return 1
  fi
}

install_core() {
  need_root
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) echo "当前仅支持 Ubuntu / Debian"; return 1 ;;
  esac

  apt-get update
  apt-get install -y curl jq openssl ca-certificates tar util-linux

  local arch url tmp binfile
  case "$(dpkg --print-architecture)" in
    amd64) arch=amd64 ;;
    arm64) arch=arm64 ;;
    *)
      echo "暂不支持此 CPU 架构。"
      return 1
      ;;
  esac

  echo "正在获取 sing-box 官方最新稳定版..."
  url="$(curl -fsSL \
    https://api.github.com/repos/SagerNet/sing-box/releases/latest |
    jq -er --arg suffix "linux-${arch}.tar.gz" \
    '[.assets[] | select(.name | endswith($suffix))][0].browser_download_url')"

  tmp="$(mktemp -d)"
  if ! curl -fL --retry 3 "$url" -o "$tmp/core.tar.gz"; then
    rm -rf "$tmp"
    return 1
  fi
  tar -xzf "$tmp/core.tar.gz" -C "$tmp"
  binfile="$(find "$tmp" -type f -name sing-box -perm /111 -print -quit)"
  if [[ -z "$binfile" ]]; then
    echo "安装包中没有找到 sing-box 可执行文件。"
    rm -rf "$tmp"
    return 1
  fi
  install -m 755 "$binfile" "$BIN"
  rm -rf "$tmp"

  init_dirs
  if [[ ! -f "$CONF" ]]; then
    cat > "$CONF" <<'JSON'
{
  "log": {"level": "info"},
  "inbounds": [],
  "outbounds": [{"type": "direct", "tag": "direct"}],
  "route": {"final": "direct"}
}
JSON
  fi

  cat > "$SERVICE" <<'UNIT'
[Unit]
Description=MyBox sing-box Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/mybox/config.json
Restart=on-failure
RestartSec=3
UMask=0077
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT

  check_file "$CONF"
  systemctl daemon-reload
  systemctl enable mybox
  systemctl restart mybox || systemctl start mybox

  if [[ "$(readlink -f "$0")" != \
      "$(readlink -f /usr/local/bin/mybox 2>/dev/null || true)" ]]; then
  install -m 755 "$0" /usr/local/bin/mybox
fi
  echo "MyBox 安装完成。运行：mybox"
  "$BIN" version
}

valid_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_-]{1,32}$ ]]
}

add_reality() {
  need_root
  require_installed
  local name port sni ip uuid keys private public sid tag tmp

  read -r -p "节点名称：" name
  valid_name "$name" || {
    echo "名称只允许字母、数字、下划线和连字符。"
    return 1
  }
  if awk -F '\t' -v n="$name" '$1==n {found=1} END {exit !found}' "$DB"; then
    echo "节点名称已存在。"
    return 1
  fi

  read -r -p "监听端口（1-65535）：" port
  [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)) || {
    echo "端口不合法。"
    return 1
  }
  if jq -e --argjson p "$port" \
    '.inbounds[]? | select(.listen_port == $p)' "$CONF" >/dev/null; then
    echo "该端口已在配置中使用。"
    return 1
  fi

  read -r -p "REALITY SNI 域名：" sni
  [[ "$sni" =~ ^[A-Za-z0-9.-]+$ && "$sni" == *.* ]] || {
    echo "请输入有效的域名。"
    return 1
  }

  read -r -p "服务器公网 IP 或域名：" ip
  [[ "$ip" =~ ^[A-Za-z0-9.:-]+$ ]] || {
    echo "地址格式不合法。"
    return 1
  }

  uuid="$("$BIN" generate uuid)"
  keys="$("$BIN" generate reality-keypair)"
  private="$(sed -nE 's/^[[:space:]]*PrivateKey:[[:space:]]*//p' <<< "$keys" | head -n1)"
  public="$(sed -nE 's/^[[:space:]]*PublicKey:[[:space:]]*//p' <<< "$keys" | head -n1)"
  [[ -n "$private" && -n "$public" ]] || {
    echo "无法解析 REALITY 密钥。请检查 sing-box 版本。"
    return 1
  }
  sid="$(openssl rand -hex 8)"
  tag="mybox-$name"

  tmp="$(mktemp "$BASE/config.XXXXXX")"
  jq --arg tag "$tag" --arg uuid "$uuid" \
    --arg sni "$sni" --arg key "$private" --arg sid "$sid" \
    --argjson port "$port" '
    .inbounds += [{
      "type":"vless",
      "tag":$tag,
      "listen":"::",
      "listen_port":$port,
      "users":[{"name":$tag,"uuid":$uuid,"flow":"xtls-rprx-vision"}],
      "tls":{
        "enabled":true,
        "server_name":$sni,
        "reality":{
          "enabled":true,
          "handshake":{"server":$sni,"server_port":443},
          "private_key":$key,
          "short_id":[$sid]
        }
      }
    }]
  ' "$CONF" > "$tmp"

  apply_config "$tmp" || return 1
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$port" "$uuid" "$sni" "$public" "$sid" "$ip" >> "$DB"
  chmod 600 "$DB"

  echo
  echo "节点已添加。请保存分享链接："
  printf 'vless://%s@%s:%s?type=tcp&security=reality&pbk=%s&fp=chrome&sni=%s&sid=%s&flow=xtls-rprx-vision#%s\n' \
    "$uuid" "$ip" "$port" "$public" "$sni" "$sid" "$name"
}

list_nodes() {
  need_root
  require_installed
  if [[ ! -s "$DB" ]]; then
    echo "暂无节点。"
    return
  fi
  printf '%-18s %-7s %-36s %-24s\n' "名称" "端口" "UUID" "SNI"
  while IFS=$'\t' read -r name port uuid sni public sid ip; do
    printf '%-18s %-7s %-36s %-24s\n' "$name" "$port" "$uuid" "$sni"
  done < "$DB"
}

show_link() {
  need_root
  require_installed
  list_nodes
  local name
  read -r -p "请输入节点名称：" name

  while IFS=$'\t' read -r n port uuid sni public sid ip; do
    if [[ "$n" == "$name" ]]; then
      printf 'vless://%s@%s:%s?type=tcp&security=reality&pbk=%s&fp=chrome&sni=%s&sid=%s&flow=xtls-rprx-vision#%s\n' \
        "$uuid" "$ip" "$port" "$public" "$sni" "$sid" "$n"
      return
    fi
  done < "$DB"
  echo "未找到该节点。"
}

delete_node() {
  need_root
  require_installed
  list_nodes
  local name confirm tmp dbtmp
  read -r -p "要删除的节点名称：" name
  awk -F '\t' -v n="$name" '$1==n {found=1} END {exit !found}' "$DB" || {
    echo "节点不存在。"
    return 1
  }
  read -r -p "输入 yes 确认删除：" confirm
  [[ "$confirm" == "yes" ]] || return 0

  tmp="$(mktemp "$BASE/config.XXXXXX")"
  jq --arg tag "mybox-$name" \
    '.inbounds |= map(select(.tag != $tag))' "$CONF" > "$tmp"
  apply_config "$tmp" || return 1

  dbtmp="$(mktemp "$BASE/nodes.XXXXXX")"
  awk -F '\t' -v n="$name" '$1 != n' "$DB" > "$dbtmp"
  install -m 600 "$dbtmp" "$DB"
  rm -f "$dbtmp"
  echo "节点已删除。"
}

status_mybox() {
  need_root
  systemctl --no-pager --full status mybox || true
  echo
  journalctl -u mybox -n 30 --no-pager || true
}

uninstall_mybox() {
  need_root
  local answer
  read -r -p "输入 UNINSTALL 确认卸载：" answer
  [[ "$answer" == "UNINSTALL" ]] || return 0

  systemctl disable --now mybox || true
  rm -f "$SERVICE" /usr/local/bin/mybox
  systemctl daemon-reload

  read -r -p "是否删除配置目录？输入 yes 确认：" answer
  if [[ "$answer" == "yes" ]]; then
    rm -rf "$BASE"
  fi
  read -r -p "是否删除 sing-box 核心？输入 yes 确认：" answer
  if [[ "$answer" == "yes" ]]; then
    rm -f "$BIN"
  fi

  echo "卸载完成。备份目录未删除。"
}

menu() {
  need_root
  while true; do
    echo
    echo "========== MyBox 中文管理 =========="
    echo "1. 安装 / 初始化"
    echo "2. 添加 VLESS-REALITY 节点"
    echo "3. 查看节点"
    echo "4. 查看分享链接"
    echo "5. 删除节点"
    echo "6. 服务状态和日志"
    echo "7. 卸载"
    echo "0. 退出"
    read -r -p "请选择：" choice

    case "$choice" in
      1) install_core ;;
      2) add_reality ;;
      3) list_nodes ;;
      4) show_link ;;
      5) delete_node ;;
      6) status_mybox ;;
      7) uninstall_mybox ;;
      0) exit 0 ;;
      *) echo "无效选项。" ;;
    esac
  done
}

# 防止多个管理操作同时修改配置
main() {
  need_root
  exec 9>"$LOCK"
  if ! flock -n 9; then
    echo "另一个 MyBox 操作正在运行，请稍后重试。"
    exit 1
  fi

  case "${1:-menu}" in
    install) install_core ;;
    add) add_reality ;;
    list) list_nodes ;;
    link) show_link ;;
    delete) delete_node ;;
    status) status_mybox ;;
    uninstall) uninstall_mybox ;;
    menu|*) menu ;;
  esac
}

main "$@"



# MyBox

MyBox 是面向 Ubuntu / Debian 的 sing-box 中文管理脚本。

## 功能

- sing-box 安装与卸载
- VLESS-REALITY 节点添加、查询和删除
- 生成 VLESS 分享链接
- systemd 服务管理
- JSON 配置校验与备份
- 中文交互菜单

## 安装

请先检查 install.sh 的内容，并将仓库地址修改为自己的 GitHub 地址。

```bash
curl -fsSL \
  https://raw.githubusercontent.com/你的GitHub用户名/MyBox/main/install.sh \
  -o /tmp/mybox-install.sh

less /tmp/mybox-install.sh
sudo bash /tmp/mybox-install.sh
```

## 管理

```bash
sudo mybox
sudo mybox add
sudo mybox list
sudo mybox link
sudo mybox status
```

## 注意事项

- 目前为基础版本，尚不包含 TLS 自动签发及续签。
- 修改节点功能仍需开发。
- 请在测试服务器上验证配置后再用于生产环境。
- 请勿公开分享节点链接或私钥。

## 许可证

请查看 LICENSE 文件。


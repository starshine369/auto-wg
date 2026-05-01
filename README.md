# 🌐 WireGuard Auto Setup (极简双节点组网脚本)

![Version](https://img.shields.io/badge/Version-V2.2-blue.svg)
![Bash](https://img.shields.io/badge/Language-Bash-green.svg)
![Platform](https://img.shields.io/badge/Platform-Linux-lightgrey.svg)

本脚本旨在通过交互式的引导，帮助用户在**两台 Linux 服务器**（如内网机与公网云主机、或海外 IX 与落地机）之间，快速建立一条基于 **WireGuard** 的安全加密内网隧道。

告别繁琐的密钥生成与路由配置，仅需跟着脚本的 `A -> B -> C` 三步走，即可在 1 分钟内完成端到端的隧道打通。

---

## ⚡ 核心特性

- 🤖 **全自动环境部署**：自动检测系统环境（Debian/Ubuntu/CentOS），一键安装 WireGuard 内核与必备工具。
- 🔑 **自动化密钥流转**：自动生成 Private/Public Key，并在终端以卡片形式清晰展示，方便双端复制粘贴。
- 🌍 **智能网络推算**：自动获取公网 IPv4，自动推算内网 IP 序列（如输入 `10.198.1.1` 会自动推算对端为 `10.198.1.2`），减少手动输入失误。
- 🛡️ **底层自动保活**：自动配置 `PersistentKeepalive` 与内核 IPv4 转发 (`ip_forward`)，确保隧道长久存活不断流。
- 🔌 **支持多路复用**：支持在初始化时自定义接口名称（如 `wg0`, `wg1`, `tun0`），轻松实现一台机器挂载多条不同的内网隧道。

---

## 📦 一键下载与执行

在需要组网的两台 Linux 机器上，使用 `root` 权限执行以下命令：
```bash
wget -O auto-wg.sh https://ghproxy.net/https://raw.githubusercontent.com/starshine369/auto-wg/main/auto-wg.sh && chmod +x auto-wg.sh && sudo ./auto-wg.sh
```

---

## 🎮 标准组网作战指南 (A -> B -> C)

假设您有两台机器：
*   **机器 A (本地机器/内网发起端)**：例如您的家庭服务器，或隐藏在防火墙后的机器。
*   **机器 B (云端服务器/公网机)**：例如您的 VPS 落地机，拥有公网 IP。

请严格按照以下顺序执行：

### 🛠️ Step 1: 在【机器 A】上生成基础配置
1. 在 **机器 A** 上运行脚本，输入网卡名（默认 `wg0`），然后选择模式：`[1] A. 本地机器 (内网)`。
2. 脚本会询问 B 机器是否准备好，输入 `n`。
3. 确认本机内网 IP（默认 `10.198.1.1`）。
4. 脚本执行完毕后，会打印出一个**信息卡片**。**请不要关闭此窗口，复制卡片中的信息！**

### 🛠️ Step 2: 在【机器 B】上部署服务端
1. 登录 **机器 B**，运行相同的脚本。
2. 输入相同的网卡名（默认 `wg0`），选择模式：`[2] B. 其他机器 (云端)`。
3. 根据提示，粘贴刚才从 **机器 A** 复制过来的 `PUBLIC KEY` 和 `内网 IP (10.198.1.1)`。
4. 脚本会自动获取 B 的公网 IP 并生成配置。
5. 执行完毕后，B 机器会打印出包含其公网 Endpoint 的**新信息卡片**。**复制这部分信息！**

### 🛠️ Step 3: 回到【机器 A】完成最终握手
1. 回到 **机器 A** 的终端，再次运行脚本。
2. 选择模式：`[3] C. 完成 A/B 后的最后一步`。
3. 粘贴刚才从 **机器 B** 复制过来的 `IP:Port` 和 `PUBLIC KEY`。
4. 脚本会自动重启服务并执行 Ping 测试。如果 Ping 通，则代表组网大功告成！

---
*Secure your intra-network, fast and easy.*

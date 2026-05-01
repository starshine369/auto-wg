#!/bin/bash

# ==========================================
# WireGuard Auto Setup V3.1
# ==========================================

# --- 颜色定义 / Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# --- 全局变量设定 ---
CONF_DIR="/etc/wireguard"
# 使用一个固定文件来记录用户安装时选择的网卡名，实现状态持久化
SAVE_FILE="${CONF_DIR}/.awg_iface"

# 动态加载网卡名称
if [ -f "$SAVE_FILE" ]; then
    WG_IFACE=$(cat "$SAVE_FILE")
else
    WG_IFACE="wg0"
fi

WG_CONF="${CONF_DIR}/${WG_IFACE}.conf"
PRIVATE_KEY_FILE="${CONF_DIR}/${WG_IFACE}_privatekey"
PUBLIC_KEY_FILE="${CONF_DIR}/${WG_IFACE}_publickey"
SERVICE_NAME="wg-quick@${WG_IFACE}"

# --- 辅助函数 ---
show_banner() {
    clear
    echo -e "${CYAN} ==========================================================${NC}"
    echo -e "${WHITE}        WireGuard Auto Setup 控制台 v3.1${NC}"
    echo -e "${CYAN} ==========================================================${NC}"
    echo ""
}

print_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_card() {
    local title=$1
    shift
    echo -e "\n${WHITE}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│ ${YELLOW}$title ${NC}"
    echo -e "${WHITE}├────────────────────────────────────────────────────────┤${NC}"
    for line in "$@"; do
        printf "${WHITE}│${NC} %-54s ${WHITE}│${NC}\n" "$line"
    done
    echo -e "${WHITE}└────────────────────────────────────────────────────────┘${NC}\n"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 权限运行此脚本: sudo awg"
        exit 1
    fi
}

ask_interface() {
    echo -e "${YELLOW}? 自定义接口名称 / Custom Interface Name${NC}"
    echo -e "   默认 / Default: ${GREEN}wg0${NC}"
    read -p "   请输入 (e.g. wg0, wg1): " input_iface
    
    if [[ -n "$input_iface" ]]; then
        WG_IFACE="$input_iface"
    fi

    # 保存配置以便后期管理面板读取
    mkdir -p "$CONF_DIR"
    echo "$WG_IFACE" > "$SAVE_FILE"

    WG_CONF="${CONF_DIR}/${WG_IFACE}.conf"
    PRIVATE_KEY_FILE="${CONF_DIR}/${WG_IFACE}_privatekey"
    PUBLIC_KEY_FILE="${CONF_DIR}/${WG_IFACE}_publickey"
    SERVICE_NAME="wg-quick@${WG_IFACE}"
    
    print_info "当前工作接口: ${GREEN}${WG_IFACE}${NC}"
    echo ""
}

install_wg() {
    if ! command -v wg &> /dev/null; then
        print_info "正在安装 WireGuard..."
        if [ -x "$(command -v apt)" ]; then
            apt update -qq && apt install -y wireguard curl > /dev/null
        elif [ -x "$(command -v yum)" ]; then
            yum install -y epel-release > /dev/null
            yum install -y wireguard-tools curl > /dev/null
        else
            print_error "不支持的操作系统，请手动安装 wireguard 和 curl。"
            exit 1
        fi
        print_success "WireGuard 安装完成。"
    else
        print_info "WireGuard 已安装。"
    fi
}

gen_keys() {
    umask 077
    mkdir -p "$CONF_DIR"
    if [ ! -f "$PRIVATE_KEY_FILE" ]; then
        wg genkey | tee "$PRIVATE_KEY_FILE" | wg pubkey > "$PUBLIC_KEY_FILE"
        print_success "密钥生成完毕。"
    fi
    PRIV_KEY=$(cat "$PRIVATE_KEY_FILE")
    PUB_KEY=$(cat "$PUBLIC_KEY_FILE")
}

# ==========================================
# 安装部署逻辑
# ==========================================
logic_A() {
    echo -e "${WHITE}>>> 模式: ${CYAN}A. 本地机器 (内网/发起端)${NC}\n"
    read -p "   B机器(云端) 是否已准备好？(y/n): " b_ready

    install_wg; gen_keys

    read -p "-> 本机内网IP [默认 10.198.1.1]: " local_ip
    local_ip=${local_ip:-10.198.1.1}

    cat > $WG_CONF <<EOF
[Interface]
# Generate by Auto Setup Script
PrivateKey = $PRIV_KEY
Address = $local_ip/24
MTU = 1280
EOF

    if [[ "$b_ready" == "y" || "$b_ready" == "Y" ]]; then
        echo -e "\n${GREEN}>>> 输入来自 B机器 的信息...${NC}"
        read -p "   B's IP:Port : " b_endpoint
        read -p "   B's PUBLIC KEY : " b_pubkey
        
        base_ip=$(echo $local_ip | cut -d'.' -f1-3)
        last_octet=$(echo $local_ip | cut -d'.' -f4)
        auto_b_ip="${base_ip}.$((last_octet + 1))"

        read -p "   B's 内网 IP [默认 $auto_b_ip]: " b_internal_ip
        b_internal_ip=${b_internal_ip:-$auto_b_ip}

        cat >> $WG_CONF <<EOF

[Peer]
PublicKey = $b_pubkey
Endpoint = $b_endpoint
AllowedIPs = $b_internal_ip/32
PersistentKeepalive = 25
EOF
        systemctl enable $SERVICE_NAME >/dev/null 2>&1
        systemctl restart $SERVICE_NAME
        print_success "完成！正在尝试 Ping B机器..."
        ping -c 3 -W 1 "$b_internal_ip"
    else
        print_success "基础配置已生成。"
        print_card "请复制以下信息到 B 机器" \
            "IP_ADDR   : $local_ip" \
            "PUBLICKEY : $PUB_KEY"
    fi
}

logic_B() {
    echo -e "${WHITE}>>> 模式: ${CYAN}B. 其他机器 (云端/公网)${NC}\n"
    read -p "   A机器(本地) 是否已完成第一步？(y/n): " a_done

    if [[ "$a_done" != "y" && "$a_done" != "Y" ]]; then
        print_error "请先在 A 机器完成基础配置！"; exit 0
    fi

    echo -e "\n${GREEN}>>> 输入来自 A机器 的信息...${NC}"
    read -p "   粘贴 A's PUBLIC KEY: " a_pubkey
    read -p "   粘贴 A's 内网 IP (如 10.198.1.1): " a_internal_ip

    if [[ -z "$a_pubkey" || -z "$a_internal_ip" ]]; then print_error "输入为空，退出。"; exit 1; fi

    install_wg; gen_keys
    listen_port=$(shuf -i 8000-9000 -n 1)
    
    base_ip=$(echo $a_internal_ip | cut -d'.' -f1-3)
    last_octet=$(echo $a_internal_ip | cut -d'.' -f4)
    default_my_ip="${base_ip}.$((last_octet + 1))"

    read -p "   本机内网 IP [默认 $default_my_ip]: " my_ip
    my_ip=${my_ip:-$default_my_ip}

    print_info "正在检测本机公网 IPv4..."
    public_ip=$(curl -4 -s --max-time 3 ifconfig.me)
    [[ -z "$public_ip" ]] && public_ip=$(curl -s --max-time 3 ifconfig.me)
    [[ -z "$public_ip" ]] && read -p "   检测失败，请手动输入公网 IP: " public_ip

    cat > $WG_CONF <<EOF
[Interface]
# Generate by Auto Setup Script
PrivateKey = $PRIV_KEY
Address = $my_ip/24
ListenPort = $listen_port
MTU = 1280
PreUp = sysctl -w net.ipv4.ip_forward=1

[Peer]
PublicKey = $a_pubkey
AllowedIPs = $a_internal_ip/32
EOF

    systemctl enable $SERVICE_NAME >/dev/null 2>&1
    systemctl restart $SERVICE_NAME

    print_success "B 机器配置完毕！"
    print_card "请将以下信息复制回 A 机器 (执行步骤 C)" \
        "IP:Port   : ${public_ip}:${listen_port}" \
        "PUBLICKEY : ${PUB_KEY}" \
        "Address   : ${my_ip}"
}

logic_C() {
    echo -e "${WHITE}>>> 模式: ${CYAN}C. 最终握手 (在 A 机器执行)${NC}"
    if [ ! -f "$WG_CONF" ]; then print_error "找不到配置文件 ($WG_CONF)，请先执行步骤 A。"; exit 1; fi

    echo -e "\n${GREEN}>>> 输入来自 B机器 的信息...${NC}"
    read -p "   粘贴 B's IP:Port : " b_endpoint
    read -p "   粘贴 B's PUBLIC KEY : " b_pubkey
    read -p "   粘贴 B's 内网 IP [默认 10.198.1.2]: " b_ip
    b_ip=${b_ip:-10.198.1.2}

    if ! grep -q "$b_pubkey" "$WG_CONF"; then
        cat >> $WG_CONF <<EOF

[Peer]
PublicKey = $b_pubkey
Endpoint = $b_endpoint
AllowedIPs = $b_ip/32
PersistentKeepalive = 25
EOF
    fi

    print_info "重启 WireGuard 接口 ($WG_IFACE)..."
    systemctl restart $SERVICE_NAME
    echo -e "\n${GREEN}=== 隧道建立完毕！正在测试连通性... ===${NC}"
    ping -c 3 -W 1 "$b_ip"
}

# ==========================================
# 管理面板逻辑 (热修改与卸载)
# ==========================================
logic_manage() {
    if [ ! -f "$WG_CONF" ]; then
        print_error "当前接口 ($WG_IFACE) 尚未配置，无法管理！"
        sleep 2; return
    fi

    while true; do
        show_banner
        echo -e "${CYAN}当前管理接口: ${GREEN}$WG_IFACE${NC}"
        local wg_status=$(systemctl is-active $SERVICE_NAME 2>/dev/null)
        echo -e "${CYAN}服务运行状态: $([[ "$wg_status" == "active" ]] && echo -e "${GREEN}运行中${NC}" || echo -e "${RED}已停止${NC}")\n"
        
        echo -e "${YELLOW}1.${NC} 查看当前配置状态"
        echo -e "${YELLOW}2.${NC} 修改对端 Endpoint (云端 IP:端口)"
        echo -e "${YELLOW}3.${NC} 修改对端 PublicKey (公钥)"
        echo -e "${YELLOW}4.${NC} 启动 / 停止 WireGuard 服务"
        echo -e "${RED}88. 彻底卸载此接口的所有配置${NC}"
        echo -e "${WHITE}0.${NC} 返回主菜单"
        echo ""
        read -p "请输入选项: " m_choice

        case "$m_choice" in
            1) 
                clear; wg show $WG_IFACE 2>/dev/null || echo "无法读取状态，请确保服务已启动。"
                echo ""; read -n 1 -s -r -p "按任意键返回..."
                ;;
            2)
                read -p "请输入新的 Endpoint (IP:端口): " new_ep
                if [[ -n "$new_ep" ]]; then
                    sed -i "s/^Endpoint *=.*/Endpoint = $new_ep/" "$WG_CONF"
                    systemctl restart $SERVICE_NAME
                    print_success "Endpoint 已更新并热重载生效！"; sleep 2
                fi
                ;;
            3)
                read -p "请输入新的 PublicKey: " new_pub
                if [[ -n "$new_pub" ]]; then
                    sed -i "s/^PublicKey *=.*/PublicKey = $new_pub/" "$WG_CONF"
                    systemctl restart $SERVICE_NAME
                    print_success "PublicKey 已更新并热重载生效！"; sleep 2
                fi
                ;;
            4)
                if [[ "$wg_status" == "active" ]]; then
                    systemctl stop $SERVICE_NAME; print_warn "服务已停止。"
                else
                    systemctl start $SERVICE_NAME; print_success "服务已启动。"
                fi
                sleep 2
                ;;
            88)
                echo -e "\n${RED}⚠️ 警告: 此操作将不可逆地删除接口 ${WG_IFACE} 的所有配置和密钥！${NC}"
                read -p "确定要继续卸载吗？(y/n): " confirm_un
                if [[ "$confirm_un" == "y" || "$confirm_un" == "Y" ]]; then
                    systemctl stop $SERVICE_NAME >/dev/null 2>&1
                    systemctl disable $SERVICE_NAME >/dev/null 2>&1
                    rm -f "$WG_CONF" "$PRIVATE_KEY_FILE" "$PUBLIC_KEY_FILE"
                    rm -f "$SAVE_FILE"
                    print_success "接口 ${WG_IFACE} 已被彻底卸载清理！"
                    exit 0
                fi
                ;;
            0) break ;;
            *) print_error "无效选项！"; sleep 1 ;;
        esac
    done
}

# --- 主程序路由 ---
check_root

while true; do
    show_banner
    
    # 智能判断：如果已经存在配置文件，则显示进入管理面板的选项
    if [ -f "$WG_CONF" ]; then
        echo -e "${GREEN}[发现已有配置]${NC} 当前接口: ${WG_IFACE}\n"
        echo -e "${YELLOW}0.${NC} 进入管理控制台 (修改配置 / 卸载)"
        echo -e "-----------------------------------"
    fi

    echo -e ">>> 全新安装 / 组网部署:"
    echo -e "${CYAN}1.${NC} A. 本地机器 (内网)"
    echo -e "${CYAN}2.${NC} B. 其他机器 (云端)"
    echo -e "${CYAN}3.${NC} C. 完成 A/B 后的最后一步 (最终握手)"
    echo -e "${WHITE}9.${NC} 切换/创建 其他网卡名称 (当前: $WG_IFACE)"
    echo -e "${WHITE}q.${NC} 退出脚本"
    echo ""
    read -p "请选择操作 [0-9, q]: " choice

    case "$choice" in
        0) 
            if [ -f "$WG_CONF" ]; then logic_manage; else print_error "没有找到配置文件！"; sleep 2; fi
            ;;
        1|a|A) ask_interface; logic_A; exit 0 ;;
        2|b|B) ask_interface; logic_B; exit 0 ;;
        3|c|C) logic_C; exit 0 ;;
        9) ask_interface ;;
        q|Q) echo "退出。"; exit 0 ;;
        *) print_error "无效选项！"; sleep 1 ;;
    esac
done
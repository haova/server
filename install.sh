#!/usr/bin/env bash

set -Eeuo pipefail

log() {
    echo "[INFO] $*"
}

error() {
    echo "[ERROR] $*" >&2
}

require_root() {
    if (( EUID != 0 )); then
        error "Root privileges are required, run with sudo"
        exit 1
    fi
}

require_supported_ubuntu() {
    if [[ ! -r /etc/os-release ]]; then
        error "Ubuntu Server 24.04 or 26.04 is required"
        exit 1
    fi

    . /etc/os-release
    if [[ ${ID:-} != "ubuntu" || ( ${VERSION_ID:-} != "24.04" && ${VERSION_ID:-} != "26.04" ) ]]; then
        error "Ubuntu Server 24.04 or 26.04 is required"
        exit 1
    fi
}

setup_system() {
    local pcre_dev=libpcre3-dev
    if [[ $(. /etc/os-release && echo "$VERSION_ID") != "24.04" ]]; then
        pcre_dev=libpcre2-dev
    fi

    apt-get update
    apt-get install -y ca-certificates curl $pcre_dev libssl-dev perl make build-essential wget gnupg lsb-release
}

install_docker() {
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_web_server() {
    if [[ $(. /etc/os-release && echo "$VERSION_ID") == "24.04" ]]; then
        wget -O - https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/openresty.gpg] https://openresty.org/package/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/openresty.list
        apt-get update
        apt-get -y install openresty
    else
        apt-get install -y nginx
        systemctl enable --now nginx
    fi
}

config_web_server() {
    :
}

setup_basic_firewall() {
    ufw --force reset

    ufw default deny incoming
    ufw default allow outgoing

    ufw limit 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp

    ufw --force enable
}

setup_cloudflare_firewall() {
    CF_IPV4_URL="https://www.cloudflare.com/ips-v4"
    CF_IPV6_URL="https://www.cloudflare.com/ips-v6"
    CF_IPV4=$(curl -fsSL "$CF_IPV4_URL")
    CF_IPV6=$(curl -fsSL "$CF_IPV6_URL")

    ufw --force reset

    ufw default deny incoming
    ufw default allow outgoing

    ufw limit 22/tcp

    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue

        ufw allow from "$ip" to any port 80 proto tcp
        ufw allow from "$ip" to any port 443 proto tcp
    done <<< "$CF_IPV4"

    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue

        ufw allow from "$ip" to any port 80 proto tcp
        ufw allow from "$ip" to any port 443 proto tcp
    done <<< "$CF_IPV6"

    ufw --force enable
}

select_components() {
    SELECTED=" docker website cloudflare_firewall "

    if [[ ! -r /dev/tty ]]; then
        return
    fi

    apt-get install -y whiptail

    local choices
    choices=$(whiptail --title "Install" --separate-output --checklist \
        "Select components to install (space to toggle)" 16 64 4 \
        docker "Docker" ON \
        website "Web server (OpenResty / nginx)" ON \
        basic_firewall "Basic firewall (ufw: 22, 80, 443)" OFF \
        cloudflare_firewall "Cloudflare firewall (ufw: 80/443 only from Cloudflare IPs)" ON \
        3>&1 1>&2 2>&3 </dev/tty) || { error "Cancelled"; exit 1; }

    SELECTED=" $(echo $choices) "
}

is_selected() {
    [[ $SELECTED == *" $1 "* ]]
}

require_root
require_supported_ubuntu

setup_system
select_components

if is_selected docker; then
    install_docker
fi
if is_selected website; then
    install_web_server
    config_web_server
fi
if is_selected cloudflare_firewall; then
    if is_selected basic_firewall; then
        log "Both firewalls selected, using Cloudflare firewall"
    fi
    setup_cloudflare_firewall
elif is_selected basic_firewall; then
    setup_basic_firewall
fi

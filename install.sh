#!/usr/bin/env bash

set -Eeuo pipefail

require_root() {
    if (( EUID != 0 )); then
        echo "sudo is required"
        exit 1
    fi
}

require_supported_ubuntu() {
    if [[ ! -r /etc/os-release ]]; then
        echo "Ubuntu Server 24.04 or 26.04 is required"
        exit 1
    fi

    . /etc/os-release
    if [[ ${ID:-} != "ubuntu" || ( ${VERSION_ID:-} != "24.04" && ${VERSION_ID:-} != "26.04" ) ]]; then
        echo "Ubuntu Server 24.04 or 26.04 is required"
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

install_openresty() {
    wget -O - https://openresty.org/package/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/openresty.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/openresty.gpg] https://openresty.org/package/ubuntu $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/openresty.list > /dev/null
    apt-get update
    apt-get -y install openresty
}

config_openresty() {
    :
}

setup_firewall() {
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

require_root
require_supported_ubuntu

setup_system
install_docker
install_openresty
config_openresty
setup_firewall

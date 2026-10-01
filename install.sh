#!/usr/bin/env bash

set -Eeuo pipefail

require_root() {
    if (( EUID != 0 )); then
        echo "sudo is required"
        exit 1
    fi
}

setup_system() {
    apt-get update
}

require_root

setup_system

echo "install docker"

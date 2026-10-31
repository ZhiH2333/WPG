#!/bin/bash
cd "$(dirname "$0")"
./open_two_clients.sh
echo ""
read -r -p "按回车关闭此窗口…"

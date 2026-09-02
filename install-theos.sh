#!/bin/bash
# 在 WSL Ubuntu 终端里运行此脚本
# 使用方法: wsl
#          cd /mnt/c/Users/Weeeiiii/led
#          bash install-theos.sh

set -e

echo "=========================================="
echo "  安装 Theos (需要 sudo 密码)"
echo "=========================================="

# 安装依赖
echo "正在安装依赖包..."
sudo apt-get update
sudo apt-get install -y git curl build-essential fakeroot rsync perl libarchive-zip-perl

# 安装 Theos
if [ ! -d "$HOME/theos" ]; then
    echo "正在克隆 Theos..."
    git clone --recursive https://github.com/theos/theos.git $HOME/theos
else
    echo "Theos 已存在"
fi

# 下载 iOS SDK
echo "正在下载 iOS SDK..."
cd $HOME/theos/sdks
if [ ! -d "iPhoneOS16.5.sdk" ]; then
    curl -LO https://github.com/theos/sdks/archive/master.zip
    unzip -q master.zip
    mv sdks-master/*.sdk .
    rm -rf sdks-master master.zip
fi

echo ""
echo "✅ Theos 安装完成！"
echo ""
echo "现在运行编译脚本:"
echo "  bash compile.sh"

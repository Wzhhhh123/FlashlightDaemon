#!/bin/bash
# 自动安装和编译（带密码）

set -e

echo "=========================================="
echo "  自动安装 Theos + 编译"
echo "=========================================="

# 安装依赖
echo "[1/4] 安装依赖..."
echo "8008" | sudo -S apt-get update -qq
echo "8008" | sudo -S apt-get install -y -qq git curl build-essential fakeroot rsync perl libarchive-zip-perl

# 安装 Theos
if [ ! -d "$HOME/theos" ]; then
    echo "[2/4] 克隆 Theos..."
    git clone --recursive https://github.com/theos/theos.git $HOME/theos
else
    echo "[2/4] Theos 已存在"
fi

# 下载 iOS SDK
echo "[3/4] 下载 iOS SDK..."
cd $HOME/theos/sdks
if [ ! -d "iPhoneOS16.5.sdk" ]; then
    curl -LO https://github.com/theos/sdks/archive/master.zip
    unzip -q master.zip
    mv sdks-master/*.sdk .
    rm -rf sdks-master master.zip
fi

# 编译
echo "[4/4] 编译项目..."
export THEOS=$HOME/theos
export PATH="$THEOS/bin:$PATH"
cd /mnt/c/Users/Weeeiiii/led
make clean 2>/dev/null || true
make package FINALPACKAGE=1

echo ""
echo "=========================================="
echo "✅ 编译完成！"
echo "=========================================="
ls -lh packages/*.deb
echo ""

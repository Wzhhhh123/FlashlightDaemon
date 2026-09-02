#!/bin/bash
# Theos 一键安装 + 编译脚本

set -e

echo "=========================================="
echo "  FlashlightDaemon - WSL 编译脚本"
echo "=========================================="
echo ""

# 1. 安装依赖
echo "[1/5] 安装系统依赖..."
sudo apt-get update -qq
sudo apt-get install -y -qq git curl build-essential fakeroot rsync perl libarchive-zip-perl

# 2. 安装 Theos
if [ ! -d "$HOME/theos" ]; then
    echo "[2/5] 克隆 Theos..."
    git clone --recursive https://github.com/theos/theos.git $HOME/theos
else
    echo "[2/5] Theos 已存在，跳过"
fi

export THEOS=$HOME/theos
export PATH="$THEOS/bin:$PATH"

# 3. 下载 iOS SDK
if [ ! -d "$THEOS/sdks/iPhoneOS16.5.sdk" ]; then
    echo "[3/5] 下载 iOS SDK..."
    cd $THEOS/sdks
    curl -LO https://github.com/theos/sdks/archive/master.zip
    unzip -q master.zip
    mv sdks-master/*.sdk .
    rm -rf sdks-master master.zip
else
    echo "[3/5] iOS SDK 已存在，跳过"
fi

# 4. 编译项目
echo "[4/5] 开始编译..."
cd /mnt/c/Users/Weeeiiii/led
make clean 2>/dev/null || true
make package FINALPACKAGE=1

# 5. 完成
echo "[5/5] 编译完成！"
echo ""
echo "=========================================="
echo "✅ 成功生成安装包："
ls -lh packages/*.deb
echo "=========================================="
echo ""
echo "安装包位置: $(pwd)/packages/"
echo ""
echo "下一步："
echo "1. 传到 iPhone: scp packages/*.deb root@你的iPhone的IP:/var/root/"
echo "2. SSH 连接: ssh root@你的iPhone的IP"
echo "3. 安装: dpkg -i /var/root/*.deb"
echo "4. 查看日志: cat /var/log/flashlightd.log"
echo ""

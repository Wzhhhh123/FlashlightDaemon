#!/bin/bash
# 编译项目 (在安装 Theos 后运行)

set -e

export THEOS=$HOME/theos
export PATH="$THEOS/bin:$PATH"

echo "=========================================="
echo "  开始编译 FlashlightDaemon"
echo "=========================================="

cd /mnt/c/Users/Weeeiiii/led

echo "清理旧文件..."
make clean 2>/dev/null || true

echo "编译中..."
make package FINALPACKAGE=1

echo ""
echo "=========================================="
echo "✅ 编译成功！"
echo "=========================================="
echo ""
ls -lh packages/*.deb
echo ""
echo "安装包: $(pwd)/packages/"
echo ""
echo "传到 iPhone:"
echo "  scp packages/*.deb root@你的iPhone的IP:/var/root/"
echo ""

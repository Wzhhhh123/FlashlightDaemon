#!/bin/bash
# 一键推送到 GitHub 并触发自动编译

echo "正在推送到 GitHub..."

# 添加远程仓库（请将 YOUR_USERNAME 和 YOUR_REPO 替换成你的实际仓库信息）
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git

# 推送代码
git branch -M main
git push -u origin main

echo ""
echo "✅ 推送完成！"
echo ""
echo "接下来："
echo "1. 访问 https://github.com/YOUR_USERNAME/YOUR_REPO/actions"
echo "2. 等待编译完成（约2-3分钟，绿色勾表示成功）"
echo "3. 点击工作流 → 下载 'flashlight-daemon' artifact"
echo "4. 解压得到 .deb 文件"
echo "5. 传到 iPhone 安装"

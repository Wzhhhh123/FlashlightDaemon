# 📦 WSL 编译指南

## 快速开始（2步）

### 1️⃣ 打开 WSL 终端

在 Windows 开始菜单搜索 **Ubuntu** 并打开，或者在当前目录按住 Shift 右键 → "在此处打开 Linux shell"

### 2️⃣ 运行以下命令

```bash
# 进入项目目录
cd /mnt/c/Users/Weeeiiii/led

# 第一次需要安装 Theos（需要输入你的 Ubuntu 密码）
bash install-theos.sh

# 编译项目
bash compile.sh
```

## ✅ 编译完成后

安装包位置：`packages/com.flashlight.daemon_1.0.0_iphoneos-arm.deb`

### 传到 iPhone 并安装

```bash
# 方法1: 用 scp 传输（需要先 SSH 到 iPhone）
scp packages/*.deb root@你的iPhone的IP:/var/root/

# 方法2: 在 Windows 资源管理器里直接找到
# C:\Users\Weeeiiii\led\packages\
# 然后用隔空投送/iCloud 传到 iPhone
```

### 在 iPhone 上安装

```bash
# SSH 连接 iPhone
ssh root@你的iPhone的IP

# 安装
dpkg -i /var/root/com.flashlight.daemon_*.deb

# 查看日志（会显示访问地址）
cat /var/log/flashlightd.log
```

## 🔄 修改代码后重新编译

```bash
cd /mnt/c/Users/Weeeiiii/led
bash compile.sh
```

---

**提示**：如果 `install-theos.sh` 要求输入密码，输入你 Ubuntu 的用户密码即可（不是 Windows 密码）

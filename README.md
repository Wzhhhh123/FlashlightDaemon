# FlashlightDaemon

**远程网页控制 iPhone 手电筒** - 越狱守护进程版

通过局域网 WiFi，用任何设备的浏览器远程控制 iPhone 的手电筒（开关、亮度调节）。

---

## ✨ 特性

- 🌐 **网页控制** - 任何设备（iPhone、安卓、电脑）用浏览器打开即可控制
- 🎚️ **亮度调节** - 实时滑块调节 1%-100% 亮度
- 🚀 **自动启动** - 守护进程，开机自启，后台常驻
- ⚡ **双 API 支持** - 优先使用私有 `AVFlashlight` API，兼容公开 `AVCaptureDevice` API
- 📱 **响应式界面** - 适配手机和电脑屏幕
- 🔒 **局域网** - 仅同一 WiFi 内可访问，安全可控

---

## 📋 要求

- **越狱 iPhone/iPad** (iOS 10+)
  - 支持 rootless (如 Dopamine, palera1n) 和 rootful 越狱
  - 巨魔（TrollStore）理论上也能装，但守护进程可能需手动启动
- **设备必须有手电筒** (大部分 iPhone/部分 iPad)

---

## 📦 安装

### 方法 1: 从 Release 下载 (推荐)

1. 进入 [Releases](../../releases) 页面
2. 下载最新的 `com.flashlight.daemon_xxx_iphoneos-arm.deb`
3. 传到 iPhone，用包管理器安装（Sileo、Zebra、Installer）或命令行：
   ```bash
   dpkg -i com.flashlight.daemon_*.deb
   ```

### 方法 2: GitHub Actions 云端编译

1. Fork 这个仓库
2. 进入你的仓库 → **Actions** → 点击 **Build deb package** → **Run workflow**
3. 等待编译完成（~2 分钟）
4. 下载 Artifacts 中的 `flashlight-daemon` 压缩包
5. 解压得到 .deb，传到 iPhone 安装

---

## 🚀 使用

### 1. 安装后会自动启动

守护进程会在后台运行，开机自启。查看日志确认启动：

```bash
cat /var/log/flashlightd.log
```

应该看到类似：
```
========================================
[FlashlightDaemon] Server started on port 8080
[FlashlightDaemon] Open in browser: http://192.168.x.x:8080
========================================
```

### 2. 查看 iPhone 的局域网 IP

在 **设置 → Wi-Fi → 当前 WiFi 的 (i) 图标** 中查看 IP 地址（如 `192.168.1.100`）

### 3. 用其他设备访问

**同一 WiFi 下**，用任何设备打开浏览器，访问：

```
http://你的iPhone的IP:8080
```

例如：`http://192.168.1.100:8080`

会看到一个漂亮的控制页面，可以：
- 点击大按钮开关手电筒
- 拖动滑块调节亮度
- 实时查看状态

---

## 🔧 API 接口

守护进程提供 RESTful API，方便集成到其他程序：

| 接口 | 方法 | 参数 | 说明 |
|------|------|------|------|
| `/` | GET | - | 网页控制界面 |
| `/status` | GET | - | 获取状态 `{"isOn":bool,"level":float,"api":"AVFlashlight"}` |
| `/on` | POST | `{"level":0.5}` | 开启（level 可选，0.0-1.0，默认 1.0）|
| `/off` | POST | - | 关闭 |
| `/toggle` | POST | `{"level":0.8}` | 切换开关（level 可选）|
| `/level` | POST | `{"level":0.3}` | 调节亮度（仅在开启时有效）|

**示例（用 curl）：**

```bash
# 开启手电筒（最大亮度）
curl -X POST http://192.168.1.100:8080/on -d '{"level":1.0}' -H "Content-Type: application/json"

# 调到 50% 亮度
curl -X POST http://192.168.1.100:8080/level -d '{"level":0.5}' -H "Content-Type: application/json"

# 关闭
curl -X POST http://192.168.1.100:8080/off

# 查看状态
curl http://192.168.1.100:8080/status
```

---

## 🛠️ 手动控制守护进程

```bash
# 停止
launchctl unload /Library/LaunchDaemons/com.flashlight.daemon.plist

# 启动
launchctl load /Library/LaunchDaemons/com.flashlight.daemon.plist

# 查看状态
launchctl list | grep flashlight

# 查看日志
tail -f /var/log/flashlightd.log
```

---

## 🔍 故障排查

### 1. 访问不了网页

- ✅ 确认 iPhone 和控制设备在**同一个 WiFi**
- ✅ 确认守护进程在运行：`launchctl list | grep flashlight`
- ✅ 检查日志：`cat /var/log/flashlightd.log`
- ✅ 确认端口 8080 没被占用
- ✅ 关闭 VPN / 代理

### 2. 手电筒无法打开

- ✅ 确认设备有手电筒（部分 iPad 没有）
- ✅ 手动测试：从控制中心能否打开手电筒
- ✅ 检查日志中是否有 `ERROR`
- ✅ 尝试重新安装

### 3. 修改端口

编辑 `/Library/LaunchDaemons/com.flashlight.daemon.plist`，把 `8080` 改成其他端口，然后重新加载：

```bash
launchctl unload /Library/LaunchDaemons/com.flashlight.daemon.plist
launchctl load /Library/LaunchDaemons/com.flashlight.daemon.plist
```

---

## 🔐 安全提示

- ⚠️ 此服务**仅监听局域网**，同一 WiFi 下所有人都能访问
- ⚠️ 如果需要认证保护，建议自行修改代码添加密码验证
- ⚠️ **不建议**通过端口转发暴露到公网（安全风险）

---

## 🗑️ 卸载

```bash
# 停止服务
launchctl unload /Library/LaunchDaeemon/com.flashlight.daemon.plist

# 卸载包
dpkg -r com.flashlight.daemon

# 或用包管理器（Sileo/Zebra）直接卸载
```

---

## 🛠️ 开发 & 编译

### 本地编译（需要 macOS 或 Linux 装 Theos）

```bash
# 安装 Theos (如果没装)
# 参考: https://theos.dev/docs/installation

# 克隆仓库
git clone <your-repo>
cd led

# 编译
make package

# 安装到设备
make do THEOS_DEVICE_IP=你的iPhone的IP THEOS_DEVICE_PORT=22
```

### GitHub Actions 自动编译

- 每次 push 到 main/master 会自动编译
- 打 tag 会自动创建 Release 并上传 deb

---

## 📄 许可证

MIT License - 自由使用、修改、分发

---

## 🙏 致谢

- [Theos](https://theos.dev/) - iOS 越狱开发框架
- [TrollLEDs](https://github.com/PoomSmart/TrollLEDs) - 手电筒控制思路参考

---

## 📮 反馈

有问题或建议请提 [Issue](../../issues)

**Enjoy! 🎉**

# TOTP Backup · 自托管 TOTP 验证码备份

![License](https://img.shields.io/badge/license-MIT-brightgreen)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84)
![Server](https://img.shields.io/badge/server-Go%20%2B%20SQLite-00ADD8)
![Client](https://img.shields.io/badge/client-Flutter-02569B)

> 自托管 TOTP 双因素验证码备份方案：**Flutter Android 客户端 + Go 自建服务端**。
>
> 解决 Microsoft / Google Authenticator **不备份自建服务 TOTP 密钥**的问题——扫码添加后自动加密备份到自己的服务器，换手机后一键恢复。

## ✨ 特性

- **扫码 / 手动添加** TOTP 账户（otpauth:// URI，支持 SHA1 / SHA256 / SHA512、6/8 位、30/60 秒周期）
- **动态验证码 + 倒计时圆环**，点击卡片即复制
- **端到端加密**：PBKDF2（210000 次）+ AES-256-GCM，本地与服务端**只存密文**
- **自动备份**：增 / 改 / 删自动同步到自建服务端，失败自动排队重试
- **换机恢复**：新手机输入同一主口令，从服务端一键恢复全部账户
- **本地锁**：主口令（仅内存，进程退出即清除）或指纹解锁（Android Keystore 生物识别保护）
- **导入 / 导出**：otpauth 文本剪贴板互通，兼容 Google / Microsoft Authenticator
- 单用户模式：固定 API Key 鉴权，无账号系统，适合个人自用
- 简体中文界面，明暗主题跟随系统

## 🏗 架构

```
┌─────────────────┐   HTTPS + X-API-Key   ┌──────────────────┐
│ Flutter App      │ ─────────────────────▶ │ Go (Gin) 服务端   │
│ (Android)        │                        │ SQLite (WAL)      │
│ 本地 SQLite       │                        │ Docker Compose     │
│ + Keystore 指纹   │                        │ 只存密文            │
└─────────────────┘                        └──────────────────┘
```

| 组件 | 技术栈 |
| --- | --- |
| 客户端 | Flutter 3.47 / Dart 3.13（`otp`、`cryptography`、`mobile_scanner`、`sqflite`、`dio`、`flutter_secure_storage` 等） |
| 服务端 | Go 1.22+ / Gin / modernc.org/sqlite（纯 Go 驱动，`CGO_ENABLED=0`） |
| 存储 | SQLite（WAL 模式，数据卷持久化） |
| 部署 | Docker Compose |

**安全模型**：主口令只存在于客户端内存；服务端即使被攻破，也只能拿到无法解密的密文。

## 📁 目录结构

```
totp-backup/
├── app/                     # Flutter 客户端
│   └── lib/
│       ├── core/            # 主题、加密服务（PBKDF2 + AES-256-GCM）
│       ├── data/            # 模型、本地仓储（sqflite / secure storage）、API 客户端
│       ├── services/        # TOTP 计算、本地锁、同步队列、账户缓存、导入导出
│       └── ui/              # 页面与组件
├── server/                  # Go 服务端
│   ├── main.go
│   ├── internal/            # config / db / handler
│   ├── Dockerfile
│   └── docker-compose.yml
├── docs/superpowers/        # 设计文档与实现计划
├── LICENSE                  # MIT 许可证
└── README.md
```

## 🚀 快速开始

### 1. 部署服务端

服务端通过环境变量配置（两种部署方式通用）：

| 变量 | 必填 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `API_KEY` | ✅ | - | 客户端鉴权密钥（请求头 `X-API-Key`），务必使用 ≥32 字符强随机串 |
| `PORT` | 否 | `8080` | 监听端口 |
| `DB_PATH` | 否 | `./data/totp.db` | SQLite 数据文件路径 |

健康检查：`GET /api/health`。

#### 方式一：直接运行二进制（推荐，无需 Docker）

**前置条件**：Go 1.22+。

Linux x64 服务器：

```bash
cd server
# 静态编译（CGO_ENABLED=0，产物可直接拷到服务器运行）
CGO_ENABLED=0 GOOS=linux go build -o totp-server .
# 运行（API_KEY 必填，否则程序拒绝启动）
API_KEY="$(openssl rand -hex 32)" PORT=8080 DB_PATH="./data/totp.db" ./totp-server
```

Windows 本地开发调试：

```powershell
cd server
go build -o totp-server.exe .
$env:API_KEY="your-long-random-key"; $env:PORT="8080"; .\totp-server.exe
```

> ⚠️ **务必修改 `API_KEY`**：替换为至少 32 字符的强随机串（例如 `openssl rand -hex 32` 的输出），App 设置页需填写**同一个值**。

生产环境建议用 systemd 或 Docker 托管进程，避免依赖 SSH 会话（systemd 示例）：

```ini
# /etc/systemd/system/totp-server.service
[Unit]
Description=TOTP Backup Server
After=network.target

[Service]
Environment=API_KEY=your-long-random-key
Environment=PORT=8080
Environment=DB_PATH=/srv/totp/data/totp.db
ExecStart=/srv/totp/totp-server
Restart=always

[Install]
WantedBy=multi-user.target
```

#### 方式二：Docker Compose 部署

**前置条件**：Docker 与 Docker Compose。

编写 `docker-compose.yml`（内容如下）：

```yaml
services:
  totp-server:
    image: baozhuo520/totp-backup-server
    container_name: totp-backup-server
    ports:
      - "8080:8080"
    environment:
      API_KEY: "please-change-me-to-a-long-random-string"
      PORT: "8080"
      DB_PATH: "/totp.db"
    volumes:
      - ./data/totp.db:/totp.db          # SQLite 数据持久化（备份数据不随容器销毁）
    restart: unless-stopped
```

构建并启动：

```bash
docker build -t baozhuo520/totp-backup-server .
docker compose up -d
```

> ⚠️ **务必修改 `API_KEY`**：将 `environment` 中的
> `please-change-me-to-a-long-random-string` 替换为至少 32 字符的强随机串
> （例如 `openssl rand -hex 32` 的输出）。App 设置页需填写**同一个值**，
> 客户端通过请求头 `X-API-Key` 携带进行鉴权。

### 2. 构建 / 安装 App

```bash
cd app
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

安装到手机后，首次启动进入「首次设置」：

- **服务端地址**：`http://<你的服务器>:8080`（公网建议通过反向代理配置 HTTPS）
- **API Key**：与 `docker-compose.yml` 中修改后的值一致
- **主口令**：至少 8 位，**务必牢记**——端到端加密下遗忘无法找回（服务端只存密文）

### 3. 使用

| 操作 | 入口 |
| --- | --- |
| 添加账户 | 右下角 `+` → 扫码 / 手动添加 |
| 复制验证码 | 点击卡片 |
| 编辑 / 删除 | 长按卡片 |
| 自动备份 | 添加 / 编辑 / 删除后自动上传，失败每 60 秒重试 |
| 换机恢复 | 新手机设置相同主口令后，菜单 → 从服务端恢复 |
| 导入 / 导出 | 菜单 → 导入 / 导出备份文件（otpauth 文本剪贴板） |
| 修改服务端配置 | 菜单 → 设置 |

> **测试辅助**：没有现成 TOTP 账户时，可用在线工具 [raybyte.cn/tools/totp](https://raybyte.cn/tools/totp/) 生成模拟的 TOTP 密钥与二维码，用于验证扫码添加、验证码显示与备份同步流程。

## 🔒 安全说明

- **主口令不落盘**：仅存于进程内存，App 被杀后需重新输入；启用指纹后主口令存于 Android Keystore（生物识别门闩保护）
- **本地与云端均只存密文**：secret 以 `v1:base64(salt+nonce+cipher+mac)` 格式存储
- API Key 存于 flutter_secure_storage（Keystore 加密）
- 导出的 otpauth 文本含明文密钥，传输请注意渠道安全
- 主口令修改（需全量重加密）不在当前版本范围

## ✅ 验证状态

| 项 | 状态 |
| --- | --- |
| 服务端接口（健康检查 / upsert / delete / list / 鉴权 / 幂等） | 已本地验证 |
| App 静态检查与构建（`flutter analyze`、debug / release APK） | 已通过 |
| 加密服务（往返 / 篡改 / 指纹校验） | 已脚本验证 |
| API 客户端 ↔ 服务端联通 | 本机端到端验证通过 |
| 导入 / 导出解析 | 已脚本验证 |
| 扫码相机 / 指纹 / sqflite 运行时 | 待真机验证（开发环境无 Android 设备） |
| Docker 镜像构建与容器启动 | 待服务器验证（开发环境无 Docker） |

## 💖 支持项目

如果这个项目对你有帮助，欢迎赞赏支持（微信 / 支付宝）：

![微信赞赏](docs/pays/wechat.png)
![支付宝赞赏](docs/pays/alipay.jpg)


## 📄 许可证

[MIT](LICENSE) © [baozhuo92](https://github.com/baozhuo92)

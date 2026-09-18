# TOTP 备份（totp-backup）

自托管 TOTP 双因素验证码备份方案：Flutter Android 客户端 + Go 自建服务端。
解决 Microsoft / Google Authenticator **不备份自建服务 TOTP 密钥**的问题——扫码添加后自动加密备份到自己的服务器，换手机后一键恢复。

## 特性

- 扫码 / 手动添加 TOTP 账户（otpauth:// URI，支持 SHA1/SHA256/SHA512、6/8 位、30/60 秒周期）
- 动态验证码 + 倒计时圆环，点击复制
- **端到端加密**：PBKDF2（210000 次）+ AES-256-GCM，服务端与本地库只存密文
- 自动备份：增/改/删自动同步到自建服务端（失败自动排队重试）
- 换机恢复：从服务端拉取备份，同一主口令即可解密恢复
- 本地锁：主口令（内存）或指纹解锁（Android Keystore 生物识别保护）
- 导入 / 导出：otpauth 文本剪贴板互通（兼容 Google/Microsoft Authenticator 格式）
- 单用户模式：固定 API Key 鉴权，无账号系统
- 简体中文界面，明暗主题跟随系统

## 架构

```
┌─────────────────┐   HTTPS + X-API-Key   ┌──────────────────┐
│ Flutter App      │ ─────────────────────▶ │ Go (Gin) 服务端   │
│ (Android)        │                        │ SQLite (WAL)      │
│ 本地 SQLite       │                        │ Docker Compose     │
│ + Keystore 指纹   │                        │ 只存密文            │
└─────────────────┘                        └──────────────────┘
```

- 客户端：`app/`（Flutter 3.47 / Dart 3.13，minSdk 见 app/android/app/build.gradle.kts）
- 服务端：`server/`（Go 1.22+，gin + modernc.org/sqlite 纯 Go 驱动，CGO_ENABLED=0）
- 安全模型：主口令只在客户端内存；服务端即使被攻破也只能拿到无法解密的密文

## 目录结构

```
totp-backup/
├── app/                     # Flutter 客户端
│   └── lib/
│       ├── core/            # 主题、加密服务（PBKDF2+AES-GCM）
│       ├── data/            # 模型、本地仓储（sqflite/secure storage）、API 客户端
│       ├── services/        # TOTP 计算、本地锁、同步队列、账户缓存、导入导出
│       └── ui/              # 页面与组件（zolysoft UI 规范）
├── server/                  # Go 服务端
│   ├── main.go
│   ├── internal/            # config / db / handler
│   ├── Dockerfile
│   └── docker-compose.yml   # 服务端 + SQLite 卷
├── docs/superpowers/        # 设计文档与实现计划
├── README.md
└── agent.md                 # AI 协作项目进度记录
```

## 快速开始

### 1. 部署服务端（Docker Compose）

```bash
cd server
cp .env.example .env   # 修改 API_KEY 为强随机串，如：openssl rand -hex 32
docker compose up -d
```

服务默认监听 `0.0.0.0:8080`，健康检查 `GET /api/health`。

> **注意**：`docker-compose.yml` 已编写但本仓库开发环境未安装 Docker，镜像构建与容器启动**未在本机验证**，请在你的服务器上按上述命令部署；如有问题欢迎反馈。

### 2. 构建 / 安装 App

```bash
cd app
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

或直接使用 debug 包调试。安装到手机后首次启动进入「首次设置」：

- 服务端地址：`http://<你的服务器>:8080`（内网 http 或反代 https）
- API Key：与 `.env` 中一致
- 主口令：**至少 8 位，务必牢记**——端到端加密下遗忘无法找回（服务端只存密文）

### 3. 使用

| 操作 | 入口 |
| --- | --- |
| 添加账户 | 右下角 `+` → 扫码 / 手动添加 |
| 复制验证码 | 点击卡片 |
| 编辑 / 删除 | 长按卡片 |
| 自动备份 | 添加/编辑/删除后自动上传，失败每 60 秒重试 |
| 换机恢复 | 新手机设置同主口令后，菜单 → 从服务端恢复 |
| 导入 / 导出 | 菜单 → 导入/导出备份文件（otpauth 文本剪贴板） |
| 修改服务端配置 | 菜单 → 设置 |

> **测试辅助**：没有现成 TOTP 账户时，可用在线工具 [raybyte.cn/tools/totp](https://raybyte.cn/tools/totp/) 生成模拟的 TOTP 密钥与二维码，用于验证扫码添加、验证码显示与备份同步流程。

## 安全说明

- **主口令不落盘**：进程被杀后需重新输入；启用指纹后主口令存于 Android Keystore（生物识别门闩保护）
- **本地与云端均只存密文**：secret 以 `v1:base64(salt+nonce+cipher+mac)` 格式存储
- API Key 存于 flutter_secure_storage（Keystore 加密）
- 导出的 otpauth 文本含明文密钥，传输请注意渠道安全
- 主口令修改（需全量重加密）不在当前版本范围

## 验证状态

| 项 | 状态 |
| --- | --- |
| 服务端单元/接口 | 已本地验证（健康检查、upsert/delete/list、鉴权、幂等） |
| App 静态检查 + 构建 | `flutter analyze` 通过，debug/release APK 构建通过 |
| 加密服务（往返/篡改/指纹） | dart 脚本验证通过 |
| API 客户端 ↔ 服务端联通 | 本机端到端验证通过 |
| 导入导出解析 | dart 脚本验证通过 |
| 扫码相机 / 指纹 / sqflite 运行时 | **需真机验证**（开发环境无 Android 设备/模拟器） |
| Docker 部署 | **未验证**（开发环境无 Docker） |

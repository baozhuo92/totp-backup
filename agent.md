# agent.md — TOTP 备份项目协作记录

> 供 AI 跨对话回顾：项目约定、进度、验证状态与待办。每次会话先读此文件。

## 项目目标

自托管 TOTP 备份 App（Flutter Android） + 自建服务端（Go + SQLite + Docker Compose），
解决主流 Authenticator 不备份自建服务 TOTP 密钥的问题。端到端加密，换机可恢复。

## 关键决策（已与用户确认，勿擅自更改）

- 备份方案：**仅自建服务端 + 数据库**（非 S3）
- 鉴权：**单用户**，固定 API Key（Header `X-API-Key`，ConstantTimeCompare）
- 服务端：**Go（gin v1.10.0）+ SQLite（modernc.org/sqlite 纯 Go）**，Docker Compose 部署
- 加密：**端到端**。PBKDF2-HMAC-SHA256 210000 次 → AES-256-GCM，
  格式 `v1:base64(salt16+nonce12+cipher+mac16)`；服务端只存密文
- TOTP 计算：**otp 包**（3.2.0，isGoogle:true + 显式算法 + 毫秒时间戳）
- 本地锁：主口令内存态；指纹解锁用 flutter_secure_storage 11.x
  `AndroidOptions.biometric(enforceBiometrics: true)`（Keystore 生物识别门闩）
- 同步：本地增/改/删 → `t_sync_queue`（payload 存**密文**，不落明文）→ 立即冲刷 + 60 秒周期重试
- 恢复：fetchAll → 全量解密（任一失败整体中止，提示主口令不匹配）→ client_id 幂等覆盖入库
- 导入导出：**otpauth 文本剪贴板**方案（零新依赖；避免文件权限）
- 无版本管理、无测试计划（用户明确排除，覆盖 AGENTS.md 默认）
- 数据库：zolysoft 规范适配 SQLite（`t_` 前缀、snake_case、5 必填字段、snowflake ID 服务端生成、
  保留 t_api_log + t_change_log，单用户去掉 t_login_log）
- UI：zolysoft 规范——极简、简体中文、无 emoji、品牌色 `#0F766E`、明暗主题、44px 触控、四态

## 开发环境要点（沙箱）

- 本机无 Docker、无 Android 设备/模拟器 → Docker 部署与真机运行时**未验证**
- 中国网络：`GOPROXY=https://goproxy.cn,direct`、`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`、
  `PUB_HOSTED_URL=https://pub.flutter-io.cn`
- Gradle：services.gradle.org 不可达 → wrapper 用本地 `file://` gradle-9.7.1-all 包
- git 需 `-c safe.directory=C:/Users/Administrator/Documents/Projects/Flutter/totp-backup`
- 分支 `feat/totp-backup`（master 为 docs）；每次改动即 commit，不 push
- Flutter：`C:\Users\Administrator\Documents\Servers\flutter\bin\flutter.bat`（3.47.2 / Dart 3.13.2）

## 进度（提交记录，倒序）

| 提交 | 内容 |
| --- | --- |
| 2af4d84 | 设置页（服务端地址/API Key 编辑） |
| 10fc6a4 | otpauth 文本导入导出（剪贴板、去重、入队同步） |
| af6bd6a | 从服务端恢复页（全量解密校验 + 幂等入库） |
| 74c8d8b | 同步服务（密文队列 + 失败重试 + 周期冲刷）、编辑删除接入 |
| d06f0fe | 扫码添加 + 手动添加/编辑（URI 解析、Base32 校验、可选校验码） |
| aec3299 | 账户列表主界面（动态码 + 倒计时圆环 + 搜索 + 空状态 + 会话缓存） |
| 38f56a6 | 首次引导设置页 + 本地锁（口令/指纹，Keystore 保护） |
| 97777a9 | dio API 客户端（联通验证通过） |
| 19f9cde | sqflite 本地库 + 账户/设置仓储 |
| f2961ea | 加密服务（PBKDF2+AES-GCM+指纹，修复 verify 前缀 bug） |
| bdbe24b | TOTP 模型/URI 解析/验证码服务 |
| 3919a37 | 项目骨架 + zolysoft 主题 |
| 93e4a7b … a21c019 | 服务端全部 7 任务（见 server 提交） |
| 6c22a3f | 实现计划（server + app） |
| 5db4675 / 0ff13eb | 设计文档 |

## 验证状态

- ✅ 已本地验证：服务端接口（health/upsert/delete/list/鉴权/幂等）、加密往返/篡改/指纹、
  ApiClient↔服务端联通、导入导出解析、`flutter analyze`、debug & release APK 构建
- ⚠️ 待真机验证：扫码相机（mobile_scanner）、指纹（local_auth + biometric storage）、
  sqflite 运行时、完整备份→换机恢复链路
- ⚠️ 待服务器验证：docker-compose 部署（本机无 Docker）

## 已知边界 / 后续可选

- 主口令修改（需全量重加密）未实现
- 服务端未配置时同步自动跳过（队列保留），配置后 60 秒内自动补传
- 恢复策略为服务端为准覆盖本地同名账户
- 备份文件名/通知小部件等未在需求内，未实现

## 常用命令

```bash
# 服务端本地跑（供联调）
cd server && $env:API_KEY='x' $env:PORT='8080' go run -buildvcs=false .

# App 检查 / 构建
cd app && flutter analyze && flutter build apk --debug|--release

# 提交（沙箱环境）
git -c safe.directory=<repo> -c user.name="owner" -c user.email="owner@local" commit -m "..."
```

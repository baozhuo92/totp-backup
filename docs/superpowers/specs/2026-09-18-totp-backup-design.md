# TOTP 自托管备份 App 设计文档

- 日期：2026-09-18
- 状态：已获用户批准（2026-09-18，含"去掉测试计划"调整）
- 作者：DeepSeek Harness（配合主人确认）

## 1. 项目背景与目标

### 背景

微软 / 谷歌 Authenticator 对用户**自行搭建服务的 TOTP 扫码结果不做云备份**。手机重置或更换手机后，自建服务的 TOTP 全部失效，需要重建自建服务器，成本高、风险大。

### 目标

开发一个 Flutter Android 版 TOTP App，满足：

1. 扫码 / 手动添加 TOTP 账户，本地离线可用（核心出码功能）
2. 每次增 / 改 / 删后**自动备份**到自建服务端（Go + SQLite）
3. 换手机后输入同一主口令即可**恢复全部备份**
4. 备份采用**端到端加密**：服务端只存密文，即使服务器被入侵也无法解密

### 明确不做（YAGNI）

- 不做版本管理 / 版本检测（主人明确指示，偏离 AGENTS.md 默认要求）
- 不做测试计划（主人明确指示去掉）
- 不做通知栏小组件
- 不做多用户 / 账号体系（单用户模式）
- 不做多端冲突合并（本地为主，单用户个人场景）
- 不做 iOS / Web 端（仅 Android）

## 2. 技术选型

| 层 | 选型 | 说明 |
|---|---|---|
| App | Flutter（Android） | 主人指定 |
| App 本地存储 | sqflite | TOTP 账户 + 设置 |
| App 扫码 | mobile_scanner | 相机扫码 |
| App 指纹 | local_auth | 本地锁 |
| App 加密 | cryptography（AES-256-GCM + PBKDF2） | 端到端加密 |
| App HTTP | dio | 服务端通信 |
| TOTP 计算 | `otp` 包（pub.dev 稳定版，主版本锁定） | 成熟 RFC 6238 实现，社区审查，纯 Dart 无原生依赖；otpauth URI 解析自行实现（格式固定，约 30 行） |
| 服务端 | Go + Gin | 主人指定 |
| 数据库 | SQLite | 主人指定，单用户够用 |
| 部署 | Docker Compose | 主人指定，数据卷挂载 SQLite 文件 |

## 3. 总体架构

```
┌─────────────────────────────┐        ┌─────────────────────────────┐
│  Flutter Android App        │  HTTPS  │  Go 服务端 (Gin)           │
│  ├ 扫码/手动添加 TOTP        │ ──────► │  ├ REST API (单用户API Key) │
│  ├ 本地加密存储 (sqlite)     │         │  ├ SQLite 数据库            │
│  ├ 端到端加密备份            │         │  └ Docker Compose 部署      │
│  └ 本地锁/导入导出/恢复       │         │                             │
└─────────────────────────────┘        └─────────────────────────────┘
```

### 核心数据流

**备份（自动，增/改/删后触发）：**

```
扫码/手动添加 → 校验 otpauth:// URI → 计算验证码验证
  → 本地入库 → 用"主口令"派生密钥(AES-256-GCM)加密 secret
  → 调服务端 POST /api/accounts/upsert 上传密文 → 服务端 SQLite 入库
```

**恢复（换手机）：**

```
新手机装 App → 设置与服务端相同的"主口令" → 填写服务端地址 + API Key
  → 拉取备份列表 → 用口令解密验证 → 本地批量导入 → 可正常出码
```

### 同步策略

- **本地为主**：App 本地 SQLite 是权威数据源，增/改/删后立即推送服务端
- **恢复**：新手机输入口令后 `GET /api/accounts` 全量拉取 → 解密 → 本地导入
- **冲突**：不处理多端同时编辑（单用户个人场景）

## 4. 端到端加密方案

| 项 | 方案 |
|---|---|
| 密钥派生 | PBKDF2-HMAC-SHA256，迭代 ≥ 210000 次，随机 16 字节盐 |
| 加密算法 | AES-256-GCM（带认证标签，防篡改） |
| 明文结构 | 版本号 + salt + nonce + ciphertext 打包为 Base64，服务端只存此密文 |
| 口令来源 | App 内"主口令"（仅存内存，不落盘）；恢复时必须输入同一口令 |

服务端与数据库**永远接触不到明文 secret**。

## 5. 数据库设计

遵循 zolysoft 数据库设计规范，针对 SQLite 做适配：

| 规范要求 | 适配方案 |
|---|---|
| 表名 `t_` 前缀、字段 snake_case、索引命名 | 完全遵循 |
| 五必须字段（created_by/created_time/update_by/update_time/delete_time） | 完全遵循（单用户模式 created_by/update_by 固定为 0） |
| 主键 BIGINT + 雪花算法 | SQLite 用 INTEGER，雪花 ID 在 Go 应用层生成 |
| 三张日志表 | 保留 t_api_log、t_change_log（应用层写入）；省略 t_login_log（单用户无登录体系） |
| 字段注释 | SQLite DDL 用 `--` 注释完整标注 |

### 5.1 t_account — TOTP 账户备份表（核心）

| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER | 主键，雪花 ID |
| client_id | VARCHAR(64) | App 本地生成的 UUID（客户端幂等键，唯一索引） |
| issuer | VARCHAR(200) | 服务商名称（如 GitHub） |
| account | VARCHAR(200) | 账号名/邮箱 |
| secret_ciphertext | TEXT | 端到端加密后的 secret（AES-256-GCM 密文） |
| algorithm | VARCHAR(20) | 算法：SHA1/SHA256/SHA512 |
| digits | INTEGER | 验证码位数（6 或 8） |
| period | INTEGER | 刷新周期秒数（默认 30） |
| created_by | INTEGER | 创建人 ID（单用户固定 0） |
| created_time | INTEGER | 创建时间（Unix 毫秒时间戳） |
| update_by | INTEGER | 最后修改人 ID（单用户固定 0） |
| update_time | INTEGER | 最后修改时间（Unix 毫秒时间戳） |
| delete_time | INTEGER DEFAULT 0 | 逻辑删除标记（0=未删除） |

- 唯一索引：`uk_t_account_client_id`
- 普通索引：`idx_t_account_delete_time`

### 5.2 t_api_log — 接口请求日志表

| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER | 主键，雪花 ID |
| path | VARCHAR(200) | 请求路径 |
| method | VARCHAR(10) | 请求方法 |
| request_body | TEXT | 请求体（脱敏，secret 为密文不涉及明文） |
| status_code | INTEGER | 响应状态码 |
| cost_ms | INTEGER | 响应耗时（毫秒） |
| client_ip | VARCHAR(64) | 客户端 IP |
| created_time | INTEGER | 请求时间（Unix 毫秒时间戳） |

索引：`idx_t_api_log_created_time`

### 5.3 t_change_log — 变更日志表

| 字段 | 类型 | 说明 |
|---|---|---|
| id | INTEGER | 主键，雪花 ID |
| table_name | VARCHAR(100) | 变更的表名 |
| record_id | VARCHAR(64) | 变更记录 ID |
| operation_type | VARCHAR(10) | INSERT/UPDATE/DELETE |
| old_data | TEXT | 变更前数据（JSON 文本） |
| new_data | TEXT | 变更后数据（JSON 文本） |
| created_time | INTEGER | 变更时间（Unix 毫秒时间戳） |

索引：`idx_t_change_log_created_time`

## 6. 服务端 API 设计

全部走 HTTPS，Header 携带 `X-API-Key` 鉴权（单用户固定密钥，服务端环境变量配置）。

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/accounts/upsert` | 上传/更新单个加密账户（client_id 幂等） |
| DELETE | `/api/accounts/{client_id}` | 删除账户（软删除，同步到服务端） |
| GET | `/api/accounts` | 全量拉取备份（换机恢复用） |
| GET | `/api/health` | 健康检查（Docker 健康探针用） |

请求/响应示例（upsert）：

```json
// POST /api/accounts/upsert
{
  "client_id": "9f8c...uuid",
  "issuer": "GitHub",
  "account": "user@example.com",
  "secret_ciphertext": "v1:base64...",
  "algorithm": "SHA1",
  "digits": 6,
  "period": 30
}
```

## 7. App UI 设计

遵循 zolysoft UI 设计规范：**简约风格**、全局简体中文、**无 emoji 图标**。

- 品牌色：深青色 `#0F766E`（主人确认设计时默认接受）
- 功能色：成功 `#10B981` / 警告 `#F59E0B` / 危险 `#EF4444` / 信息 `#3B82F6` / 中性 `#6B7280`
- 支持暗黑模式（跟随系统）
- 间距 4px 基准，卡片式布局，四种状态（加载/空/错误/正常）全覆盖

### 页面清单

| 页面 | 功能 |
|---|---|
| 首次引导/设置页 | 配置服务端地址 + API Key + 设置主口令（用于加密与恢复） |
| 本地锁页 | 主口令或指纹解锁（local_auth） |
| 账户列表页（主界面） | 卡片列表：issuer/account + 6 位动态码 + 30s 倒计时圆环；支持搜索 |
| 扫码页 | 相机扫码自动识别 otpauth:// URI 并添加（mobile_scanner） |
| 手动添加页 | 表单：issuer、account、secret、算法、位数、周期 |
| 编辑/删除 | 滑出操作或长按菜单；删除同步服务端 |
| 恢复页 | 输入服务端地址 + 口令 → 拉取备份 → 解密 → 批量导入 |
| 导入/导出页 | 导出加密 JSON 文件到本地（可手动备份）；导入解密恢复 |

## 8. 交付物

1. `app/` — Flutter App 源码
2. `server/` — Go 服务端源码 + `Dockerfile` + `docker-compose.yml`（SQLite 数据卷挂载）
3. 数据库初始化 DDL + 种子脚本
4. `README.md` — 部署步骤 + App 使用说明
5. `agent.md` — 关键约定与进度记录（AGENTS.md 要求）

## 9. 安全说明

- TOTP secret 等价于账户密码本身：端到端加密是底线，不做明文存储
- 主口令仅存内存，不落盘；服务端永远接触不到明文
- API Key 通过 HTTPS 传输，服务端环境变量配置，不入库

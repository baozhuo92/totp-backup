package db

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"

	// modernc.org/sqlite 为纯 Go 驱动，无需 CGO，Docker 构建简单
	_ "modernc.org/sqlite"
)

// schemaDDL 建表语句：遵循 zolysoft 数据库设计规范
// 命名：t_ 前缀、snake_case 字段；五必须字段齐全（单用户 created_by/update_by 固定 0）
// 主键 INTEGER（雪花 ID 由应用层生成）；delete_time 软删除；SQLite 注释用 --
const schemaDDL = `
CREATE TABLE IF NOT EXISTS t_account (
    id                 INTEGER PRIMARY KEY,              -- 主键，应用层雪花 ID
    client_id          VARCHAR(64)  NOT NULL,            -- App 本地 UUID，客户端幂等键
    issuer             VARCHAR(200) NOT NULL,            -- 服务商名称
    account            VARCHAR(200) NOT NULL,            -- 账号名/邮箱
    secret_ciphertext  TEXT         NOT NULL,            -- 端到端加密密文（v1:salt:nonce:cipher）
    algorithm          VARCHAR(20)  NOT NULL DEFAULT 'SHA1', -- 算法：SHA1/SHA256/SHA512
    digits             INTEGER      NOT NULL DEFAULT 6,  -- 验证码位数（6/8）
    period             INTEGER      NOT NULL DEFAULT 30, -- 刷新周期秒
    created_by         INTEGER      NOT NULL DEFAULT 0,  -- 创建人（单用户固定 0）
    created_time       INTEGER      NOT NULL,            -- 创建时间（Unix 毫秒）
    update_by          INTEGER      NOT NULL DEFAULT 0,  -- 最后修改人（单用户固定 0）
    update_time        INTEGER      NOT NULL,            -- 最后修改时间（Unix 毫秒）
    delete_time        INTEGER      NOT NULL DEFAULT 0   -- 软删除标记（0=未删除）
);
CREATE UNIQUE INDEX IF NOT EXISTS uk_t_account_client_id ON t_account(client_id);
CREATE INDEX IF NOT EXISTS idx_t_account_delete_time ON t_account(delete_time);

CREATE TABLE IF NOT EXISTS t_api_log (
    id            INTEGER PRIMARY KEY,                   -- 主键，应用层雪花 ID
    path          VARCHAR(200) NOT NULL,                 -- 请求路径
    method        VARCHAR(10)  NOT NULL,                 -- 请求方法
    request_body  TEXT,                                  -- 请求体（secret 为密文，无明文泄露）
    status_code   INTEGER      NOT NULL,                 -- 响应状态码
    cost_ms       INTEGER      NOT NULL,                 -- 响应耗时（毫秒）
    client_ip     VARCHAR(64)  NOT NULL,                 -- 客户端 IP
    created_time  INTEGER      NOT NULL                  -- 请求时间（Unix 毫秒）
);
CREATE INDEX IF NOT EXISTS idx_t_api_log_created_time ON t_api_log(created_time);

CREATE TABLE IF NOT EXISTS t_change_log (
    id             INTEGER PRIMARY KEY,                  -- 主键，应用层雪花 ID
    table_name     VARCHAR(100) NOT NULL,                -- 变更表名
    record_id      VARCHAR(64)  NOT NULL,                -- 变更记录 ID
    operation_type VARCHAR(10)  NOT NULL,                -- INSERT/UPDATE/DELETE
    old_data       TEXT,                                 -- 变更前 JSON
    new_data       TEXT,                                 -- 变更后 JSON
    created_time   INTEGER      NOT NULL                 -- 变更时间（Unix 毫秒）
);
CREATE INDEX IF NOT EXISTS idx_t_change_log_created_time ON t_change_log(created_time);
`

// Open 打开 SQLite 连接并执行建表迁移。
// dsn 形如 file:path?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)，
// 确保父目录存在；WAL 模式提升并发读写性能。
func Open(path string) (*sql.DB, error) {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("创建数据目录失败: %w", err)
	}
	dsn := fmt.Sprintf("file:%s?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)", path)
	conn, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("打开 SQLite 失败: %w", err)
	}
	// 单写者场景，1 个连接即可，避免 SQLite 锁竞争
	conn.SetMaxOpenConns(1)
	if err := conn.Ping(); err != nil {
		conn.Close()
		return nil, fmt.Errorf("连接 SQLite 失败: %w", err)
	}
	if err := migrate(conn); err != nil {
		conn.Close()
		return nil, fmt.Errorf("建表迁移失败: %w", err)
	}
	return conn, nil
}

// migrate 执行建表 DDL（幂等：IF NOT EXISTS）
func migrate(conn *sql.DB) error {
	if _, err := conn.Exec(schemaDDL); err != nil {
		return err
	}
	return nil
}

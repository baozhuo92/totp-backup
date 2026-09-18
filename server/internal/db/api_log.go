package db

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/bwmarrin/snowflake"
)

// WriteApiLog 向 t_api_log 写入一条接口请求记录（由请求日志中间件调用）。
// 请求体为密文数据，无明文 secret 泄露风险；日志写入失败不阻断请求（审计用途，忽略错误）。
func WriteApiLog(ctx context.Context, conn *sql.DB, node *snowflake.Node, path, method, requestBody string, statusCode, costMs int, clientIP string, ts int64) error {
	id := node.Generate().Int64()
	_, err := conn.ExecContext(ctx,
		`INSERT INTO t_api_log (id, path, method, request_body, status_code, cost_ms, client_ip, created_time)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		id, path, method, nullableString(requestBody), statusCode, costMs, clientIP, ts,
	)
	if err != nil {
		return fmt.Errorf("写入接口日志失败: %w", err)
	}
	return nil
}

// nullableString 空字符串转为 nil（SQL NULL）
func nullableString(s string) any {
	if s == "" {
		return nil
	}
	return s
}

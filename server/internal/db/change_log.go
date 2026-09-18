package db

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/bwmarrin/snowflake"
)

// WriteChangeLog 向 t_change_log 写入一条业务变更记录（应用层写入，替代数据库触发器）。
// tableName 变更表名；recordID 记录 ID；opType 取 INSERT/UPDATE/DELETE；
// oldData/newData 为变更前后 JSON（可为 nil）；ts 为 Unix 毫秒时间戳。
// node 为雪花 ID 生成节点（单实例固定 node=1）。
// 注意：change log 写入失败不应阻断主业务（主流程仍应返回成功），由调用方权衡
// ——本函数返回 error，调用方决定是否仅记录日志。
func WriteChangeLog(ctx context.Context, conn *sql.DB, node *snowflake.Node, tableName, recordID, opType string, oldData, newData []byte, ts int64) error {
	id := node.Generate().Int64()
	_, err := conn.ExecContext(ctx,
		`INSERT INTO t_change_log (id, table_name, record_id, operation_type, old_data, new_data, created_time)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		id, tableName, recordID, opType, nullableBytes(oldData), nullableBytes(newData), ts,
	)
	if err != nil {
		return fmt.Errorf("写入变更日志失败: %w", err)
	}
	return nil
}

// nullableBytes 将 nil 转为 nil（SQL NULL），非 nil 保持原值
func nullableBytes(b []byte) any {
	if b == nil {
		return nil
	}
	return b
}

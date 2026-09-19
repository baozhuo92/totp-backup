package db

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"github.com/bwmarrin/snowflake"

	"totp-backup/server/internal/model"
)

// snowflakeNodeID 单实例固定节点号（单用户模式不会多节点并发）
const snowflakeNodeID = 1

// NewSnowflakeNode 创建雪花 ID 生成节点（单实例固定 node=1）
func NewSnowflakeNode() (*snowflake.Node, error) {
	return snowflake.NewNode(snowflakeNodeID)
}

// accountRow 数据库行结构（含内部字段），与 model.Account 分离：
// model 层是 API 契约，本结构用于查询扫描
type accountRow struct {
	ClientID         string
	Issuer           string
	Account          string
	SecretCiphertext string
	Algorithm        string
	Digits           int
	Period           int
	OldDataJSON      []byte // UPDATE 前旧值，用于变更日志
}

// UpsertAccount 按 client_id 幂等写入账户：存在则 UPDATE，不存在则 INSERT。
// 每次写入后记录 t_change_log；变更日志写入失败不阻断主流程（仅打日志由调用方处理）。
func UpsertAccount(ctx context.Context, conn *sql.DB, node *snowflake.Node, a *model.Account) error {
	now := time.Now().UnixMilli()

	var existing accountRow
	err := conn.QueryRowContext(ctx,
		`SELECT issuer, account, secret_ciphertext, algorithm, digits, period
		 FROM t_account WHERE client_id = ? AND delete_time = 0`, a.ClientID,
	).Scan(&existing.Issuer, &existing.Account, &existing.SecretCiphertext,
		&existing.Algorithm, &existing.Digits, &existing.Period)

	switch {
	case err == sql.ErrNoRows:
		// 不存在 → INSERT
		id := node.Generate().Int64()
		if _, err := conn.ExecContext(ctx,
			`INSERT INTO t_account (id, client_id, issuer, account, secret_ciphertext, algorithm, digits, period,
				created_by, created_time, update_by, update_time, delete_time)
			 VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, 0, ?, 0)`,
			id, a.ClientID, a.Issuer, a.Account, a.SecretCiphertext, a.Algorithm, a.Digits, a.Period, now, now,
		); err != nil {
			return fmt.Errorf("插入账户失败: %w", err)
		}
		newJSON, _ := json.Marshal(a)
		// 变更日志失败不阻断：忽略错误（个人备份服务，日志仅审计用途）
		_ = WriteChangeLog(ctx, conn, node, "t_account", a.ClientID, "INSERT", nil, newJSON, now)
		return nil

	case err != nil:
		return fmt.Errorf("查询账户失败: %w", err)

	default:
		// 存在 → UPDATE（幂等：相同数据也走更新路径，保持 update_time 刷新语义）
		old := &model.Account{
			ClientID:         a.ClientID,
			Issuer:           existing.Issuer,
			Account:          existing.Account,
			SecretCiphertext: existing.SecretCiphertext,
			Algorithm:        existing.Algorithm,
			Digits:           existing.Digits,
			Period:           existing.Period,
		}
		if _, err := conn.ExecContext(ctx,
			`UPDATE t_account
			 SET issuer = ?, account = ?, secret_ciphertext = ?, algorithm = ?, digits = ?, period = ?, update_time = ?
			 WHERE client_id = ? AND delete_time = 0`,
			a.Issuer, a.Account, a.SecretCiphertext, a.Algorithm, a.Digits, a.Period, now, a.ClientID,
		); err != nil {
			return fmt.Errorf("更新账户失败: %w", err)
		}
		oldJSON, _ := json.Marshal(old)
		newJSON, _ := json.Marshal(a)
		_ = WriteChangeLog(ctx, conn, node, "t_account", a.ClientID, "UPDATE", oldJSON, newJSON, now)
		return nil
	}
}

// DeleteAccount 软删除账户（delete_time 置为当前时间戳）。
// 返回 (true, nil) 表示删除成功；记录不存在（或已删除）返回 (false, nil)。
func DeleteAccount(ctx context.Context, conn *sql.DB, node *snowflake.Node, clientID string) (bool, error) {
	now := time.Now().UnixMilli()
	res, err := conn.ExecContext(ctx,
		`UPDATE t_account SET delete_time = ?, update_time = ? WHERE client_id = ? AND delete_time = 0`,
		now, now, clientID,
	)
	if err != nil {
		return false, fmt.Errorf("删除账户失败: %w", err)
	}
	affected, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("读取删除结果失败: %w", err)
	}
	if affected == 0 {
		return false, nil
	}
	_ = WriteChangeLog(ctx, conn, node, "t_account", clientID, "DELETE", nil, nil, now)
	return true, nil
}

// ListAccounts 全量拉取未删除账户（换机恢复用）。
// secret_ciphertext 密文原样返回，解密在 App 端完成。
func ListAccounts(ctx context.Context, conn *sql.DB) ([]model.Account, error) {
	rows, err := conn.QueryContext(ctx,
		`SELECT client_id, issuer, account, secret_ciphertext, algorithm, digits, period
		 FROM t_account WHERE delete_time = 0 ORDER BY issuer, account`)
	if err != nil {
		return nil, fmt.Errorf("查询账户列表失败: %w", err)
	}
	defer rows.Close()

	items := make([]model.Account, 0, 16)
	for rows.Next() {
		var a model.Account
		if err := rows.Scan(&a.ClientID, &a.Issuer, &a.Account, &a.SecretCiphertext,
			&a.Algorithm, &a.Digits, &a.Period); err != nil {
			return nil, fmt.Errorf("扫描账户行失败: %w", err)
		}
		items = append(items, a)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("遍历账户行失败: %w", err)
	}
	return items, nil
}

// Stats 备份统计（状态页展示用，仅数量与时间，不含任何账户明细/密文）
type Stats struct {
	AccountCount   int   // 有效（未删除）账户数
	LatestBackupTs int64 // 最近一次写入/更新时间（毫秒时间戳）
}

// GetStats 查询备份统计：有效账户总数与最近更新时间。
// 供公开状态页使用；刻意不返回账户明细，避免泄露 issuer/账号等元数据。
func GetStats(ctx context.Context, conn *sql.DB) (*Stats, error) {
	s := &Stats{}
	err := conn.QueryRowContext(ctx,
		`SELECT COUNT(*), COALESCE(MAX(update_time), 0)
		 FROM t_account WHERE delete_time = 0`,
	).Scan(&s.AccountCount, &s.LatestBackupTs)
	if err != nil {
		return nil, fmt.Errorf("查询备份统计失败: %w", err)
	}
	return s, nil
}

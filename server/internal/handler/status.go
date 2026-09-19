package handler

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"totp-backup/server/internal/db"
)

// StatusHandler 简单状态页（公开，无需 API Key）。
// 仅展示统计信息（账户数量/最近备份时间/运行状态），
// 刻意不返回账户明细与密文——服务端本就只存密文，页面亦不泄露元数据。
type StatusHandler struct {
	conn *sql.DB
}

// NewStatusHandler 创建状态页处理器
func NewStatusHandler(conn *sql.DB) *StatusHandler {
	return &StatusHandler{conn: conn}
}

// Register 挂载状态页路由：GET /（公开访问）
func (h *StatusHandler) Register(r *gin.Engine) {
	r.GET("/", h.page)
}

// page GET /：服务端渲染状态页 HTML
func (h *StatusHandler) page(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	stats, err := db.GetStats(ctx, h.conn)
	if err != nil {
		// 状态页查询失败仍渲染页面（数量显示未知），不向访问者暴露内部错误细节
		stats = &db.Stats{AccountCount: -1}
	}

	latest := "—"
	if stats.LatestBackupTs > 0 {
		latest = time.UnixMilli(stats.LatestBackupTs).Format("2006-01-02 15:04:05")
	}
	countText := fmt.Sprintf("%d", stats.AccountCount)
	if stats.AccountCount < 0 {
		countText = "未知"
	}

	html := fmt.Sprintf(`<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TOTP Backup 服务状态</title>
<style>
  body{font-family:-apple-system,"Segoe UI","Microsoft YaHei",sans-serif;background:#f4f6f8;color:#1f2937;margin:0;padding:0}
  .card{max-width:560px;margin:48px auto;background:#fff;border-radius:12px;padding:32px;box-shadow:0 1px 4px rgba(0,0,0,.08)}
  h1{font-size:20px;color:#0F766E;margin:0 0 4px}
  .sub{color:#6b7280;font-size:13px;margin-bottom:24px}
  table{width:100%%;border-collapse:collapse}
  td{padding:10px 0;border-bottom:1px solid #eef1f4;font-size:14px}
  td:first-child{color:#6b7280}
  td:last-child{text-align:right;font-weight:600}
  .ok{color:#059669}
  .note{margin-top:24px;font-size:12px;color:#9ca3af;line-height:1.6}
</style>
</head>
<body>
<div class="card">
  <h1>TOTP Backup</h1>
  <div class="sub">自托管 TOTP 验证码备份服务 · 状态页</div>
  <table>
    <tr><td>运行状态</td><td class="ok">● 正常</td></tr>
    <tr><td>备份账户数</td><td>%s</td></tr>
    <tr><td>最近备份时间</td><td>%s</td></tr>
  </table>
  <div class="note">备份数据已端到端加密（PBKDF2 + AES-256-GCM），服务端仅保存密文。
  本页只展示统计信息，不包含任何账户明细与验证码；账户数据仅由 App 通过受 API Key 保护的接口访问。</div>
</div>
</body>
</html>`, countText, latest)

	c.Header("Content-Type", "text/html; charset=utf-8")
	c.String(http.StatusOK, html)
}

package handler

import (
	"bytes"
	"crypto/subtle"
	"database/sql"
	"io"
	"net/http"
	"time"

	"github.com/bwmarrin/snowflake"
	"github.com/gin-gonic/gin"

	"totp-backup/server/internal/db"
)

// AuthMiddleware 单用户 API Key 鉴权。
// 固定密钥由环境变量注入；比较用 ConstantTimeCompare 防时序侧信道；
// 缺失或不匹配统一返回 401（不区分原因，避免探测）。
func AuthMiddleware(apiKey string) gin.HandlerFunc {
	return func(c *gin.Context) {
		got := c.GetHeader("X-API-Key")
		if got == "" || subtle.ConstantTimeCompare([]byte(got), []byte(apiKey)) != 1 {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}
		c.Next()
	}
}

// bodyLogWriter 包装 gin.ResponseWriter 以捕获响应状态码（默认 200）
type bodyLogWriter struct {
	gin.ResponseWriter
	status int
}

// WriteHeader 记录状态码后透传
func (w *bodyLogWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

// RequestLogger 请求日志中间件：记录 path/method/body/status/cost/ip 到 t_api_log。
// 注意坑点：Gin 中读 body 后必须复位 c.Request.Body，否则后续 handler 读不到 body；
// 日志写入失败仅忽略（审计用途，不影响业务）。
func RequestLogger(conn *sql.DB, node *snowflake.Node) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()

		// 读取并复位请求体
		var body []byte
		if c.Request.Body != nil {
			body, _ = io.ReadAll(c.Request.Body)
			c.Request.Body = io.NopCloser(bytes.NewReader(body))
		}

		// 替换 writer 捕获状态码
		blw := &bodyLogWriter{ResponseWriter: c.Writer, status: http.StatusOK}
		c.Writer = blw

		c.Next()

		_ = db.WriteApiLog(
			c.Request.Context(), conn, node,
			c.Request.URL.Path, c.Request.Method, string(body),
			blw.status, int(time.Since(start).Milliseconds()),
			c.ClientIP(), time.Now().UnixMilli(),
		)
	}
}

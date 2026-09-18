package handler

import (
	"database/sql"
	"net/http"

	"github.com/bwmarrin/snowflake"
	"github.com/gin-gonic/gin"

	"totp-backup/server/internal/db"
	"totp-backup/server/internal/model"
)

// AccountHandler 账户相关接口处理器，持有 DB 连接与雪花节点
type AccountHandler struct {
	conn *sql.DB
	node *snowflake.Node
}

// NewAccountHandler 创建账户处理器
func NewAccountHandler(conn *sql.DB, node *snowflake.Node) *AccountHandler {
	return &AccountHandler{conn: conn, node: node}
}

// Register 挂载账户路由（调用方负责鉴权中间件）
func (h *AccountHandler) Register(r *gin.RouterGroup) {
	r.POST("/accounts/upsert", h.upsert)
	r.DELETE("/accounts/:client_id", h.delete)
	r.GET("/accounts", h.list)
}

// validAlgorithms 允许的 TOTP 算法白名单
var validAlgorithms = map[string]bool{"SHA1": true, "SHA256": true, "SHA512": true}

// upsert POST /api/accounts/upsert：上传/更新单个加密账户（client_id 幂等）
// 请求体为 App 端端到端加密后的密文，服务端只做存储，不接触明文
func (h *AccountHandler) upsert(c *gin.Context) {
	var a model.Account
	if err := c.ShouldBindJSON(&a); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求体格式错误"})
		return
	}
	// 参数校验：必填字段 + 枚举白名单，防止脏数据入库
	if a.ClientID == "" || a.Issuer == "" || a.Account == "" || a.SecretCiphertext == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "client_id/issuer/account/secret_ciphertext 不能为空"})
		return
	}
	if !validAlgorithms[a.Algorithm] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "algorithm 必须为 SHA1/SHA256/SHA512"})
		return
	}
	if a.Digits != 6 && a.Digits != 8 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "digits 必须为 6 或 8"})
		return
	}
	if a.Period < 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "period 必须大于 0"})
		return
	}

	if err := db.UpsertAccount(c.Request.Context(), h.conn, h.node, &a); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// delete DELETE /api/accounts/:client_id：软删除账户
// 记录不存在返回 404（幂等调用方按此处理）
func (h *AccountHandler) delete(c *gin.Context) {
	clientID := c.Param("client_id")
	if clientID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "client_id 不能为空"})
		return
	}
	ok, err := db.DeleteAccount(c.Request.Context(), h.conn, h.node, clientID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "账户不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// list GET /api/accounts：全量拉取未删除账户（换机恢复用）
// 密文原样返回，解密在 App 端完成
func (h *AccountHandler) list(c *gin.Context) {
	items, err := db.ListAccounts(c.Request.Context(), h.conn)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}
	if items == nil {
		items = []model.Account{} // 空列表返回 [] 而非 null，保证 JSON 契约稳定
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

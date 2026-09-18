package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// HealthHandler 健康检查处理器
type HealthHandler struct{}

// NewHealthHandler 创建健康检查处理器
func NewHealthHandler() *HealthHandler {
	return &HealthHandler{}
}

// Register 挂载健康检查路由（公开，不校验 API Key，供 Docker healthcheck 探测）
func (h *HealthHandler) Register(r *gin.Engine) {
	r.GET("/api/health", h.health)
}

// health GET /api/health：返回固定状态，仅用于存活探测
func (h *HealthHandler) health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

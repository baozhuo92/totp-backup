package main

import (
	"log"

	"github.com/gin-gonic/gin"

	"totp-backup/server/internal/config"
	"totp-backup/server/internal/db"
	"totp-backup/server/internal/handler"
)

func main() {
	// 1. 加载配置（API_KEY 缺失直接退出，保证无鉴权不启动）
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("配置加载失败: %v", err)
	}

	// 2. 初始化雪花节点（单实例 node=1）与数据库连接
	node, err := db.NewSnowflakeNode()
	if err != nil {
		log.Fatalf("初始化雪花节点失败: %v", err)
	}
	conn, err := db.Open(cfg.DBPath)
	if err != nil {
		log.Fatalf("初始化数据库失败: %v", err)
	}
	defer conn.Close()

	// 3. 组装路由：全局请求日志 + 恢复中间件；health 公开，accounts 走 API Key 鉴权
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(handler.RequestLogger(conn, node))

	h := handler.NewHealthHandler()
	h.Register(r)

	api := r.Group("/api", handler.AuthMiddleware(cfg.APIKey))
	ah := handler.NewAccountHandler(conn, node)
	ah.Register(api)

	// 4. 启动 HTTP 服务
	log.Printf("TOTP 备份服务端已启动，监听端口 %s", cfg.Port)
	if err := r.Run(":" + cfg.Port); err != nil {
		log.Fatalf("服务启动失败: %v", err)
	}
}

package main

import (
	"log"

	"totp-backup/server/internal/config"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("配置加载失败: %v", err)
	}
	// 任务 6 在此组装路由并启动 HTTP 服务
	_ = cfg
}

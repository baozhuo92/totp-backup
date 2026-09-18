package config

import (
	"errors"
	"os"
)

// errMissingAPIKey：API_KEY 未配置时返回，阻止无鉴权启动（安全底线）
var errMissingAPIKey = errors.New("API_KEY 未配置")

// Config 服务端配置，全部来自环境变量（.env 由 docker-compose 注入）
type Config struct {
	Port   string // 监听端口，默认 8080
	APIKey string // 单用户 API Key，必填；App 通过 X-API-Key 头携带
	DBPath string // SQLite 文件路径，默认 ./data/totp.db
}

// Load 从环境变量读取配置；API_KEY 缺失时返回 error 阻止启动（安全底线：不允许无鉴权运行）
func Load() (*Config, error) {
	cfg := &Config{
		Port:   getEnv("PORT", "8080"),
		APIKey: os.Getenv("API_KEY"),
		DBPath: getEnv("DB_PATH", "./data/totp.db"),
	}
	if cfg.APIKey == "" {
		return nil, errMissingAPIKey
	}
	return cfg, nil
}

// getEnv 读取环境变量，缺失时返回默认值 def
func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

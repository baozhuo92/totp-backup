# baizelu-api-server 构建脚本
#
# 用法：
#   make build-linux   # Linux x64（amd64）静态编译打包
#   make clean         # 清理构建产物
#
# 注意：
# - 目标产物为纯静态二进制（CGO_ENABLED=0），可直接部署到 Linux x64 服务器；
# - Windows 上执行需 GNU make（Git Bash 自带），或在 Linux/CI 环境使用；
# - 本项目入口为 ./cmd/server（module: baizelu-api-server）。

BINARY := baizelu-api-server
OUTPUT_DIR := build

.PHONY: build-linux clean

# Linux x64 静态编译打包（禁用 CGO，裁剪符号与调试信息减小体积）
build-linux:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o $(OUTPUT_DIR)/$(BINARY)-linux-amd64 ./cmd/server

build-linux-for-windows:
	$env:CGO_ENABLED=0
	$env:GOOS="linux"
	$env:GOARCH="amd64"
	go build -trimpath -ldflags="-s -w" -o app .
# 清理构建产物
clean:
	rm -rf $(OUTPUT_DIR)

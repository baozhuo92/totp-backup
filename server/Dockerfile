## 构建阶段：golang alpine 编译（modernc 纯 Go 驱动，无需 CGO/gcc）
#FROM golang:1.27-alpine AS builder
#WORKDIR /build
#COPY go.mod go.sum ./
#RUN go mod download
#COPY . .
#RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /totp-server .
#
## 运行阶段：精简 alpine，仅含证书与时区数据
#FROM alpine:3.20
#RUN apk add --no-cache ca-certificates tzdata
#WORKDIR /app
#COPY --from=builder /totp-server .
#EXPOSE 8080
#ENTRYPOINT ["/app/totp-server"]


FROM ghcr.nju.edu.cn/distroless/static
COPY ./app /app
EXPOSE 8080
ENTRYPOINT ["/app"]
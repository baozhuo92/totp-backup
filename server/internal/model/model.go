package model

// Account 与 App 的 JSON 契约（服务端 API 请求/响应共用）。
// secret_ciphertext 为端到端加密密文，服务端永不接触明文 secret。
type Account struct {
	ClientID         string `json:"client_id"`
	Issuer           string `json:"issuer"`
	Account          string `json:"account"`
	SecretCiphertext string `json:"secret_ciphertext"`
	Algorithm        string `json:"algorithm"`
	Digits           int    `json:"digits"`
	Period           int    `json:"period"`
}

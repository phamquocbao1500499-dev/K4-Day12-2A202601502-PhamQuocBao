# Thông Tin Deploy — Checkpoint 5

> Service đã deploy thật trên Render.
> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị token vào đây.**

## Thông Tin Học Viên

| Mục | Nội dung |
|-----|----------|
| Họ và tên | Pham Quoc Bao |
| Mã học viên | 2A202601502 |
| Repo | https://github.com/phamquocbao1500499-dev/K4-Day12-2A202601502-PhamQuocBao |

## Service

| Mục | Nội dung |
|-----|----------|
| Public URL | https://day12-chat-1lr6.onrender.com |
| Platform | Render (Blueprint từ `render.yaml`) |
| Ngày deploy | 2026-08-10 |

## Biến Môi Trường Đã Set Trên Cloud

| Biến | Đã set | Ghi chú |
|------|--------|---------|
| `PORT` | ✅ | Render tự gán |
| `API_TOKEN` | ✅ | sinh bằng `secrets.token_urlsafe(32)`, đặt trong dashboard (sync: false) |
| `REDIS_URL` | ✅ | Render tự gắn từ Redis add-on `day12-chat-redis` (thông qua `fromService`) |
| `BUCKET_CAPACITY` | ✅ | 10 |
| `REFILL_PER_MINUTE` | ✅ | 10 |
| `DAILY_BUDGET_USD` | ✅ | 1.0 |
| `LOG_LEVEL` | ✅ | INFO |

## Lệnh Kiểm Tra

```powershell
# 1. Liveness — mong đợi 200 {"status":"ok"}
curl.exe -i https://day12-chat-1lr6.onrender.com/healthz

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl.exe -i https://day12-chat-1lr6.onrender.com/readyz

# 3. Không có token — mong đợi 401 kèm header WWW-Authenticate
curl.exe -i -X POST https://day12-chat-1lr6.onrender.com/chat -H "Content-Type: application/json" -d '{\"message\":\"Hello\"}'

# 4. Có token — mong đợi 200 kèm câu trả lời
$TOKEN = $env:API_TOKEN   # hoặc dán thẳng token vào
'{"message":"Deploy la gi"}' | Set-Content body.json -Encoding utf8
curl.exe -i -X POST https://day12-chat-1lr6.onrender.com/chat -H "Content-Type: application/json; charset=utf-8" -H "Authorization: Bearer $TOKEN" -H "X-Client-Id: sv-test" --data-binary "@body.json"

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for ($i=1; $i -le 15; $i++) {
  (curl.exe -s -o $null -w "%{http_code} " -X POST https://day12-chat-1lr6.onrender.com/chat -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -H "X-Client-Id: sv-test" --data-binary "@body.json")
}; Write-Host ""
```

## Kết Quả Chạy Thật

```
# /healthz
HTTP/1.1 200 OK
Content-Type: application/json
{"status":"ok","service":"day12-chat-service","version":"1.0.0"}

# /readyz
HTTP/1.1 200 OK
{"status":"ready","redis":true}

# /chat (không token)
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer
{"detail":"invalid or missing bearer token"}

# /chat (có token)
HTTP/1.1 200 OK
{"reply":"Ngắn gọn: Render la gi phụ thuộc vào ba yếu tố — cấu hình qua biến môi trường, health check để orchestrator biết trạng thái, và giới hạn tài nguyên.","client_id":"sv-test","turns_before":0,"usd_cost":2.265e-05,"usage":{"prompt":3,"completion":37}}
```

## Ảnh Chụp Màn Hình

Đặt trong `screenshots/`:
- `dashboard.png` — Render dashboard của service `day12-chat`
- `healthz.png` — kết quả gọi `/healthz`
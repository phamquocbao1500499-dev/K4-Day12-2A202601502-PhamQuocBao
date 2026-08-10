# Phiếu Phản Ánh — K4 Ngày 12

> Các câu trả lời dựa trên quan sát thực tế khi chạy code trong lab.

Họ và tên: Pham Quoc Bao
Mã học viên: 2A202601502

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `api_token` không có giá trị mặc định. Một tình huống cụ thể mà "chết sớm" cứu mình:

Deploy lên Render nhưng quên set biến `API_TOKEN` trong dashboard. Vì `Settings` không có giá trị mặc định, container khởi động ngay lập tức ném `ValidationError: api_token Field required`, uvicorn không start được, Render health check fail → Render hiển thị deploy failed trên dashboard trong vòng 30 giây.

Nếu có mặc định `"changeme"`: app vẫn khởi động bình thường, `/healthz` trả 200, bản deploy "có vẻ" thành công. Mình mở `/chat` gọi thử → nhận 401 vì token mặc định khác token thật, mất thêm 10 phút debug mới biết token chưa được set trên cloud. Tệ hơn: nếu mình quên luôn, attacker có thể dò ra `changeme` là token mặc định và gọi API miễn phí trước khi mình kịp phát hiện.

---

### Câu 2 — Log cho máy đọc (CP1)

Dòng log JSON thu được sau khi gọi `/chat` (lệnh `docker compose logs chat`):

```json
{"event": "chat_completed", "severity": "INFO", "ts": "2026-08-10T08:37:03.414344+00:00", "client_id": "sv-log", "prompt_tokens": 2, "completion_tokens": 34, "usd_cost": 2.07e-05}
```

**Hai việc làm được với log này mà `print("đã trả lời xong")` không làm được:**

1. **Lọc/cảnh báo theo mức độ**: trên Render dashboard, mình gõ `severity:ERROR` vào ô filter để gom mọi lỗi trong hàng triệu log request mà không cần đọc từng dòng. `print()` không có khóa `severity`, cloud logging không biết đâu là lỗi đâu là thông tin.

2. **Truy vấn theo trường tùy ý**: mình có thể đếm `sum(usd_cost)` group by `client_id` để biết client nào tiêu nhiều tiền nhất, hoặc đếm số event theo `ts` để biết request/giây theo giờ. `print()` chỉ cho ra chuỗi tự do, máy không parse được thành truy vấn.

---

### Câu 3 — Kích thước image (CP2)

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | ~1.8 GB (theo LAB_GUIDE.md) |
| Multi-stage | **270 MB** (đo bằng `docker images day12-chat:prod`) |

Phần chênh ~1.5 GB là những thứ multi-stage đã loại bỏ:
- Compiler và dev headers (`build-essential`, `gcc`, `libpython-dev`) mà `pip install` cần để build một số wheel nhưng runtime không dùng.
- `pip` cache (`/root/.cache/pip`) sau khi cài xong.
- Bất kỳ thư viện nào chỉ dùng lúc build (ví dụ `setuptools`, `wheel`) mà không nằm trong `requirements.txt` runtime.
- Layer `pip install` được tạo trong stage `builder` rồi bị vứt đi khi stage `runtime` chỉ `COPY --from=builder /install /usr/local` site-packages.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Output build image từ `docker build -t day12-chat:prod .` (lần build thứ hai, sau khi image đã có sẵn):

```
=> CACHED [builder 3/4] COPY requirements.txt .
=> CACHED [builder 4/4] RUN pip install --no-cache-dir --prefix=/insta...
=> CACHED [runtime 4/6] COPY app ./app
=> CACHED [runtime 5/6] COPY utils ./utils
=> CACHED [runtime 6/6] RUN useradd --create-home --uid 10001 appuser
```

Khi sửa 1 ký tự trong `app/main.py`, **chỉ layer `[runtime 4/6] COPY app ./app` phải chạy lại** — tất cả layer phía trước (requirements.txt, pip install, utils, useradd) vẫn `CACHED`. Lý do: Docker cache theo từng layer, key cache là checksum của input layer đó. `COPY app ./app` có input thay đổi → cache miss → chạy lại. Các layer trước có input không đổi → cache hit.

Nếu đặt `COPY . .` lên **trước** `RUN pip install` (lỗi phổ biện): mỗi lần sửa bất kỳ file nào trong repo (kể cả `README.md`, `.env`, file test), `COPY . .` đã đổi checksum → tất cả layer phía dưới (gồm cả `pip install`) phải chạy lại. Build mất thêm 1–2 phút cho thư viện không liên quan.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng UID 0 (root). Chuỗi sự cố:

1. Lỗ hổng trong code Python — ví dụ pickle deserialize dữ liệu user gửi lên (`pickle.loads(payload)`), attacker chèn payload đặc biệt để thực thi code tùy ý trong process Python.
2. Code tùy ý chạy được thực thi trong container với quyền UID 0 (root), vì đó là user mặc định của container.
3. Vì container chạy root trong user-namespace nhưng chia sẻ kernel với host, attacker có thể mount `/host` qua `/proc/1/root`, đọc `/proc/self/mountinfo`, hoặc exploit lỗi kernel để thoát ra ngoài container.
4. Kết quả: attacker có quyền root trên host, đọc được mọi container khác, mọi file, mọi credential.

Lệnh `USER appuser` cắt đứt chuỗi ở bước 2: dù code Python vẫn bị exploit, process chỉ có quyền của `appuser` (UID 10001), không phải root. Attacker vẫn có thể đọc file trong `/app`, ghi vào file user đó sở hữu — nhưng không thể mount `/proc/1/root`, không bind cổng <1024, không cài package. Thiệt hại khu trú trong container.

---

### Câu 6 — Bearer token (CP3)

`WWW-Authenticate: Bearer` là cách HTTP server nói cho client biết "tôi yêu cầu Bearer token, hãy gửi lại kèm `Authorization: Bearer <token>`". Không có header này, client không biết phải thử scheme nào — Basic? Digest? API key? — và 401 vô dụng với họ.

Dùng cùng một thông báo lỗi cho cả 3 trường hợp (thiếu header, sai scheme, sai token) vì lý do bảo mật: nếu server phân biệt "thiếu header" với "sai token", attacker đoán được mình đang sai ở khúc nào và tối ưu cách dò. Ví dụ: thấy "thiếu header" → biết token đang sai scheme, đổi sang `Bearer` rồi tiếp tục. Thấy "sai token" → đã đúng scheme, chỉ cần brute-force token. Cùng message = mỗi lần đoán sai đều nhận cùng phản hồi, không có thông tin phụ.

Việc này không ảnh hưởng người dùng thật: họ đọc tài liệu API, biết phải gửi `Authorization: Bearer <token>`, lần đầu làm đúng là xong. Người dùng thật bị lỗi thì có log/debugger để tự sửa, không cần server chỉ điểm.

---

### Câu 7 — Token bucket (CP3)

Với `capacity=10`, `refill_per_minute=10` (~0.1667 token/giây):

- Ban đầu xô đầy 10 token.
- Im lặng 10 phút = 600 giây × 0.1667 = 100 token nạp thêm. Nhưng vì có `min(capacity, tokens)`, xô vẫn chỉ chứa tối đa 10.
- Bùng liên tiếp: gửi được **10 request**, request thứ 11 → 429.

Nếu bỏ `min(capacity, ...)` trong `available()`:

- Sau 10 phút im lặng, `tokens = 10 + 100 = 110`. Không cap.
- Bùng liên tiếp: gửi được **110 request** trong vài giây, đến khi xô cạn.

Đây là lý do phải cap: rate limit mục đích là giới hạn tốc độ trung bình và burst, không phải cho phép tích lũy vô hạn. Client im lặng cả ngày rồi gửi 14.400 request trong 1 giây thì service sập còn tệ hơn attacker gửi đều — vì spike đó phá cả bucket rate, không chỉ endpoint.

---

### Câu 8 — Ngân sách theo ngày (CP3)

| Cách | Thiệt hại tối đa | Tự hồi phục khi nào |
|------|-----------------|---------------------|
| $30/tháng | Toàn bộ $30 có thể bay trong vài giờ (nếu attacker gọi liên tục từ 2h sáng). Lúc phát hiện (sáng hôm sau) đã mất hết. | Reset đầu tháng — sau đó vẫn có thể mất tiếp $30 nếu attacker tiếp tục. |
| $1/ngày | Tối đa $1 cho mỗi sự cố. Sang ngày mới key Redis `spend:<client>:<YYYY-MM-DD>` đổi, key cũ tự expire sau 3 ngày. | Reset lúc 00:00 UTC — service tự cho phép gọi lại mà không cần ai can thiệp. |

Hạn mức tháng báo động sau khi đã mất phần lớn số tiền. Hạn mức ngày giới hạn thiệt hại tối đa của một sự cố xuống 1/30, sáng hôm sau tự hồi phục. Ngay cả khi attacker cố ý, mỗi ngày chỉ mất $1, chờ fix xong là hết nguy.

---

### Câu 9 — /healthz khác /readyz (CP4)

Nếu gộp 2 endpoint, cho `/healthz` kiểm tra Redis:

1. Redis mất kết nối 30 giây (network blip).
2. Cả 3 container trong cụm gọi `store.ping()` đều fail.
3. Cả 3 container `/healthz` trả 503.
4. Orchestrator (Render, K8s) thấy 3/3 unhealthy → restart toàn bộ cùng lúc.
5. Container mới khởi động nhưng Redis vẫn đang recover → `/healthz` 503 ngay → orchestrator restart lại.
6. Crash loop cho đến khi Redis hoàn toàn phục hồi (có thể 5–10 phút).
7. Khi Redis quay lại, **cả 3 container vừa được restart cùng lúc và đã xử lý xong request cũ** — không có instance nào còn sống để nhận traffic.

Kết quả: sự cố Redis 30 giây → downtime toàn bộ service 5–10 phút.

Phân tách `/healthz` (chỉ báo process sống) và `/readyz` (kiểm tra Redis):
- Redis chết → `/readyz` 503 → load balancer ngừng gửi request mới vào 3 container này (đảm bảo user nhận 503 từ LB thay vì treo request).
- 3 container vẫn `/healthz` 200 → orchestrator không restart.
- Khi Redis phục hồi → `/readyz` 200 → load balancer gửi traffic trở lại. **Zero downtime**.

---

### Câu 10 — Deploy thật (CP5)

**Lỗi**: gọi `curl -i http://localhost:8000/chat -H "Authorization: Bearer $TOKEN" -d '{"message":"Hello"}'` từ PowerShell, response trả `{"detail":[{"type":"json_invalid","loc":["body",1],"msg":"JSON decode error",...}]}` (422 Unprocessable Entity).

**Nguyên nhân**: PowerShell có 2 vấn đề với curl:
1. PowerShell mặc định `curl` được alias sang `Invoke-WebRequest`, không phải curl thật. `Invoke-WebRequest` parse flag `-H` theo cách khác, không nhận JSON body qua `-d` đúng cách.
2. PowerShell parse chuỗi `'`...`'` khác bash: nháy đơn bọc ngoài, nháy kép escape `\"` bên trong bị convert thành `"`, khi đến ký tự Unicode (ví dụ `ì` trong "Là") bị curl interpret thành Punycode (`xn--l-sfa`) — dấu hiệu nhận ra là dòng `curl: (6) Could not resolve host: xn--l-sfa` trong output.

**Cách sửa**: dùng `curl.exe` thay vì `curl`, và tách JSON body ra file rồi dùng `--data-binary "@body.json"` để curl đọc y nguyên, không qua parse shell:

```powershell
'{"message":"Render la gi"}' | Set-Content body.json -Encoding utf8
curl.exe -i -X POST https://day12-chat-1lr6.onrender.com/chat `
  -H "Content-Type: application/json; charset=utf-8" `
  -H "Authorization: Bearer $TOKEN" `
  -H "X-Client-Id: sv-test" `
  --data-binary "@body.json"
```

Sau khi sửa → `HTTP/1.1 200 OK` + body `{"reply":"...","client_id":"sv-test",...}`.
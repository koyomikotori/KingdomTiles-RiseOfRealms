# Việc còn lại trước khi phát hành bản máy tính

Danh sách người chơi (chủ dự án) đưa ra sau M14e (2026-10-30). Làm xong các mốc dưới đây thì chuyển sang **M14c: build và phát hành bản Windows**. Mỗi mốc một nhánh; trước khi làm mốc nào thì chốt các "Câu hỏi cần chốt" của mốc đó rồi ghi luật vào `GDD.md`.

| Mốc | Nội dung | Trạng thái |
|---|---|---|
| M14f | Đặc vụ: mỗi gia tộc 1 đặc vụ, tỉ lệ lộ +1%/lượt | Xong (đã merge) |
| M14g | Bảng báo cáo quan trọng + nút mũi tên xem tướng/mưu sĩ | Xong (đã merge) |
| M14h | Chọn độ khó ván mới + tướng/mưu sĩ của gia tộc địch | Xong (đã merge) |
| M14i | Thảo phạt đạo tặc (vùng đỏ, chuyến thảo phạt, màn phát lại kiểu Dungeon Village) | Xong, chờ chơi thử |
| M14j | Cutscene mờ sau menu chính (kiểu Kairosoft) + nhạc nền mới | Chưa làm |
| M14c | Build Windows, phát hành bản máy tính | Cuối cùng |

---

## M14g — Bảng báo cáo quan trọng và nút mũi tên

**Bảng báo cáo quan trọng:** đầu lượt, nếu có sự kiện đặc biệt quan trọng thì hiện một bảng giữa màn hình, bấm **OK** hoặc **Enter** ở dưới để tắt. Các sự kiện:
- Gia tộc tuyên chiến với ta.
- Đặc vụ bị lộ (trốn về / bị giết).
- Tướng bị thương / tử trận.
- Quân lính đào ngũ vì thiếu lương nuôi.

**Xem tướng/mưu sĩ qua lại:** ngoài phím ← / → trên bàn phím, thêm **nút mũi tên** bấm được trên bảng chi tiết tướng/mưu sĩ.

Đã chốt: hiện sau trận đầu lượt và bảng kết quả trận, trước sự kiện ngẫu nhiên. Thêm cả mưu sĩ bị thương, đồng minh rời bỏ, thành chính nguy hiểm và (ở M14i) vùng đạo tặc xuất hiện. Luật ghi ở GDD §15.

---

## M14h — Độ khó và tướng của gia tộc địch

**Chọn độ khó khi tạo ván mới** (áp dụng cho quân gia tộc, cướp dạo và thảo phạt):

| Độ khó | Quân địch so với đơn vị tiêu chuẩn của người chơi | Tướng/mưu sĩ địch |
|---|---|---|
| Dễ | 75% | như thường |
| Bình thường | 100% | như thường |
| Khó | 150% | như thường |
| Huyền thoại | 200% | gia tộc trung bình +1 sao, gia tộc mạnh +2 sao |

- **Huyền thoại** chỉ mở ở lần chơi sau khi đã thắng (thống nhất) một ván Bình thường hoặc Khó.

**Gia tộc địch có tướng và mưu sĩ trong trận:**
- Gia tộc yếu: không có tướng hay mưu sĩ ra trận.
- Gia tộc trung bình: có tướng **hoặc** mưu sĩ 1–2 sao, không trang bị.
- Gia tộc mạnh: có **cả** tướng lẫn mưu sĩ 3 sao.

Đã chốt (luật ở GDD §15): hạng theo quân lực hiện tại (dưới 150 / 150–399 / từ 400), tướng địch như của ta và có thể tử trận, độ khó nhân số lính mỗi đơn vị, màn ván mới có thêm tên và màu vương quốc. Độ khó không đổi giữa ván; Huyền thoại nhớ trong `settings.cfg`.

---

## M14i — Thảo phạt đạo tặc

Tham khảo mini game thảo phạt trong Dungeon Village (Kairosoft).

**Vùng đạo tặc chiếm đóng:**
- Thỉnh thoảng một **vùng 3×3 nhấp nháy đỏ** hiện ra **gần rìa phần đất đã đặt** (không bao giờ ở khu chưa khai hoang).
- Mọi công trình trong vùng bị **vô hiệu hóa**, không dùng được.
- Nếu chưa thảo phạt thì cứ **2 lượt vùng đỏ mở rộng thêm 1 ô bán kính**.

**Bảng thảo phạt** (bấm vào vùng đỏ):
- **Tab 1:** quân lực của địch, số ải phải vượt qua.
- **Tab 2:** cử **1 tướng, 1 mưu sĩ và tối đa 10 đơn vị lính**.
- Bấm **Tiến hành thảo phạt** thì bảng đóng lại. Vùng đỏ vẫn còn; bấm vào sẽ thấy **bảng tiến trình** và ải hiện tại.

**Màn phát lại** (lượt kế tiếp, bấm vào vùng đỏ):
- Màn hình ngang, quân ta đi từ trái sang phải. **Mỗi đơn vị hiện 1 nhân vật.**
- Đội hình: **tướng và kỵ binh đi đầu, lính cận chiến ở giữa, lính đánh xa ở cuối.**
- Trên đường gặp **1–5 đơn vị địch** ở giữa ải. Hai bên lao vào nhau; bên nào hết quân hoặc hết nhuệ khí thì **văng ra khỏi màn hình**.
- Vẫn chạy giả lập trận như combat thường (`BattleSimulator`), chỉ đổi cách thể hiện. Đánh liên tục, gặp nhiều toán địch dọc đường.
- **Hết một ải:** cả đội hồi phục; đơn vị bỏ chạy hoặc bị tiêu diệt thì mất luôn. Hiện **bảng thống kê** của ải.
- Dùng **nhạc khác** với nhạc combat thường.

**Độ dài theo cấp thành:**

| Cấp thành | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| Số ải | 1 | 1 | 2 | 2 | 3 | 4 |
| Số trận phục kích mỗi ải | 1 | 1 | 2 | 2 | 3 | 3 |

- Ải sau và các lần thảo phạt sau có quân cướp đông hơn, nhiều đơn vị dọc đường hơn, cấp cao hơn (cân đo hợp lý).

**Kết thúc:**
- Đánh hết các ải thì cả đội về, vùng đỏ biến mất.
- Vùng đỏ xuất hiện thì báo trong **bảng báo cáo quan trọng** (`ImportantNews`, M14g).
- Nhận **kinh nghiệm theo số trận thắng**, cùng **trang bị và tài nguyên** từ thường tới xịn, số lượng kha khá.

**Trong khi đi thảo phạt:**
- Tướng và mưu sĩ đi thảo phạt **không tham gia** các trận với gia tộc hay cướp thường.
- Mưu sĩ đang giữ chức (vd. Ngoại giao) đi thì **tạm mất tác dụng chức** cho tới khi về.
- **Không chiêu mộ người mới thay chỗ, không sa thải** tướng/mưu sĩ đang đi.

Đã chốt (luật đầy đủ ở GDD §15): từ lượt 8, 10%/lượt, một vùng; lan tới khi chạm thành chính; ô bị khóa hẳn; bỏ mặc chỉ khóa công trình; có tướng nổi loạn cuối ải với tỉ lệ tăng dần; thua như thua trận thường; miễn phí; mỗi lượt một ải; thưởng theo số ải và độ lớn vùng.

---

## M14j — Màn hình chính và nhạc

- **Cutscene chạy mờ** phía sau menu chính, như game Kairosoft (vd. cảnh vương quốc nhỏ có dân đi lại, mây trôi, quân đi tuần).
- **Nhạc nền mới:** người chơi tự làm, thả vào `assets/audio/custom/` (cùng tên file sẽ thay nhạc cũ, xem GDD §14).

Câu hỏi cần chốt:
- Cảnh lấy từ bản đồ thật (một vương quốc dựng sẵn + MapLife) hay vẽ riêng?

---

## Ý tưởng đã nhắc trước đây (chọn cái nào đưa vào bản máy tính)

Các ý này đang nằm ở mục "Để sau" trong `GDD.md`, chưa bắt buộc cho bản phát hành:
- Màn tạo ván mới: chọn chủ tướng, cờ và **màu chủ đạo** của người chơi (§13 M12b); có thể làm cùng chọn độ khó ở M14h.
- Chọn gia tộc xuất phát, thêm gia tộc mới, mỗi gia tộc một nét riêng; tướng chiêu mộ mang trang phục của gia tộc đó (§13).
- Quân gia tộc có cấp (§8 Kinh nghiệm).
- Sự kiện mưu sĩ xin đầu quân (§8 Mưu sĩ).
- Ngoại giao: kết thông gia, yêu sách / cống nạp, mượn đường quân sự, sự kiện ngoại giao ngẫu nhiên (§9.8).
- Font pixel (§13).
- **NPC trợ lý / cánh tay phải của chúa công** (người chơi đề xuất sau M14h, để sau): hướng dẫn tutorial khi vừa tạo ván mới; chân dung nhiều biểu cảm hiện cạnh bảng thông báo với lời thoại báo cáo tình hình chiến sự; xuất hiện cả ở màn chiến thắng / thất bại.

# Ý tưởng phát triển tiếp (chưa xếp thứ tự)

Ghi lại từ người chơi sau M14c. Mỗi mục sẽ được bàn chi tiết (câu hỏi lựa chọn) trước khi làm.

## Thứ tự làm (dễ trước, khó sau)

Bản mobile (M15) vẫn để cuối cùng. Các milestone dưới đây đặt số M16 để khỏi lẫn.

| Milestone | Nội dung | Mục | Độ khó | Lý do |
|---|---|---|---|---|
| M16a (xong, chờ chơi thử) | Cân bằng và ngoại giao: nerf hồi quân doanh trại, thảo phạt thành công cộng quan hệ, tìm lỗi liên minh 0% về late, cho lại hiệp định bất tương xâm, buff mưu sĩ Ngoại giao | C1, C2, C3 | Dễ | Chủ yếu sửa số và luật có sẵn; hiệp định từng có code ở M9b |
| M16b (xong, chờ chơi thử) | Event không cần trận đánh: kho lương bị tấn công, cơ hội ám sát, tướng bất mãn, dân chúng cầu cứu, tù binh quan trọng, nhóm người khả nghi, đạo tặc cầu hòa, địch dụ hàng | B2, B5, B7 | Dễ | Dùng hệ event (M11b), đặc vụ (M14e) và tướng địch (M14h) đã có |
| M16c (xong, chờ chơi thử) | Limit break cho tướng / mưu sĩ (GDD §19) | A2 | Dễ–vừa | Chỉ thêm luật và nút trong cửa sổ tướng sĩ |
| M16d | Chợ đen | B6 | Vừa | Cửa sổ mới (6 ô, làm mới), dùng lại hệ trang bị; cần 1 portrait |
| M16e | Event có trận đánh / nhuệ khí tối đa: tướng bị phục kích, tin tuồn ra, tướng địch thách đấu tay đôi, đạo tặc bắt quan chức, mật thư bị đánh cắp, đặc vụ báo tin khẩn cấp | B1, B3, B4, B8 | Vừa | Cần trận đánh với quân rút gọn, địch còn 50%, trừ nhuệ khí tối đa, trận chỉ có 2 tướng |
| M16f | Thêm loại lính mới | C4 | Vừa | Dữ liệu `.tres` + sprite vẽ bằng script; cần chốt danh sách lính |
| M16g | Sprite theo độ hiếm + tướng 4 khung hình trở lên, có hiệu ứng | A1 | Vừa–khó | Nhiều hình vẽ (mỗi mức sao, mỗi loại vũ khí, nam / nữ) |
| M16h | Chúa công: tùy chỉnh ở màn Ván mới (đầu / thân / giới tính / tên), sprite tướng đi bộ | A4, A5 | Vừa–khó | Vẽ sprite mới; là nền cho mini game tỉ thí |
| M16i | Cố vấn nam / nữ: chọn ở Ván mới, portrait 4+ biểu cảm, thoại riêng ở báo cáo / sự kiện / thắng thua | A3 | Khó | Phải viết lại lời thoại ở rất nhiều chỗ, thành hai giọng; cần portrait |
| M16j | Mini game tỉ thí võ công (tướng) | D2 | Khó | Màn chơi mới theo thời điểm bấm; cần sprite đi bộ từ M16h |
| M16k | Mini game giải đố cờ tướng (mưu sĩ) | D1 | Khó nhất | Phải làm luật cờ tướng đầy đủ, kiểm tra chiếu hết và soạn bộ thế cờ |

Cần chuẩn bị trước:
- Portrait gã chợ đen (M16d) và hai cố vấn với 4+ biểu cảm (M16i): bạn làm bằng AI như pool portrait, hoặc mình vẽ bằng script.
- M16i nên làm sau M16b và M16e để cố vấn đọc luôn các event mới.

## A. Nhân vật và hình ảnh

### A1. Sprite theo độ hiếm của tướng / mưu sĩ
- Mỗi mức sao có sprite riêng (giáp, mũ, vũ khí, áo bào khác nhau), kèm hiệu ứng (hào quang, lấp lánh…) cho các mức cao.
- Tăng số khung hình của tướng lên 4 khung trở lên (hiện là 2) cho chuyển động mượt hơn.

### A2. Limit break (đột phá giới hạn)
- Khi tướng / mưu sĩ đã max mọi chỉ số, cho phép đột phá để nâng tiếp chỉ số.
- Đã chốt ở M16c (GDD §19): +2 trần chỉ số và +2 cấp mỗi lần; 1/2/3 lần theo sao; tài nguyên × N và N Bí kíp (chỉ từ thảo phạt thắng; chợ đen M16d sẽ bán).

### A3. Cố vấn (nhân vật dẫn truyện)
- Hai cố vấn để chọn ngay ở màn Ván mới: một nam, một nữ. Cố vấn gọi người chơi là "Chúa công".
- Cố vấn là người đưa thông báo sự kiện và báo cáo (báo cáo trận, tin quan trọng, sự kiện…).
- **Nam:** lạnh lùng, nghiêm túc, trung thành, giọng trang trọng. Thắng / thành công: chúc mừng lễ nghĩa. Thua / thất bại: khuyên nên cẩn thận.
- **Nữ:** năng động, vui tính, trung thành, giọng hoạt bát. Thắng / thành công: chúc mừng hơi quá đà. Thua / thất bại: đổ cho xui xẻo, khuyên chúa công cẩn thận hơn nhưng đừng quá áp lực.
- Portrait mỗi người có từ 4 biểu cảm trở lên (ví dụ: bình thường, vui, lo lắng, nghiêm / buồn).
- Thoại của hai người khác nhau ở mọi chỗ cố vấn nói.

### A4. Chúa công (chủ tướng của người chơi)
- Màn Ván mới (chọn tên vương quốc, màu lính) có thêm hình chúa công đứng cạnh.
- Nút "Thay đổi" mở menu chi tiết: đổi đầu / thân, giới tính, tên gọi (tên ít quan trọng vì cố vấn gọi là "Chúa công").
- Chúa công có sprite riêng, dùng cả trong mini game tỉ thí (D2).
- Cần chốt: chúa công có ra trận / có chỉ số không, hay chỉ là hình đại diện.

### A5. Sprite tướng đi bộ
- Tướng có sprite không cưỡi ngựa, dùng cho mini game tỉ thí võ công (D2) và event đấu tay đôi (B1).

## B. Sự kiện

Thêm nhiều event hơn, đặc biệt là event chỉ xuất hiện khi **đang có chiến tranh** hoặc **đang thảo phạt đạo tặc**.

### B1. Tướng địch thách đấu tay đôi trước cổng thành
- Tướng địch rủ tổng tướng của ta ra solo 1 đấu 1.
- **Chấp nhận:** mở ngay màn chiến đấu chỉ có tướng của mỗi phe (không lính, không mưu sĩ).
  - Ta thắng: tướng địch tử trận; trận kế tiếp với phe đó, quân địch bị trừ cố định 1–2 nhuệ khí tối đa ngay khi vào trận.
  - Ta thua: áp dụng tương tự cho phe ta (tướng ta tử trận, quân ta bị trừ 1–2 nhuệ khí tối đa).
- **Từ chối:** toàn bộ quân ta bị trừ cố định 1–2 nhuệ khí tối đa trong 5 lượt.

### B2. Kho lương bị tấn công
- Đánh trả: mất ít lương thực.
- Mặc kệ: mất nhiều lương thực.
- Cần chốt: "đánh trả" có mở trận đánh không, hay chỉ tính kết quả.

### B3. Tướng bị phục kích
- **Mặc kệ:** tướng chắc chắn chết, nhưng không mất thêm lính.
- **Phá vòng vây:** tướng chỉ mang theo 3–5 unit ngẫu nhiên vào trận.
  - Thắng: tướng thoát.
  - Thua: tướng chết hoặc bị thương như luật cũ, và mất luôn 3–5 unit đó.

### B4. Thông tin bị tuồn ra (doanh trại địch phòng vệ hở)
- **Cho quân đi đánh:**
  - 30% là bẫy: quân và tướng bị phục kích, tướng bị thương, 3–5 unit ngẫu nhiên mất 50% quân.
  - 70% thành công: mở trận với quân địch chỉ còn 50% quân, địch bị −2 nhuệ khí tối đa trong trận đó vì bị đánh bất ngờ.
- Từ chối: không có gì xảy ra (cần chốt).

### B5. Đặc vụ ám sát
- Đặc vụ đang nằm vùng ở gia tộc khác có lựa chọn ám sát tướng hoặc mưu sĩ của gia tộc đó.
- Tỉ lệ thành công: 50% + 5% × số sao của đặc vụ.
  - Thành công: mục tiêu 50% bị thương, 50% chết luôn.
  - Thất bại: đặc vụ bị lộ ngay; có tỉ lệ chết, nếu không chết thì buộc phải quay về.
- Gắn với `ClanOfficers` (M14h: tướng / mưu sĩ của gia tộc, chỗ trống `VACANCY_TURNS`).

### B6. Chợ đen
- Thỉnh thoảng xuất hiện. Người chơi chọn giao thương: đổi tài nguyên lấy trang bị của tướng / mưu sĩ, độ hiếm đến Sử thi.
- Bảng tối đa 6 món, xếp 3 trên 3 dưới.
- Làm mới (refresh) tối đa 3 lần, mỗi lần 10 khoáng sản + 10 gỗ cứng.
- Portrait riêng: gã mặc áo choàng đen, mũ che nửa trên đầu, miệng cười gian.
- Từ chối: không có chuyện gì xảy ra.

## C. Ngoại giao và cân bằng

### C1. Hiệp định bất tương xâm trở lại
- Cho ký lại hiệp định bất tương xâm (đã bỏ ở M14b).
- Buff mưu sĩ Ngoại giao.
- Vấn đề người chơi gặp: về late game, dù quan hệ 100, tỉ lệ liên minh với mọi gia tộc là 0%. Cần điều tra nguyên nhân (có thể do độ cảnh giác / `threat` khi vương quốc quá mạnh) trước khi sửa.

### C2. Thảo phạt đạo tặc thành công
- Cộng điểm quan hệ với toàn bộ gia tộc.

### C3. Nerf tốc độ hồi quân của doanh trại
- Hiện tại: `REPLENISH_FRACTION` 10% + 1% × cấp mỗi doanh trại (6 doanh trại cấp 5 = 40%/lượt).

### C4. Thêm nhiều loại unit hơn

## D. Mini game (cho kinh nghiệm)

Chung: chỉ cho tướng / mưu sĩ từ 3 sao trở lên, mỗi người 1 lần mỗi 5 lượt, nút mini game nằm dưới portrait trong cửa sổ tướng sĩ. Thắng hay thua đều có kinh nghiệm, chỉ khác ít hay nhiều.

### D1. Giải đố cờ tướng (mưu sĩ)
- Bàn cờ đã đi sẵn nhiều nước; người chơi tìm số nước tối thiểu để chiếu hết.
- Cần chốt: nguồn thế cờ (soạn tay một bộ thế cờ), độ khó theo sao.

### D2. Tỉ thí võ công (tướng)
- Tấn công: thanh trượt ngang, bấm chuột trái hoặc Space đúng thời điểm để gây sát thương.
- Phòng thủ: bấm W / A / S / D đúng thời điểm để né đòn tướng đối phương tung ra.
- Dùng sprite tướng đi bộ (A5) và sprite chúa công (A4).
- Có thể dùng lại cho event đấu tay đôi (B1) nếu muốn trận solo do người chơi điều khiển.

## B7–B8. Event bổ sung (người chơi gửi thêm sau M16a)

- **B7 (làm ở M16b):** Tướng bất mãn, Dân chúng cầu cứu, Tù binh quan trọng, Nhóm người khả nghi, Đạo tặc cầu hòa, Tướng ta được địch chiêu hàng. Luật chi tiết ở GDD §18.
- **B8 (để M16e, cần trận đánh hoặc nhuệ khí tối đa):**
  - Đạo tặc bắt giữ quan chức: Cứu viện (mở trận, có thưởng) / Chuộc người (mất tài nguyên) / Bỏ mặc (trừ quan hệ với mọi gia tộc).
  - Mật thư bị đánh cắp: Thay đổi kế hoạch (mất thêm tài nguyên) / Bỏ qua (80% trận tiếp theo địch +2 nhuệ khí tối đa).
  - Đặc vụ báo tin khẩn cấp (cần có đặc vụ): Tin tưởng (50% tin thật: địch tấn công lượt sau, ta +3 nhuệ khí tối đa; tin giả: ta giao tranh với −3) / Mặc kệ (50% không sao, 50% địch tấn công lượt sau, ta −1).

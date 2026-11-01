# Kingdom And Tetris — GDD v0.2

Tên tạm của dự án. Tài liệu này ghi lại các quyết định đã chốt; mục "Câu hỏi mở" là những thứ chưa quyết.

## 1. Tóm tắt

Game chiến thuật xây dựng vương quốc theo lượt, 2D pixel art, chơi đơn, Windows PC, Godot 4.5 + GDScript.

Người chơi đặt các mảnh đất (polyomino kiểu Tetris) để mở rộng lãnh thổ. Hình dạng và cách sắp xếp lãnh thổ quyết định sản lượng tài nguyên và loại quân có thể tuyển. Định kỳ địch tấn công, trận đánh diễn ra tự động trên chiến trường nhìn ngang.

## 2. Vòng lặp một lượt

1. Nhận 3 mảnh đất.
2. Đặt mảnh để mở rộng hoặc cải tạo lãnh thổ.
3. Xây công trình, tuyển quân, ngoại giao (từ M6).
4. Kết thúc lượt: thu tài nguyên theo địa hình, trả tiền nuôi quân.
5. Nếu có cướp / quân xâm lược đến, hoặc mình đi đánh → auto-battle (§7).
6. Xử lý sự kiện (nếu có).

Không còn "đợt địch theo mốc lượt cố định": địch đến từ cướp ngẫu nhiên và từ các gia tộc láng giềng (§7, §9).

## 3. Bản đồ

| Thông số | Giá trị |
|---|---|
| Kích thước lưới | 12×12 (cấu hình được, có thể lên 15×15) |
| Kích thước ô | 32×32 px |
| Camera | Lăn chuột để zoom, kéo chuột phải/giữa để di chuyển |
| Thành chính | 2×2, đặt giữa bản đồ |
| Lãnh thổ khởi đầu | Vùng 4×4 cỏ quanh thành |
| Hệ tọa độ | `Vector2i(x, y)`, x sang phải, y xuống dưới, (0,0) là góc trên trái |

Mỗi ô lưu riêng: **địa hình**, **quyền sở hữu**, **công trình**, **ô quan trọng** (sẽ thêm ở M2). Không gộp vào một biến `type`.

Ô chưa sở hữu là đất hoang, chưa có địa hình. Địa hình chỉ xuất hiện khi người chơi đặt mảnh đất lên.

### Địa hình v0.1

| Địa hình | Tài nguyên chính |
|---|---|
| Cỏ | — (đất trống để xây) |
| Ruộng | Lương thực |
| Rừng | Gỗ |
| Đồi đá | Đá (sau này: quặng) |

("Mỏ" là công trình đặt trên đồi đá, không phải địa hình.)

## 4. Cơ chế đặt đất

- Mảnh đất là một nhóm ô có hình dạng, mỗi ô trong mảnh có địa hình riêng (ngẫu nhiên theo trọng số của địa hình).
- Hình dạng v0.1: ô đơn, thanh 2, thanh 3, vuông 2×2, **L trái** và **L phải** (hai hình khác nhau, là ảnh gương của nhau).
- **Người chơi không xoay được mảnh.** Thay vào đó, mỗi hướng xoay của một hình là một mảnh riêng có thể được rút ra: L trái có 4 hướng, L phải có 4 hướng, thanh có ngang/dọc, vuông và ô đơn chỉ có 1. Mỗi hình được chia đều trọng số cho các hướng của nó, để hình nhiều hướng không bị rút ra nhiều hơn. (Thử nghiệm, có thể đổi sang cho xoay sau.)
- **Kết nối:** mảnh phải chạm cạnh (không tính chéo) với lãnh thổ hiện có, hoặc đè lên lãnh thổ hiện có.
- **Đè / thay thế:** mảnh mới được đặt đè lên đất đã đặt trước đó. Ô bị đè **mất địa hình cũ** (và mất sản lượng của nó), lấy địa hình của mảnh mới. Đây là cách cải tạo lãnh thổ.
  - Không được đè lên thành chính.
  - Ô có công trình khác: v0.1 **không cho đè** (xem câu hỏi mở).
- **Ô quan trọng:** khoảng 20% số mảnh có một ô quan trọng (đánh dấu ◆). Đè lên ô quan trọng thì mất nó.
- Đặt không hợp lệ thì không được thay đổi bản đồ và không tiêu thụ mảnh.
- Mỗi lượt nhận 3 mảnh mới. Không bắt buộc đặt hết; mảnh chưa đặt **bị bỏ** khi kết thúc lượt.
- Vì được phép đè lên lãnh thổ của mình, gần như luôn có chỗ đặt, nên v0.1 chưa cần cơ chế đổi mảnh.

## 5. Sản lượng

> **Đã thay bằng Kinh tế v2 (§8, "Kinh tế v2"):** đất không còn tự cho tài nguyên; chỉ công trình khai thác cho tài nguyên. Bảng dưới đây là luật cũ (M3–M11e).

Mỗi lượt, mỗi ô thuộc lãnh thổ cho sản lượng theo địa hình của nó:

| Địa hình | Sản lượng mỗi lượt |
|---|---|
| Cỏ | không có (đất trống để xây) |
| Ruộng | 1 lương thực |
| Rừng | 1 gỗ |
| Đồi đá | 1 đá |

Ví dụ: có 4 ô ruộng thì được 4 lương thực mỗi lượt. Đặt một ô rừng đè lên 1 trong 4 ô ruộng đó thì còn 3 lương thực + 1 gỗ mỗi lượt.

**Ô quan trọng ◆ cho sản lượng ×2** trên ô đó (ô cỏ ◆ vẫn không cho gì).

Tài nguyên được cộng vào kho khi bấm **Kết thúc lượt**, tính theo lãnh thổ lúc đó. Thanh trên cùng hiển thị kho và thu nhập mỗi lượt, ví dụ "Lương thực: 10 (+5)". Khi rê mảnh lên bản đồ, game cho biết thu nhập sẽ thay đổi thế nào nếu đặt ở đó.

Loại tài nguyên nằm trong `data/resources/`, sản lượng của địa hình nằm trong trường `yields` của file địa hình.

Các quy tắc kề nhau (cụm ruộng, trại gỗ cạnh rừng, mỏ cạnh đồi…) **tạm gác lại**; chỉ thử thêm nếu sau khi chơi thử thấy việc xếp đất còn thiếu chiều sâu.

## 6. Liên kết bản đồ ↔ chiến trường

Bản đồ ảnh hưởng chiến đấu trực tiếp chứ không chỉ qua tài nguyên:

- ~~Có rừng (đủ số lượng) → mở khóa cung thủ.~~ (bỏ ở M13)
- Có đồng cỏ lớn liền mạch → mở khóa kỵ binh.
- Có đồi đá + mỏ → mở khóa lính khiên, sau này là quân trang bị nặng.
- Tướng có thể nhận buff theo địa hình lãnh thổ.

## 7. Chiến đấu — kiểu Ninja Village (Kairosoft)

### 7.1 Ba loại xung đột

| Loại | Xuất hiện khi | Thua thì | Thắng thì (đề xuất) |
|---|---|---|---|
| **Cướp** | Ngẫu nhiên mỗi lượt, hoặc do sự kiện | Mất một phần tài nguyên | Thu một ít chiến lợi phẩm |
| **Quân xâm lược** | Gia tộc láng giềng có quan hệ xấu tấn công | Mất đất ở phía biên giáp kẻ địch | Quan hệ / uy tín thay đổi, có thể đòi bồi thường |
| **Đi xâm lược** | Người chơi đem quân đánh vùng xung quanh | Mất **toàn bộ** quân + bồi thường tài nguyên | Chiếm vùng / tài nguyên |

**Toàn bộ quân tham chiến** trong mọi trận.

### 7.2 Cướp

- Từ lượt 6, mỗi lượt có **15%** khả năng cướp xuất hiện.
- **Không báo trước:** cướp đến ngay đầu lượt, trận đánh diễn ra luôn.
- Quân cướp đông dần theo số lượt (cấu hình trong `data/raids/bandits.tres`).
- **Thua:** mất 30% mỗi loại tài nguyên, và lính còn sống mất thêm 30% mỗi loại (tháo chạy). Lính chết trong trận thì vẫn mất như thường.
- **Thắng:** nhận một ít tài nguyên theo số cướp bị đánh bại. Sau này: kinh nghiệm cho tướng, mưu sĩ, lính.
- **Trạm lính canh:** mỗi trạm giảm 4% tỉ lệ cướp, tối đa 3 trạm (M14d: 1 trạm ở thành cấp 1, +1 mỗi cấp thành, tối đa 4), tốn phí duy trì mỗi lượt. Nếu không trả đủ phí duy trì thì lượt đó trạm không có tác dụng. Sau này có thể thêm tác dụng khác.

### 7.3 Quân xâm lược & mất đất

Bản đồ vương quốc có 4 cạnh tương ứng 4 hướng trên bản đồ thế giới. Thua trước quân xâm lược đến từ hướng nào thì mất các ô lãnh thổ sát cạnh đó: ô trở lại đất hoang, công trình trên đó bị phá. Thành chính không bao giờ mất. Cần có bản đồ thế giới (§9) để biết hướng.

### 7.4 Trận đánh theo pha (bản M5, sẽ thay bằng §7.6)

Mỗi loại lính có **hàng** (trước / giữa / sau) và **kiểu đánh** (cận chiến / cung / súng). Quân tính theo **số lượng**, không tính từng con.

1. **Súng** (nếu có): hai phe nổ súng cùng lúc, sát thương vào **hàng đầu** của đối phương.
2. **Cung**: tên bắn vòng lên rồi rơi xuống, sát thương **chia đều cho cả 3 hàng** của đối phương (dàn trải nên yếu hơn mỗi hàng).
3. **Xung phong**: bộ binh (sau này cả tướng, kỵ binh) lao vào nhau giữa chiến trường. Mỗi hiệp, toàn bộ lính cận chiến đánh vào hàng đầu còn sống của đối phương; cung thủ vẫn bắn yểm trợ với 50% sức.
4. Sau mỗi bước: phe nào chết hết, hoặc **còn dưới 40% quân** ban đầu thì tan vỡ và thua. Hết 8 hiệp mà chưa phân thắng bại thì phe còn tỉ lệ quân cao hơn thắng (bằng nhau thì phe phòng thủ thắng).

Sát thương của một nhóm = số lính còn sống × max(1, công − thủ của mục tiêu) × hệ số pha × ngẫu nhiên ±10%. Hai phe ra đòn cùng lúc trong mỗi bước.

Không có quân thì thua ngay.

### 7.5 Hiển thị (M6)

Màn hình ngang, chia theo bề ngang:

| 10% | 18% | 44% | 18% | 10% |
|---|---|---|---|---|
| Thông tin phe 1 (tên, số lính, sĩ khí từng đơn vị) | Xạ thủ phe 1 | Chiến trường cận chiến | Xạ thủ phe 2 | Thông tin phe 2 |

(Ban đầu là 5/20/50/20/5; tăng khung thông tin lên 10% để đủ chỗ hiện tên đơn vị, đọc được cả trên điện thoại.)

- Phe của người chơi luôn ở bên trái.
- Mỗi hình lính đại diện cho 4 lính.
- Luôn mở màn hình trận đánh khi có cướp; có nút **Bỏ qua** để mô phỏng nốt và xem kết quả ngay.
- Thông tin luôn hiện sẵn, không cần rê chuột (chuẩn bị cho bản điện thoại).

- Súng: loạt đạn li ti bay vụt qua chiến trường.
- Cung: tên bay lên khỏi khung hình, rồi rơi xuống từ phía trên.
- Xung phong: bộ binh + tướng (cưỡi ngựa) lao vào, va chạm ở giữa.
- Mỗi hình lính đại diện cho một nhóm lính; khi thiệt hại đủ số lượng thì hình bị thổi bay ra phía sau, ra khỏi khung hình.
- Nút điều khiển: **tạm dừng**, **tăng tốc**, **rút lui** (§7.6).
- Kết thúc: bảng thống kê thiệt hại của cả 2 phe và sát thương gây ra theo loại lính (đã có từ M5).

### 7.6 Chiến đấu v2 — chỉ số lính, sĩ khí, rút lui (đã chốt)

**Chỉ số của một đơn vị lính:**

| Chỉ số | Ý nghĩa |
|---|---|
| **HP / Number** | Số lính còn lại của đơn vị. Bị đánh thì số lính giảm. |
| **Melee Attack** | Sát thương khi đánh gần. |
| **Melee Defense** | Giảm sát thương nhận từ đánh gần. |
| **Armor** | Giảm sát thương nhận từ đạn và tên. |
| **Charge Attack** | Sát thương cộng thêm, chỉ ở **lần lao vào giao tranh đầu tiên**; sau đó không còn tác dụng. |
| **Morale** (sĩ khí) | Giảm khi tướng chết, và khi số lính giảm xuống dưới các mốc nhất định. Về 0 thì cả đơn vị **bị loại khỏi trận như bị tiêu diệt hoàn toàn**, dù vẫn còn lính. |
| **Range Attack** | Sát thương đánh xa. Chỉ đơn vị dùng súng hoặc cung mới có. |

**Đánh xa:**
- **Súng:** nã một loạt đạn duy nhất ở đầu trận, sau đó không tham gia trận đánh nữa.
- **Cung:** bắn nhiều loạt tên, cách nhau một khoảng thời gian. Cung càng tốt thì bắn càng nhanh (chỉ số thời gian nạp tên).

**Rút lui:** trong trận có nút **Rút lui**, dùng được bất cứ lúc nào. Rút lui thì trận đó tính là **thua**, nhưng toàn bộ quân chỉ thiệt hại **50%** thay vì bị đánh tan. Dùng khi tiền tuyến đã vỡ và muốn giữ lại hậu tuyến (súng, cung).

**Hệ quả kỹ thuật:** vì có rút lui giữa trận và cung bắn theo thời gian, trận đánh chuyển sang mô phỏng **theo thời gian** (tick), có thể chạy từng bước. Màn hình trận đánh điều khiển bộ mô phỏng: tạm dừng thì ngừng gọi, tăng tốc thì chạy nhiều tick mỗi khung hình, rút lui thì kết thúc ngay. Bộ mô phỏng vẫn thuần logic, có seed và test headless được (test có thể giả lập "rút lui ở giây thứ X").

**Đơn vị (squad):** mỗi lần tuyển được **một đơn vị gồm nhiều lính** (ví dụ kiếm sĩ: 20 lính). Trên màn hình trận đánh, mỗi đơn vị chỉ vẽ vài hình đại diện (ví dụ 5 hình cho 20 lính) để tránh lag, giống Ninja Village. Mỗi đơn vị là một quân riêng, có số lính và sĩ khí riêng (sau này: kinh nghiệm riêng). Giá tuyển và phí nuôi tính theo đơn vị.

**Quản lý đơn vị:**
- **Bổ sung quân:** cuối mỗi lượt, đơn vị thiếu quân tự hồi 10% quân số chuẩn (25% trước M13b; M14d: + cấp của mỗi doanh trại, tính theo %) (làm tròn lên, không vượt chuẩn), **miễn phí** (đã tốn lương thực nuôi quân). Cần có ít nhất 1 doanh trại.
- **Giới hạn số đơn vị:** thành chính cho 2, mỗi doanh trại thêm 4; tối đa 3 doanh trại (tổng 14). Sau này: nâng cấp / mở rộng thành để tăng giới hạn và mở rộng ra đất hoang mới.
- **Giải tán:** người chơi có thể giải tán một đơn vị (ví dụ còn quá ít quân, hoặc muốn thay bằng loại tốt hơn). Không hoàn tài nguyên.
- Không có gộp đơn vị.

**Sĩ khí:** mỗi loại lính có mức sĩ khí riêng; lính càng tốt sĩ khí càng cao (như Shogun 2). Sĩ khí giảm mỗi khi đơn vị mất thêm 25% quân, và khi tướng chết (khi có tướng). Về 0 thì đơn vị **vỡ**.

**Kết thúc trận:** phe có toàn bộ đơn vị bị vỡ hoặc chết hết thì thua. Hết giờ (120 giây) mà bên tấn công chưa thắng thì **bên tấn công thua** (như Total War): ta đánh gia tộc / thảo phạt mà hết giờ là thất bại; bị cướp / xâm lược mà cầm cự đủ 120 giây là thắng. Cả hai phe cùng vỡ một lúc thì phe còn tỉ lệ quân cao hơn thắng (bằng nhau thì phe phòng thủ thắng).

**Thiệt hại khi thua** (cả thua thường lẫn rút lui):
- Đơn vị **đã vỡ** (hết quân hoặc hết sĩ khí): **mất sạch**.
- Đơn vị **chưa vỡ** (rút lui, hoặc khi hết giờ): **giữ 50%** số lính còn lại.
- Tài nguyên vẫn bị mất như thua bình thường (cướp: 30%).
- Phe thắng: đơn vị bị vỡ vẫn giữ số lính sống sót (họ quay về sau trận).

## 8. Công trình & quân đội

- Prototype: 3 tài nguyên (lương thực, gỗ, đá). Quặng và vàng thêm khi có quân cao cấp / tướng.
- Tất cả chỉ số nằm trong file dữ liệu (`data/buildings/`, `data/units/`), không viết cứng trong code.

### Công trình (M4)

- Xây trong lãnh thổ, chọn ở tab **Xây dựng**, có bóng xem trước giống mảnh đất.
- Xây xong thì trừ tài nguyên. Không đủ tài nguyên hoặc chỗ không hợp lệ thì không xây và không trừ gì.
- Mảnh đất không được đè lên công trình.

| Công trình | Giá | Điều kiện | Tác dụng |
|---|---|---|---|
| Doanh trại | 6 gỗ, 2 đá | Ô cỏ, tối đa 1 | Cho phép tuyển quân |
| Trạm lính canh | 4 gỗ, 3 đá | Ô cỏ, tối đa 3 | −4% khả năng bị cướp mỗi trạm; duy trì 1 lương thực/lượt |

Công trình có thể có phí duy trì. Phí này được trả sau tiền nuôi quân; nếu không đủ thì lượt đó công trình tạm ngưng tác dụng.

### Quân lính (M4)

- Tuyển ở tab **Quân đội**. Mỗi lính tốn **1 lương thực mỗi lượt** để nuôi.
- Thanh tài nguyên hiển thị thu nhập ròng (sản lượng trừ nuôi quân).
- Cuối lượt: thu sản lượng trước, rồi trả tiền nuôi quân. Nếu không đủ lương thực, lính **bỏ đi** (nhóm đông nhất bỏ trước) cho đến khi đủ.

Mỗi lần tuyển được 1 đơn vị; giá và phí nuôi tính theo đơn vị.

| Lính | Số lính | Hàng / kiểu | Cận chiến | Phòng thủ | Giáp | Xung kích | Sĩ khí | Bắn xa / nạp | Giá | Điều kiện |
|---|---|---|---|---|---|---|---|---|---|---|
| Kiếm sĩ | 20 | Trước / cận chiến | 9 | 7 | 5 | 5 | 8 | — | 3 lương thực, 1 đá | Doanh trại |
| Thương binh | 20 | Giữa / cận chiến | 6 | 9 | 4 | 3 | 7 | — | 2 lương thực, 2 gỗ | Doanh trại |
| Cung thủ | 15 | Sau / cung | 3 | 2 | 2 | 1 | 5 | 6 / 5 giây | 2 lương thực, 3 gỗ | Doanh trại (M13: bỏ điều kiện rừng) |
| Cướp cầm dao | 16 | Trước / cận chiến | 6 | 3 | 1 | 4 | 4 | — | (địch) | |
| Cướp cung | 10 | Sau / cung | 2 | 1 | 0 | 0 | 3 | 4 / 6 giây | (địch) | |

Số đơn vị cướp = 1 + lượt × 0.15. Cân bằng hiện tại (mô phỏng 200 trận mỗi trường hợp): lượt 6 cần 1 đơn vị, lượt 12 khoảng 2, lượt 20–30 khoảng 4 đơn vị (2 kiếm sĩ + 1 thương binh + 1 cung thủ). Trận kéo dài khoảng 7–40 giây tùy chênh lệch lực lượng.

Sau này: lính khiên, kỵ binh, lính súng; tướng (1 tướng võ + 1 quân sư mẫu).

### Công trình khai thác, tài nguyên mới, cấp thành chính (M11c, đã chốt)

**Tài nguyên mới:** Khoáng sản (giá trị giao thương 3), Gỗ cứng (2), Ngựa (3). Dùng để nâng cấp thành và sau này tuyển tướng, kỵ binh, quân tinh nhuệ. Lương thực, gỗ, đá là **tài nguyên cơ bản**.

**Công trình khai thác** (1 ô, xây trên ô đúng địa hình trong lãnh thổ). Phần sinh ra cộng thêm vào sản lượng sẵn có của ô; đặt trên ô ◆ thì sản lượng của công trình ×2. Không trả nổi phí duy trì thì công trình ngừng khai thác lượt sau, giống các công trình khác.

| Công trình | Đặt trên | Cần thành | Mỗi lượt | Giá xây | Phí duy trì |
|---|---|---|---|---|---|
| Mỏ khai thác | Đồi | Cấp 2 | +2 Đá, +1 Khoáng sản | 8 Gỗ, 4 Đá | 1 Lương thực |
| Xưởng gỗ | Rừng | Cấp 2 | +2 Gỗ, +1 Gỗ cứng | 6 Gỗ, 4 Đá | 1 Lương thực |
| Trại ngựa | Ruộng | Cấp 3 | +1 Lương thực, +1 Ngựa | 8 Gỗ, 2 Đá | không |

Giới hạn: Mỏ khai thác 3, Xưởng gỗ 3, Trại ngựa 2.

**Thành chính 6 cấp** (nút "Nâng cấp thành chính" trong tab Xây dựng, có hiệu lực ngay). Mỗi cấp thêm **1 chỗ cho đơn vị lính**, mở khóa công trình, và sau này (M11d) cho tuyển **tướng tới N sao** ở cấp N.

| Lên cấp | Giá |
|---|---|
| 2 | 20 Gỗ, 20 Đá |
| 3 | 30 Gỗ, 30 Đá, 10 Khoáng sản |
| 4 | 40 Đá, 20 Khoáng sản, 15 Gỗ cứng |
| 5 | 60 Đá, 35 Khoáng sản, 30 Gỗ cứng |
| 6 | 80 Đá, 50 Khoáng sản, 45 Gỗ cứng, 20 Ngựa |

Các con số sẽ cân bằng lại sau. Chiến thắng Hòa bình thịnh vượng (§9b) chỉ tính thu nhập của 3 tài nguyên cơ bản.

### Kinh tế v2 (làm cùng M11f, đã chốt)

**Lý do:** tránh lạm phát tài nguyên, người chơi farm quá nhanh.

**Khởi đầu:** vào game có sẵn **80 Lương thực, 80 Gỗ, 80 Đá** và **10 Khoáng sản, 10 Gỗ cứng, 10 Ngựa**.

**Đất không tự cho tài nguyên nữa.** Mảnh đất chỉ mở rộng lãnh thổ và cho địa hình để xây. Tài nguyên chỉ đến từ **công trình khai thác**, và công trình cho nhiều hơn trước. Ô ◆ vẫn nhân đôi sản lượng của công trình đặt trên nó.

**Công trình khai thác** (đều xây được từ thành cấp 1; **Trại ngựa đổi thành Nông trại**):

| Công trình | Đặt trên | Cấp 1 | Cấp 2 | Cấp 3 | Cấp 4 | Cấp 5 | Cấp 6 |
|---|---|---|---|---|---|---|---|
| Nông trại | Ruộng | 5 LT | 8 LT | 11 LT, 1 Ngựa | 13 LT, 2 Ngựa | 15 LT, 3 Ngựa | 18 LT, 4 Ngựa |
| Xưởng gỗ | Rừng | 5 Gỗ | 8 Gỗ, 1 Gỗ cứng | 10 Gỗ, 2 Gỗ cứng | 12 Gỗ, 3 Gỗ cứng | 14 Gỗ, 4 Gỗ cứng | 17 Gỗ, 5 Gỗ cứng |
| Mỏ khai thác | Đồi | 5 Đá | 8 Đá, 1 Khoáng sản | 10 Đá, 2 Khoáng sản | 12 Đá, 3 Khoáng sản | 14 Đá, 4 Khoáng sản | 17 Đá, 5 Khoáng sản |

Sản lượng đã tăng nhẹ sau lần chơi thử đầu (trước là 4 / 6–7 / 8–9 … / 14–15).

**Nâng cấp công trình:** bấm vào công trình → tab Nâng cấp. Cấp công trình **không vượt cấp thành chính** (thành cấp 3 mới nâng công trình lên cấp 3). Giá lên cấp N = **N × giá xây**, từ cấp 3 thêm **(N − 2) × 2 Khoáng sản và 2 Gỗ cứng**. Phí duy trì tăng **1 Lương thực mỗi cấp** trên cấp 1. Di chuyển giữ nguyên cấp; phá hủy hoàn lại 50% giá xây.

**Giới hạn số công trình:** mỗi loại **3 cái ở thành cấp 1, +1 mỗi cấp thành** (cấp 6: 8 cái), áp dụng cho **mọi công trình**, kể cả Doanh trại (Trạm lính canh: từ M14d là 1, +1 mỗi cấp thành, tối đa 4).

**Thành chính không đổi kích thước** (2×2). Bản đầu cho thành lớn thêm 1 ô mỗi phía ở cấp 2, 4, 6, nhưng **đã bỏ sau khi chơi thử**: phải chờ có đủ ô cỏ quanh thành làm game khó quá.

**Mưu sĩ Nội chính:** "+% sản lượng" nay áp dụng cho toàn bộ sản lượng công trình khai thác (không còn sản lượng đất).

**Để sau:** Doanh trại nâng cấp khi có loại lính mới cần doanh trại cấp cao; Trạm lính canh cấp cao thành **Sở cảnh sát** (giảm cướp nhiều hơn và hạn chế các sự kiện xấu mới).

**Bảng công trình (kiểu Kairosoft, chốt sau khi chơi thử M11c):** tab Xây dựng chỉ để **xây mới** (mỗi công trình ghi số đang có / tối đa, khóa khi chưa đủ cấp thành hoặc đã đủ số). **Bấm vào công trình trên bản đồ** mở bảng của nó:
- Tab **Thông tin** (mô tả, vị trí, sản lượng, phí duy trì, số đang có) và **Nâng cấp** (hiện chỉ thành chính có nâng cấp).
- Thao tác bên dưới: **Nâng cấp** (thành chính) · **Di chuyển** · **Phá hủy**. Bấm thao tác thì bảng ghi rõ nó sẽ làm gì, rồi chờ **Xác nhận** / **Hủy**.
- **Di chuyển:** miễn phí, chọn ô mới trên bản đồ (cùng luật như xây: trong lãnh thổ, đúng địa hình, ô trống), Esc để hủy.
- **Phá hủy:** hoàn lại 50% giá xây, không hoàn tác được.
- Thành chính không phá hủy hay di chuyển được.

### Bố cục tab và thi công mất lượt (M12d, đã chốt)

**Thanh tab bên phải:** rộng 340 px (trước 300); 4 nút tab Đất / Xây dựng / Quân đội / Tướng sĩ rộng bằng nhau.

**Tab Xây dựng và Quân đội** chỉ còn thông tin những gì đang có:
- Trên cùng một nút dài **Xây dựng công trình** / **Tuyển lính** mở bảng ở giữa màn hình.
- Tab Xây dựng: cấp thành, **Đội thợ** đang dùng / tối đa, rồi mỗi loại công trình đang có một dòng: hình, số đang có / tối đa (kể cả đang thi công), tổng phí duy trì của loại đó.
- Tab Quân đội: số đơn vị / chỗ, tổng tướng, mưu sĩ Quân sự, mỗi loại lính đang có một dòng (hình, số đơn vị và lính, tổng phí nuôi), rồi danh sách đơn vị (cấp, kinh nghiệm, giải tán).

**Bảng Xây dựng (giữa màn hình, kiểu Kairosoft):**
- Danh mục trên đầu: **Tất cả / Sản xuất / Quân sự / Hành chính** (`BuildingData.category`). Hiện có: Sản xuất = Nông trại, Xưởng gỗ, Mỏ khai thác; Quân sự = Doanh trại; Hành chính = Trạm lính canh. Sau này: Trại tập bắn, Võ trường, Chuồng ngựa chiến, Học viện quân sự, Xưởng rèn khí giới (mở lính cao cấp); Sở cảnh sát, Chính viện, Quan phủ (chưa chốt tác dụng).
- Bên trái danh sách công trình (khóa khi chưa đủ cấp thành / đã đủ số), bên phải hình, công dụng tóm tắt, chi phí, số lượt xây và nút **Xây dựng**: bảng đóng lại, chọn chỗ đặt nền móng trên bản đồ.
- **Bảng Tuyển lính** làm cùng kiểu, danh mục theo hàng quân (Tất cả / Tiền tuyến / Hậu tuyến). Lính vẫn **tuyển ngay**, không mất lượt.

**Thi công mất lượt:**
- Xây mới mất `BuildingData.build_turns` lượt: Trạm lính canh 1, Nông trại / Xưởng gỗ / Mỏ / Doanh trại 2.
- Nâng cấp công trình mất số lượt bằng **cấp mới** (lên cấp 3: 3 lượt); thành chính mất **cấp mới + 1**.
- Trả tiền khi đặt nền móng / bắt đầu nâng cấp. Số lượt giảm 1 ở mỗi lần kết thúc lượt; về 0 thì xong.
- **Đang thi công thì ngừng hoạt động:** không sản xuất, không phí duy trì, không tính vào chỗ đơn vị, bổ sung quân, giảm cướp, điều kiện tuyển lính / đặc tính / sự kiện. Thành chính đang nâng cấp vẫn giữ mọi giới hạn của cấp cũ nhưng đóng Chiêu hiền tới khi xong.
- Trên bản đồ: giàn giáo + số lượt còn lại. Bấm vào chỉ hiện lượt hoàn thành và nút **Phá hủy** (hoàn 50% giá đã trả); với công trình / thành đang nâng cấp là **Hủy nâng cấp** (hoàn 50%, về cấp cũ). Không di chuyển được khi đang thi công.
- **Đội thợ:** số công trình thi công cùng lúc (kể cả thành) tối đa **1 + cấp thành**.
- Save cũ: công trình đã có coi như xong.
- Để sau: trả thêm để xây nhanh (cân bằng ở M14).

### Ruộng đất xung quanh, tháp canh, thành chứa quân (M14d, đã chốt)

Mục tiêu: ô đất trống bớt vô dụng; người chơi muốn đặt nhiều ô cùng loại quanh công trình khai thác, hoặc xây công trình ở chỗ có nhiều ô cùng loại.

- **Ô xung quanh:** Nông trại / Xưởng gỗ / Mỏ nhận thêm **2 tài nguyên cơ bản** (lương thực / gỗ / đá) từ **mỗi ô cùng loại đất kề bên** (8 ô xung quanh: ruộng / rừng / đồi), **ô ◆ cho 4**. Chỉ tính ô trong lãnh thổ và **chưa có công trình** đứng trên. Số này không đổi theo cấp công trình. Một ô nằm giữa hai công trình cùng loại thì **cho cả hai**.
- **Ô của chính công trình làm ra ít hơn 1** tài nguyên cơ bản ở mọi cấp (nông trại cấp 1: 5 → 4, cấp 6: 18 → 17; trên ô ◆ vẫn nhân đôi sau khi trừ). Tài nguyên phụ (ngựa, gỗ cứng, khoáng sản) giữ nguyên.
- Đang thi công hoặc thiếu phí duy trì thì cũng không nhận từ ô xung quanh. Mưu sĩ Nội chính cộng % trên cả phần này.
- Giao diện: bảng công trình ghi "Trong đó từ ô đất xung quanh"; bấm vào một ô đất thấy nó cho công trình bên cạnh bao nhiêu; khi đặt mảnh đất thì dòng sản lượng tính cả phần ô xung quanh thay đổi.
- **Trạm lính canh:** thành cấp 1 chỉ xây được **1 trạm**, **+1 mỗi cấp thành**, **tối đa 4**.
- **Thành chính chứa quân:** thành cấp 1 chứa **3** đơn vị, mỗi cấp +1 (cấp 6: **8**); mỗi doanh trại vẫn thêm 4 chỗ.
- **Ván mới có sẵn 3 đơn vị** đủ quân: Kiếm binh, Thương binh, Cung thủ nông dân.
- **Doanh trại cấp N tăng tốc hồi quân thêm N × 0.5%**, cộng thẳng vào mức gốc 5% (M16a, trước là 10% + N%; 6 doanh trại cấp 5: 5% + 15% = **20%** mỗi lượt). Vẫn cần ít nhất 1 doanh trại thì mới hồi quân; doanh trại đang thi công không tính.
- Tiếp theo: các công trình hành chính (M14e, bên dưới).

### Công trình hành chính (M14e, đã chốt)

Tất cả xây trên **ô cỏ**, mục **Hành chính** trong bảng Xây dựng. Như mọi công trình: thiếu phí duy trì hoặc đang thi công thì không có tác dụng.

| Công trình | Mở ở thành | Số lượng | Cấp | Tác dụng |
|---|---|---|---|---|
| **Chợ** | 2 | 1 ở thành cấp 2, +1 mỗi cấp thành (cấp 6: 5) | không | Mỗi chợ: +10 giá trị hàng đổi được với mỗi gia tộc mỗi lượt (40 → 90), giá lợi hơn 3% (tối đa 15%) |
| **Kho lương** | 2 | như Chợ | không | Mỗi kho: giữ lại 10% tài nguyên khỏi bị cướp (quân cướp và quân xâm lược; tối đa 50%), giảm 2% lương thực nuôi quân và tướng |
| **Học quán** | 2 | 1 | 6 (≤ cấp thành) | Mỗi lượt mọi tướng và mưu sĩ +5 × cấp kinh nghiệm |
| **Y quán** | 2 | 1 | 6 (≤ cấp thành) | Tướng / mưu sĩ bị thương hồi gấp đôi (−2 lượt mỗi lượt); tổng tướng gục ngã ít chết hơn 4% × cấp; thua trận thì quân còn sống giữ 50% + 4% × cấp |
| **Quan phủ** | 3 | 1 | 6 (≤ cấp thành) | +4% × cấp sản lượng công trình khai thác (tối đa 24%) |
| **Sở cảnh sát** | 3 | 1 | 4 (≤ cấp thành − 2) | Chiêu mộ và cử đặc vụ (bên dưới); duy trì 2 lương thực, 2 gỗ, 2 đá |

Giới hạn số lượng tính từ cấp thành mở khóa công trình: +1 mỗi cấp thành **trên** cấp đó.

**Đặc vụ (Sở cảnh sát):**
- Bấm vào Sở cảnh sát: tab **Thông tin**, **Nâng cấp**, **Chiêu mộ đặc vụ**, **Đặc vụ**. Tab Tướng sĩ có nút **Đặc vụ** dưới danh sách tướng / mưu sĩ, mở thẳng tab Đặc vụ của Sở cảnh sát (chưa xây thì nút bị khóa và ghi lý do).
- Sở cảnh sát cấp N giữ được **N đặc vụ**. Ứng viên: 3 người, sao tới **cấp thành** (tỉ lệ như Chiêu hiền), đổi mới sau 5 lượt hoặc trả 20 lương thực để đổi ngay. Tuyển **trả một lần** 30 + 20 × sao lương thực và 10 × sao gỗ, **không có phí nuôi**. Đặc vụ không có trang bị, chỉ có tên, sao, cấp và kinh nghiệm. Có thể sa thải.
- **Cấp đặc vụ 1–10:** mỗi lượt làm nhiệm vụ +10 kinh nghiệm, lên cấp N cần 100 × N; cấp tối đa = 4 + số sao (1★ tới cấp 5, 6★ tới cấp 10).
- **Giao nhiệm vụ:** chọn đặc vụ đang rảnh → bản đồ chiến dịch mở ra → chọn một gia tộc bất kỳ chưa bị thôn tính (cả bản đồ, không cần gần) → bảng chọn nhiệm vụ. **Mỗi gia tộc chỉ nhận 1 đặc vụ** cùng lúc (nút Cử đặc vụ khóa với lý do "Đã có đặc vụ ở đây"). Trên bản đồ, bảng gia tộc cũng có nút **Cử đặc vụ**. Mỗi nhiệm vụ kéo dài **10 lượt**:
  - **Tăng quan hệ:** +cấp đặc vụ quan hệ mỗi lượt với gia tộc đó (cấp 1: +1 … cấp 10: +10), như quà tặng (mờ dần theo thời gian).
  - **Phá hoại:** quân gia tộc đó hồi chậm hơn: trừ thẳng vào mức hồi 10% của họ 1 / 1.5 / 2 / 2.5 / 3 / 3.5 / 4 / 4.5 / 5 / 6% theo cấp 1–10.
- **Bị lộ:** lượt đầu nhiệm vụ có **3%** bị lộ (Sở cảnh sát mỗi cấp trên 1 giảm 1%, thấp nhất 0.5%), **mỗi lượt ở lại thêm +1%** (lượt 10: 12%; sở cấp 4: 0.5% → 9.5%). Sống sót trọn 10 lượt: ~46% với sở cấp 1, ~60% với sở cấp 4. Không rút về sớm được. Bị lộ thì bị giết với tỉ lệ **40% − 5% × sao** (mất hẳn), không thì trốn về; nhiệm vụ dừng và quan hệ với gia tộc đó **−10**. Xong nhiệm vụ thì đặc vụ về, rảnh để giao việc mới. Gia tộc đặc vụ đang ở bị sáp nhập thì nhiệm vụ dừng ngay và đặc vụ về an toàn (không còn bị lộ, M14h).

### Tướng (M11d, đã chốt)

**Một tổng tướng cho cả đạo quân.** Vương quốc giữ tối đa **3 tướng** (đều tốn phí nuôi): một người làm **tổng tướng**, những người khác dự bị (thay khi tổng tướng bị thương hoặc tử trận). Có thể sa thải tướng (có xác nhận).

**Sao (1–6) và chỉ số:** mỗi tướng có **Võ lực** và **Thống suất** (mỗi chỉ số 1–10). Số sao quyết định **tổng điểm** hai chỉ số; tổng điểm và cách chia đều ngẫu nhiên (sao càng cao tổng càng cao, nhưng vẫn có may rủi).
- **Võ lực:** mỗi điểm **+3% tấn công cận chiến và xung phong** cho cả đạo quân.
- **Thống suất:** mỗi điểm **+0,4 sĩ khí** và **+2% phòng thủ** (cận chiến và giáp) cho cả đạo quân.
- Chỉ cộng cho quân của vương quốc, không cộng cho quân đồng minh gửi đến.

| Sao | Tổng Võ + Thống | Cận vệ | Giá tuyển | Phí nuôi/lượt |
|---|---|---|---|---|
| 1★ | 3–5 | 4 kỵ binh | 30 Lương thực, 20 Gỗ | 2 Lương thực |
| 2★ | 6–8 | 6 | 40 Lương thực, 20 Gỗ, 5 Ngựa | 3 Lương thực |
| 3★ | 9–11 | 7 | 60 Lương thực, 10 Khoáng sản, 10 Ngựa | 4 Lương thực |
| 4★ | 12–14 | 9 | 80 Lương thực, 20 Khoáng sản, 10 Gỗ cứng, 15 Ngựa | 5 Lương thực, 1 Khoáng sản |
| 5★ | 15–17 | 10 | 100 Lương thực, 35 Khoáng sản, 20 Gỗ cứng, 20 Ngựa | 6 Lương thực, 2 Khoáng sản |
| 6★ | 18–20 | 12 | 140 Lương thực, 50 Khoáng sản, 30 Gỗ cứng, 30 Ngựa | 8 Lương thực, 3 Khoáng sản |

**Đặc tính** (`data/traits/`): tướng từ **2★** có 1 đặc tính, **chỉ kích hoạt khi lãnh thổ đạt điều kiện**:

| Đặc tính | Điều kiện | Hiệu ứng |
|---|---|---|
| Thợ săn rừng | Từ 12 ô rừng | Cung thủ +25% sát thương bắn |
| Thiết kỵ | Từ 3 nông trại | Xung phong +30% |
| Giữ thành | Khi phòng thủ (cướp, xâm lược) | +2 sĩ khí, +10% phòng thủ |
| Sinh ra trên núi | Từ 10 ô đồi | +15% phòng thủ |
| Tướng đồn điền | Từ 15 ô ruộng | +1,5 sĩ khí |
| Tiên phong | Từ 3 doanh trại | Hàng đầu +15% tấn công cận chiến |

**Chiêu hiền:** bấm vào thành chính → tab **Chiêu hiền**: 3 ứng viên (tên, sao, Võ lực, Thống suất, đặc tính, giá). Số sao không vượt **cấp thành**; sao càng cao càng hiếm. Danh sách đổi sau mỗi **5 lượt**, hoặc trả **20 Lương thực** để đổi ngay. Tab **Tướng**: xem tướng, chọn tổng tướng, sa thải. Phí nuôi tướng trả cùng phí nuôi quân; thiếu lương thực thì quân đào ngũ trước.

**Trong trận:** tổng tướng ra trận cùng một **đơn vị cận vệ kỵ binh** riêng (cờ vàng), **đứng giữa, trước hàng đầu** của đội hình. Cận vệ mạnh như tướng trong Total War Three Kingdoms: chỉ số cao hơn hẳn lính thường, **mỗi cận vệ gây sát thương bằng 4 lính và cần 5 đòn mới ngã**, và còn mạnh thêm theo tướng (+5% tấn công mỗi điểm Võ lực, +5% phòng thủ mỗi điểm Thống suất, ngoài phần cộng cho cả quân). Loại lính có thêm 2 chỉ số chung cho việc này: sát thương mỗi lính và máu mỗi lính (lính thường = 1). Cận vệ **bị vỡ hoặc bị diệt → tướng ngã**: mọi đơn vị phe đó **−3 sĩ khí**. Sau trận: **30% tử trận, 70% bị thương nghỉ 3 lượt** (không ra trận; tướng dự bị không tự thay, người chơi chọn). Không có tổng tướng ra trận được thì quân đi đánh không tướng.

**Sự kiện tướng:**
- **Tướng lạc xin đầu quân:** tướng 1–3★, trả một ít lương thực để nhận (cần còn chỗ).
- **Hàng tướng xin quy thuận:** đầu lượt ngay sau khi sáp nhập một gia tộc, khả năng cao; tướng 3–5★.

### Kinh nghiệm và cấp (M11e, đã chốt)

**Đơn vị lính — 3 cấp:** **Tân binh** (0 XP) → **Cựu binh** (100 XP) → **Tinh nhuệ** (300 XP).

| Cấp | Cộng thêm |
|---|---|
| Tân binh | — |
| Cựu binh | +2 tấn công cận chiến (xạ thủ: +2 tấn công tầm xa), +2 phòng thủ cận chiến, +2 sĩ khí |
| Tinh nhuệ | +4 / +4 / +4 |

**Nhận XP:**
- **Trận đánh:** mỗi đơn vị còn sống sau trận (không vỡ) nhận **+20**, thêm **+2 mỗi lính địch nó hạ**, thêm **+20 nếu phe mình thắng**.
- **Huấn luyện:** có ít nhất 1 doanh trại thì mỗi lượt mọi đơn vị nhận **+10**, nhưng huấn luyện chỉ đưa tới **Cựu binh** (khoảng 10 lượt). **Tinh nhuệ** chỉ đạt được qua trận đánh. Miễn phí.

**Lính bổ sung pha loãng kinh nghiệm:** XP là trung bình mỗi lính, lính mới có 0 XP, nên khi thêm lính (bổ sung cuối lượt, sự kiện): XP mới = XP cũ × lính cũ / tổng lính. Đơn vị mất một nửa quân rồi bổ sung đầy còn khoảng nửa XP và có thể tụt cấp.

**Tướng:** bắt đầu ở **cấp 1**, cấp tối đa = **2 + số sao** (1★: cấp 3, 6★: cấp 8). Lên cấp tiếp theo cần **100 × cấp hiện tại** XP.
- Chỉ **tổng tướng ra trận** nhận XP: **+30** mỗi trận, **+30 nếu thắng**, **+5 mỗi lính địch cận vệ hạ**. Tướng ngã trong trận vẫn nhận XP nếu sống sót (bị thương). Tướng dự bị không lên cấp.
- Mỗi cấp được **1 điểm**; người chơi tự cộng vào **Võ lực** hoặc **Thống suất** trong tab Tướng. Điểm chưa dùng được giữ lại.

**Hiển thị:** tab Quân đội (ký hiệu cấp + thanh XP mỗi đơn vị), màn hình trận (ký hiệu cấp cạnh tên đơn vị), tab Tướng (cấp, thanh XP, nút cộng điểm). Báo cáo sau trận chưa ghi lên cấp; bố cục các tab sẽ gọn lại ở M12.

**Để sau:** quân gia tộc có cấp; **Thảo phạt đạo tặc** — icon đỏ hiện ở góc màn hình, cử 1 tướng, 1 mưu sĩ và vài đơn vị đi như một chuyến commission (kiểu mini game thảo phạt trong Dungeon Village của Kairosoft): cutscene màn hình ngang, một hàng quân xếp theo loại tiến từ trái sang phải, đánh qua từng ải tới khi chinh phục hết hoặc thua hết; nhận tài nguyên, kinh nghiệm, trang bị. Cách này cho tướng dự bị có việc làm.

### Mưu sĩ (M11f, đã chốt)

**Mưu sĩ:** tối đa **3**, tách riêng với tướng. Mỗi người có tên, **sao 1–6** và **3 chỉ số (1–10)**: **Nội chính**, **Ngoại giao**, **Mưu lược**. Tổng 3 chỉ số theo sao, khoảng 1,5 lần tổng của tướng cùng sao (1★: 5–7 … 6★: 27–30). Giá tuyển và phí nuôi như tướng cùng sao. Mưu sĩ không có đặc tính; bản sắc là **bộ mưu kế**.

**Chức vụ:** 3 chức, mỗi chức giao cho 1 mưu sĩ. Mưu sĩ chỉ có tác dụng khi đang giữ chức và không bị thương; chức dùng đúng chỉ số của nó.

| Chức | Chỉ số | Mỗi điểm |
|---|---|---|
| **Nội chính** | Nội chính | +2% sản lượng công trình khai thác (Kinh tế v2); −2% giá xây công trình và nâng cấp thành; −2% phí nuôi quân và tướng |
| **Ngoại giao** | Ngoại giao | Trao đổi tài nguyên có lợi hơn 2%; +3% khả năng gia tộc nhận hợp đồng, liên minh, bất tương xâm, nghị hòa; −4% mức cảnh giác của gia tộc (M16a, trước là 2% / 3%); +3% quan hệ nhận được khi tặng quà |
| **Quân sự** | Mưu lược | Ra trận cùng quân: +0,3 sĩ khí và +2% tấn công tầm xa cho quân của vương quốc; dùng mưu kế đầu trận |

Phần cộng và phần giảm của Nội chính làm tròn tới số nguyên gần nhất (ví dụ giảm 16% của 6 Gỗ = 1 Gỗ).

**Mưu kế:** mưu sĩ N sao có **N mưu kế khác nhau**, rút ngẫu nhiên khi tạo từ kho 8 mưu kế (xem được trước khi tuyển). Chỉ mưu sĩ giữ chức Quân sự dùng mưu kế. **Đầu trận, trước khi giáp chiến**, mỗi mưu kế tung xúc xắc riêng: tỉ lệ **25% + 3% mỗi điểm Mưu lược** (Mưu lược 10 → 55%). Sức mạnh cũng tăng theo Mưu lược (ML):

| Mưu kế | Hiệu ứng |
|---|---|
| Hỏa công | Đơn vị địch đông nhất mất 4% + 0,45% × ML lính (giảm ở M14i) |
| Mưa tên | Mọi đơn vị địch mất 2% + 0,3% × ML lính |
| Trống trận | Toàn quân mình +1 + 0,2 × ML sĩ khí |
| Phục binh | Toàn quân địch −1 − 0,2 × ML sĩ khí |
| Ly gián | Đơn vị địch đông nhất −2 − 0,4 × ML sĩ khí |
| Bày trận | Hàng đầu quân mình +5% + 1% × ML phòng thủ cận chiến |
| Khích tướng | Toàn quân mình +5% + 1% × ML tấn công cận chiến |
| Nghi binh | Xạ thủ địch −10% − 2% × ML tấn công tầm xa |

Màn hình trận hiện dòng chữ cho mỗi mưu kế thành công (ví dụ "Mưu sĩ X dùng Hỏa công!").

**Rủi ro:** mưu sĩ Quân sự đứng sau, không có cận vệ. Chỉ khi **thua trận**: 50% bị thương nghỉ 3 lượt (mất tác dụng chức). Không tử trận.

**Kinh nghiệm và cấp** (như tướng): bắt đầu cấp 1, tối đa 2 + sao, lên cấp tiếp theo cần 100 × cấp hiện tại; mỗi cấp 1 điểm, người chơi tự cộng vào một trong 3 chỉ số.
- Mưu sĩ giữ chức **Nội chính / Ngoại giao**: **+10 XP mỗi lượt** (chậm).
- Mưu sĩ giữ chức **Quân sự**: không nhận XP theo lượt; mỗi trận ra trận **+30**, **+30 nếu thắng** (sau này thêm Thảo phạt).

**Chiêu hiền:** danh sách vẫn **3 ứng viên chung cho cả tướng và mưu sĩ** (mỗi ứng viên 50% là mưu sĩ), sao theo cấp thành, đổi sau mỗi 5 lượt hoặc trả 20 Lương thực. Tuyển mưu sĩ cần còn chỗ (dưới 3 mưu sĩ).

**Giao diện:** bảng thành chính thêm tab **Mưu sĩ**: mỗi mưu sĩ có chức đang giữ, 3 chỉ số, cấp và kinh nghiệm, bộ mưu kế, nút giao chức (Nội chính / Ngoại giao / Quân sự; giao chức đang có người thì hai người đổi chỗ), nút cộng điểm, sa thải. Tab Chiêu hiền ghi rõ ứng viên là tướng hay mưu sĩ.

**Để sau:** gia tộc có mưu sĩ dùng mưu kế; sự kiện mưu sĩ xin đầu quân; mưu sĩ đi Thảo phạt.

### Lính và công trình quân sự mới (M13, đã chốt)

**Doanh trại có cấp** (tối đa 6, không vượt cấp thành; vẫn được xây nhiều cái để có thêm chỗ đơn vị). Bậc lính theo **Doanh trại cấp cao nhất** đang có:
- Cấp 1: Kiếm binh nông dân, Thương binh nông dân, Cung thủ nông dân (ba loại hiện có, đổi tên). **Bỏ điều kiện 3 ô rừng của Cung thủ.**
- Cấp 3: Kiếm sĩ tinh nhuệ, Thương binh tinh nhuệ, Cung thủ tinh nhuệ.
- Cấp 6: Kiếm vệ hoàng gia, Trường thương vệ binh, Cung thủ thiện xạ.

**4 công trình Quân sự mới:** xây **trên ô cỏ**, cần **thành cấp 3**, mỗi loại **1 cái**, **3 cấp**, cấp tối đa = cấp thành − 2 (thành 3 → cấp 1, thành 4 → cấp 2, thành 5 → cấp 3), như Xưởng rèn.

| Công trình | Cấp 1 | Cấp 2 | Cấp 3 |
|---|---|---|---|
| Chuồng ngựa chiến | Kỵ binh nhẹ (+ Doanh trại 1) | Kỵ binh thương (+ Doanh trại 3) | Kỵ binh nặng (+ Doanh trại 6) |
| Trại bắn tên | Nỏ binh nông dân (+ Doanh trại 1) | Nỏ binh chuyên nghiệp (+ Doanh trại 3) | Nỏ binh tinh nhuệ (+ Doanh trại 6) |
| Võ trường | Đao thuẫn binh nông dân (+ Doanh trại 1) | Đao thuẫn binh kỳ cựu (+ Doanh trại 3) | Đao thuẫn vệ binh tinh nhuệ (+ Doanh trại 6) |
| Học viện quân sự | Pháo binh nhẹ (+ Doanh trại 3) | Pháo binh nặng (+ Doanh trại 6) | Lính hỏa mai tinh nhuệ (+ Doanh trại 6 + Võ trường 3) |

**Hàng quân và vai trò:**
- **Hàng trước:** Kiếm binh (mạnh giáp lá cà, yếu khi bị xung kích), Thương binh (cùng hàng với Kiếm binh; **chống xung kích**: giảm sát thương xung kích nhận vào và đánh mạnh hơn vào kỵ binh), Kỵ binh (xung kích rất mạnh, đứng cùng hàng với cận vệ tướng; tốn Ngựa).
- **Hàng giữa:** Đao thuẫn binh (phòng thủ cận chiến và giáp cao, đỡ tên tốt, giữ đội hình).
- **Hàng sau:** Cung thủ; Nỏ binh (bắn chậm hơn, **xuyên giáp**: bỏ qua một phần Giáp mục tiêu, Cung thủ không có); Pháo binh (chỉ khai hỏa **1 lần đầu trận**, sát thương cực lớn, trúng mọi hàng; pháo nặng mạnh hơn pháo nhẹ); Lính hỏa mai (nã 1 phát cực mạnh đầu trận rồi **tiến lên cận chiến** như bộ binh công thủ toàn diện, cảm hứng Samurai Flintlock của Shogun 2).
- Bảng Tuyển lính vẫn chia theo hàng quân (Tất cả / Tiền tuyến / Hàng giữa / Hậu tuyến); loại chưa mở ghi rõ cần công trình nào cấp mấy.
- **Không nâng bậc** đơn vị đã tuyển: muốn lính mạnh hơn thì tuyển đơn vị mới.

**Số liệu ban đầu** (cận chiến / phòng thủ / giáp / xung kích / sĩ khí, bắn xa; chỉnh khi chơi thử):

| Lính | Lính/đơn vị | Chỉ số | Giá | Nuôi/lượt |
|---|---|---|---|---|
| Kiếm binh nông dân | 20 | 9/7/5/5/8 | 3 Lương, 1 Đá | 1 Lương |
| Thương binh nông dân | 20 | 6/9/4/3/7, chống xung kích 40% | 2 Lương, 2 Gỗ | 1 Lương |
| Cung thủ nông dân | 15 | 3/2/2/1/5, bắn 6 | 2 Lương, 3 Gỗ | 1 Lương |
| Kiếm sĩ tinh nhuệ | 20 | 12/9/7/6/10 | 5 Lương, 2 Đá, 1 Khoáng | 2 Lương |
| Thương binh tinh nhuệ | 20 | 8/12/6/4/9, chống 50% | 4 Lương, 3 Gỗ, 1 Khoáng | 2 Lương |
| Cung thủ tinh nhuệ | 15 | 4/3/3/1/7, bắn 8 | 4 Lương, 4 Gỗ, 1 Gỗ cứng | 2 Lương |
| Kiếm vệ hoàng gia | 20 | 15/11/9/7/13 | 8 Lương, 3 Đá, 3 Khoáng | 3 Lương |
| Trường thương vệ binh | 20 | 10/15/8/5/12, chống 60% | 7 Lương, 4 Gỗ, 3 Khoáng | 3 Lương |
| Cung thủ thiện xạ | 15 | 5/4/4/1/9, bắn 11 | 6 Lương, 4 Gỗ, 3 Gỗ cứng | 3 Lương |
| Kỵ binh nhẹ | 12 | 7/5/3/10/9 | 3 Lương, 3 Ngựa | 2 Lương |
| Kỵ binh thương | 12 | 8/6/5/14/10 | 4 Lương, 4 Ngựa, 1 Khoáng | 2 Lương |
| Kỵ binh nặng | 12 | 10/9/8/16/12 | 6 Lương, 5 Ngựa, 3 Khoáng | 3 Lương |
| Nỏ binh nông dân | 15 | 3/3/3/1/5, bắn 7, xuyên giáp 30% | 3 Lương, 3 Gỗ | 1 Lương |
| Nỏ binh chuyên nghiệp | 15 | 4/4/4/1/7, bắn 9, xuyên 40% | 4 Lương, 3 Gỗ, 2 Gỗ cứng | 2 Lương |
| Nỏ binh tinh nhuệ | 15 | 5/5/5/1/9, bắn 11, xuyên 50% | 6 Lương, 4 Gỗ, 3 Gỗ cứng | 3 Lương |
| Đao thuẫn binh nông dân | 20 | 7/11/9/3/9 | 3 Lương, 2 Gỗ, 1 Đá | 1 Lương |
| Đao thuẫn binh kỳ cựu | 20 | 9/13/11/4/11 | 5 Lương, 2 Gỗ, 2 Khoáng | 2 Lương |
| Đao thuẫn vệ binh tinh nhuệ | 20 | 11/15/13/5/13 | 7 Lương, 3 Gỗ, 3 Khoáng | 3 Lương |
| Pháo binh nhẹ | 8 | 2/2/2/0/6, 1 phát 25 trúng mọi hàng | 4 Lương, 4 Gỗ cứng, 3 Khoáng | 2 Lương |
| Pháo binh nặng | 8 | 2/3/3/0/7, 1 phát 40 trúng mọi hàng | 6 Lương, 6 Gỗ cứng, 5 Khoáng | 3 Lương |

M14i giảm sát thương pháo ~15%: sát thương mỗi lính pháo nhẹ 5 → 4,25, pháo nặng 7 → 6.
| Lính hỏa mai tinh nhuệ | 15 | 10/9/6/4/11, 1 phát 14 rồi cận chiến | 6 Lương, 2 Gỗ cứng, 4 Khoáng | 3 Lương |

Save cũ: đơn vị Kiếm sĩ / Thương binh / Cung thủ trở thành bậc nông dân (giữ nguyên chỉ số); Doanh trại đã có là cấp 1.

**Đã làm (M13):** Doanh trại đang nâng cấp không tính khi tuyển (như mọi công trình đang thi công). Bốn công trình mới xây mất 3 lượt, phí duy trì 1 Lương (+1 mỗi cấp). Nỏ nạp 7 giây (cung 5, thiện xạ 4,5). Pháo: mỗi khẩu đánh như 5 (nhẹ) / 7 (nặng) người. Thương binh đánh kỵ binh mạnh hơn đúng bằng tỉ lệ chống xung kích. Quân các lang tộc vẫn chỉ dùng bậc nông dân (để cân bằng ở M14).

**Tiện lợi (M13b, đã chốt):** bảng Tuyển lính chia theo loại (Tất cả / Kiếm / Thương / Đao thuẫn / Kỵ binh / Cung / Nỏ / Hỏa khí, nút xuống 2 hàng); tên lính tô màu theo bậc (nông dân nâu, tinh nhuệ bạc, hoàng gia vàng) ở bảng tuyển và tab Quân đội; loại chưa đủ công trình hiện mờ. Tên tướng và mưu sĩ tô màu theo sao như độ hiếm trang bị (1–2★ xám, 3★ xanh lá, 4★ xanh lam, 5★ tím, 6★ vàng); trong bảng thông tin tướng sĩ, phím ← → (hoặc hai nút ← → dưới chân dung, kèm số thứ tự, M14g) chuyển sang người trước / sau. Tự bổ sung quân giảm từ 25% xuống 10% mỗi lượt; quân lang tộc vẫn hồi +2 lính mỗi lượt.

**Bản đồ sinh động (M13c, đã chốt):** ô bản đồ 48 px (ô đất vẽ 24×24), công trình giữ cỡ 32 px đứng giữa ô nên quanh nó có lối đi. Trên các mép ô (khe giữa các công trình) có dân làng đi giữa thành chính và ruộng / xưởng gỗ / mỏ rồi vác lúa, gỗ, đá về; xe bò chở hàng từ mỏ và xưởng gỗ; lính tuần tra (1 tốp cho 3 đơn vị) từ doanh trại và công trình quân sự ra biên giới, mặc màu của bạn; ngựa quanh chuồng ngựa chiến và trang trại cấp 3; hươu ở rừng ngoài lãnh thổ; chim bay ngang. Mỗi công trình có một vòng animation nhỏ 4 khung (khói, cờ bay, lưỡi cưa, quặng lấp lánh, đầu ngựa, mũi tên bay vào bia, lửa lò rèn…), công trình đang xây có thợ gõ búa. Menu có nút "Hiệu ứng bản đồ: Bật/Tắt", lưu theo máy.

**Để sau:** công trình sản xuất trên ô cỏ (×2 sản lượng) khi có tài nguyên mới; công trình Hành chính (Sở cảnh sát, Quan phủ, Chính viện).

### Trang bị (M12e, đã chốt)

**Ô trang bị:** mỗi người 3 ô, món của tướng và của mưu sĩ khác nhau.

| | Tướng | Mưu sĩ |
|---|---|---|
| Vũ khí | +Võ lực; 5 loại: **Đao** (+cận chiến cận vệ), **Thương** (+xung kích), **Kiếm** (+phòng thủ), **Kích** (+cận chiến và xung kích, ít hơn), **Chùy** (đòn cận chiến bỏ qua một phần **Phòng thủ** địch) | Quạt / Bút: +Mưu lược |
| Giáp | Cận vệ thêm Phòng thủ và Giáp (đỡ cả cận chiến lẫn tên đạn), giảm khả năng tử trận | Áo bào: +Nội chính |
| Phụ kiện | +Thống suất | Ấn / Ngọc bội: +Ngoại giao |

Trong trận chỉ cận vệ nhận phần thêm theo loại vũ khí; Võ lực / Thống suất vẫn có tác dụng như cũ (§8 Tướng).

**Độ hiếm** (màu viền ô và icon):

| Bậc | Màu | Chỉ số chính | Hiệu ứng |
|---|---|---|---|
| Thường | xám | +1 | — |
| Tốt | xanh lá | +2 | — |
| Hiếm | xanh dương, họa tiết nhỏ | +3 | 1 |
| Sử thi | tím, họa tiết vừa | +4 | 2 |
| Huyền thoại | vàng, họa tiết nhiều | +6 | 2 hiệu ứng mạnh |

- Hiệu ứng lấy ngẫu nhiên trong bộ của tướng (+2 sĩ khí toàn quân, +10% sát thương cận vệ, +3% cận chiến / phòng thủ toàn quân, −8% khả năng tử trận, +25% kinh nghiệm) hoặc của mưu sĩ (+5% tỉ lệ mưu kế khi giữ Quân sự; +3% sản lượng, −3% giá xây, −3% phí nuôi khi giữ Nội chính; +15% quan hệ khi tặng quà khi giữ Ngoại giao; +25% kinh nghiệm). Hiệu ứng của món Huyền thoại ×2. Giáp tướng: mỗi điểm +5% phòng thủ cận vệ và −3% khả năng tử trận (tối thiểu 5%). Vũ khí tướng, mỗi điểm: Đao +4% cận chiến cận vệ, Thương +6% xung kích, Kiếm +4% phòng thủ, Kích +2% cận chiến và +3% xung kích, Chùy bỏ qua 3% phòng thủ địch.
- **Huyền thoại** là món có tên, hiệu ứng cố định, **mỗi món chỉ có 1 trong một ván**: Thanh long đao, Đồ long đao, Trượng bát xà mâu, Phương thiên họa kích, Ỷ thiên kiếm, Bát qua chùy…, và vài món cho mưu sĩ (quạt lông, sách binh pháp, ấn ngọc).

**Nguồn trang bị:**
- **Xưởng rèn khí giới** (công trình Quân sự, cần thành **cấp 3**, tối đa **1 xưởng**, không tăng theo cấp thành). Nâng cấp xưởng tối đa bằng cấp thành − 2 (thành 3 → xưởng 1 … thành 6 → xưởng 4). Bấm vào xưởng: chọn loại món (vũ khí / giáp / phụ kiện, cho tướng hay mưu sĩ), trả Khoáng sản + Gỗ cứng, **2 lượt** sau ra 1 món. Mỗi lúc rèn 1 món; đang rèn thì không nâng cấp xưởng, mất xưởng thì mất món đang rèn. Giá 6 Khoáng sản + 6 Gỗ cứng, +2 mỗi cấp xưởng. Xưởng chỉ ra tới **Sử thi**; tỉ lệ Thường / Tốt / Hiếm / Sử thi: cấp 1 55/30/13/2, cấp 2 40/35/20/5, cấp 3 25/37/28/10, cấp 4 15/33/35/17.
- **Chiến lợi phẩm:** đi đánh thắng 35% rơi đồ (Thường 30, Tốt 30, Hiếm 22, Sử thi 13, Huyền thoại 5), phòng thủ thắng 12% (50/30/15/5/0); Huyền thoại chỉ có ở đây, ở sự kiện và sau này ở mini game Thảo phạt đạo tặc, tỉ lệ thấp.
- **Sự kiện:** vài sự kiện mới tặng đồ.

**Kho đồ:** chung, tối đa **20 món** (xem ở tab Trang bị). Món đang ở trên người khác cùng loại (tướng / mưu sĩ) cũng hiện trong danh sách, kèm mặt và tóm tắt người đó, nút **Đổi** (món người hiện tại đang đeo ở ô đó chuyển sang người kia). Bảng tướng sĩ giữ một kích thước cố định; nội dung dài thì cuộn. Mỗi lượt mới bảng bên phải quay về tab Đất. Sa thải thì đồ đang đeo về kho; **tử trận thì mất luôn đồ đang đeo**. Phân rã món không cần để lấy lại một ít Khoáng sản / Gỗ cứng. Tab Trang bị có nút **Đến xưởng rèn** (M14h): mở ngay tab Rèn của Xưởng rèn, chọn sẵn loại (tướng / mưu sĩ) và ô đang xem; chưa có xưởng thì nút khóa kèm lý do.

**Khung chân dung theo sao** (vẽ lại, hào nhoáng hơn; ô trang bị dùng cùng kiểu theo độ hiếm): 1–2★ đồng · 3★ xanh lá · 4★ xanh dương, họa tiết nhỏ · 5★ tím, họa tiết vừa · 6★ vàng, họa tiết nhiều.

**Hình ảnh:** mỗi món một icon pixel. Tổng tướng ra trận cầm đúng loại vũ khí đang đeo (chưa đeo: kiếm thường). Sửa luôn: cổ và đầu ngựa của tổng tướng quá to / dài; vũ khí của lính bị cắt mất đầu (mũi giáo…) ở frame đâm thứ 2.

## 9. Bản đồ thế giới & ngoại giao

- Thêm tab/nút **Ngoại giao**. Bấm vào thì mở một màn hình bản đồ lớn: vương quốc của mình ở một vị trí, các gia tộc / vương quốc xung quanh hiển thị quanh đó.
- Với mỗi gia tộc: xem quan hệ, giao thương (trao đổi tài nguyên), kết liên minh, tuyên chiến.
- Quan hệ xấu thì gia tộc đó có thể gửi quân xâm lược (§7.3). Người chơi cũng có thể đem quân đánh họ.
- Mỗi gia tộc nằm ở một hướng so với vương quốc của mình, quyết định cạnh nào của bản đồ vương quốc bị mất đất khi thua.

**Thế giới làm sẵn** (đã chốt) (khoảng 5–6 gia tộc, mỗi gia tộc một file dữ liệu: tên, vị trí, tính cách, sức mạnh, quan hệ ban đầu). Lý do:
- Dễ cân bằng và dễ viết sự kiện / cốt truyện cho từng gia tộc.
- Ít việc hơn nhiều so với một bộ sinh bản đồ ngẫu nhiên (sông, biển, địa lý…).
- Vì gia tộc là dữ liệu, sau này vẫn có thể thêm chế độ sinh ngẫu nhiên ra các file đó mà không phải viết lại hệ thống.

Biển, sông: chưa làm, để sau.

### 9.1 Bản đồ thế giới (M8)

- Nút **Ngoại giao** trên thanh trên cùng mở màn hình bản đồ thế giới (toàn màn hình).
- Bản đồ dạng **điểm vùng nối đường**: vương quốc ở giữa, mỗi gia tộc là một điểm, có đường nối giữa các vùng giáp nhau.
- Chạm vào một gia tộc → bảng bên phải: mô tả, tính cách, sức mạnh, hướng, quan hệ, tài nguyên dư/thiếu, và các hành động.
- **Bảng lệnh kiểu Shogun 2** (chốt sau M9b): thanh bên phải chỉ có phần tóm tắt và **mỗi lệnh một nút** (Trao đổi · Tặng quà · Hợp đồng giao thương · Liên minh · Bất tương xâm · Tuyên chiến; khi đang chiến tranh: Tấn công · Nghị hòa · Tặng quà, các lệnh hòa bình bị ẩn). Nút không dùng được thì mờ đi, lý do ghi ngay dưới.
- Bấm một nút → **bảng riêng giữa màn hình** (bản đồ mờ phía sau) để chỉnh chi tiết, xem trước kết quả / khả năng đồng ý rồi mới xác nhận. Bảng nào dùng tài nguyên (trao đổi, tặng quà, hợp đồng, nghị hòa) hiện luôn **kho tài nguyên hiện có**. Tuyên chiến liệt kê hết hậu quả; Tấn công cho xem trước quân hai bên (cả đồng minh và bạn của đối phương).

### 9.2 Gia tộc (tên tạm, sửa trong `data/clans/`)

| Gia tộc | Vị trí | Tính cách | Dư | Thiếu | Quan hệ đầu / gốc |
|---|---|---|---|---|---|
| Lang Tộc Phương Bắc | Bắc (giáp biên) | Hiếu chiến | Đá | Lương thực | −10 / −15 |
| Thương Hội Đông Hải | Đông (giáp biên) | Thương nhân | Lương thực | Gỗ | 10 / 20 |
| Điền Trang Nam Lâm | Nam (giáp biên) | Ôn hòa | Gỗ | Đá | 20 / 30 |
| Hắc Sơn Bảo | Tây (giáp biên) | Cô lập | Đá | Lương thực | −5 / 0 |
| Vương Quốc Kim Ưng | Xa, Đông Bắc | Hiếu chiến | Đá | Gỗ | 0 / −5 |
| Bộ Lạc Thảo Nguyên | Xa, Tây Nam | Ôn hòa | Lương thực | Đá | 0 / 10 |

Gia tộc giáp biên có hướng (Bắc/Đông/Nam/Tây) để M9 biết mất đất ở cạnh nào. Gia tộc ở xa chỉ giao thương (giá kém hơn).

### 9.3 Quan hệ

Thang −100 → +100:

| Mức | Khoảng |
|---|---|
| Thù địch | ≤ −60 |
| Căng thẳng | −59 → −20 |
| Trung lập | −19 → 19 |
| Thân thiện | 20 → 59 |
| Thân thiết | ≥ 60 |

**Quan hệ = tổng các yếu tố** (kiểu Total War, đã chốt sau khi chơi thử M9b). Người chơi luôn xem được từng yếu tố, và chúng cộng lại đúng bằng con số trên thanh:
- **Yếu tố lâu dài:**
  - Thiện cảm gốc (mức gốc trong file gia tộc).
  - E dè vương quốc lớn mạnh (trừ).
  - Đang có hợp đồng dài hạn +15.
  - Đang liên minh +30.
  - Đang có hiệp ước bất tương xâm +10.
- **Sự kiện gần đây**, ghi riêng theo nguồn: ấn tượng ban đầu (quan hệ đầu − mức gốc), quà tặng, giao thương, chuyện hợp đồng, chiến tranh với vương quốc, vương quốc gây chiến với gia tộc khác, trận đánh chung, bị hủy liên minh. Mỗi nguồn **mờ dần về 0** mỗi lượt (ôn hòa / thương nhân 2 điểm, hiếu chiến 3, cô lập 1).
- **E dè** = Uy hiếp × hệ số (hiếu chiến ×1.0, cô lập ×0.8, ôn hòa ×0.5, thương nhân ×0.4). Không áp ngay mà **tăng dần** tới mức đó, mỗi lượt cùng số điểm như trên (giảm dần khi Uy hiếp giảm).
- **Uy hiếp** của vương quốc = (số ô lãnh thổ − 16) / 4 + 15 × số gia tộc đã sáp nhập + số lính / 20. Vương quốc càng lớn mạnh, các gia tộc càng e dè.
- Tổng bị giới hạn −100 → 100. Mỗi thay đổi dịch đúng con số đang hiển thị (phần vượt giới hạn bị bỏ, không nằm ẩn).
- Bảng gia tộc hiện quan hệ, mức "về lâu dài" (khi mọi sự kiện đã mờ hết và e dè đã đủ), nút **Chi tiết quan hệ** (chạm để mở) liệt kê phần cộng và phần trừ; rê chuột vào thanh quan hệ cũng hiện bảng đó.
- **Tặng quà:** mỗi 5 giá trị tài nguyên = +1 quan hệ, nhân theo tính cách (ôn hòa ×1.5, thương nhân ×1, hiếu chiến ×0.6, cô lập ×0.5); tối đa +15 mỗi lượt cho mỗi gia tộc.
- Mỗi lần trao đổi: +1 quan hệ (tối đa +3 mỗi lượt).
- "Đồng minh" là hiệp ước riêng (§9.7), không phải một mức quan hệ.

### 9.4 Trao đổi tài nguyên

- Giá trị: lương thực 1, gỗ 1, đá 2.
- Đưa X, nhận Y: số nhận = số đưa × giá trị(X) / giá trị(Y) × hệ số giá.
- Hệ số giá = 0.6 + quan hệ/100 × 0.2, +0.15 nếu là thương nhân, ×1.4 nếu X là thứ họ **thiếu**, ×1.3 nếu Y là thứ họ **dư**, ×0.85 nếu ở xa.
- Mỗi gia tộc chỉ nhận tối đa 40 giá trị hàng mỗi lượt (chống mua đi bán lại vô hạn).
- Quan hệ Căng thẳng trở xuống: từ chối giao thương.

### 9.5 Hợp đồng giao thương dài hạn

- Người chơi đề nghị: **đưa** X mỗi lượt, **nhận** Y mỗi lượt, trong **N lượt** (5–30, người chơi chọn). Giá trị hàng đưa tối đa 30 mỗi lượt. Mỗi gia tộc tối đa 1 hợp đồng.
- **Thương thảo (kiểu Shogun 2):** trước khi gửi, hiện khả năng đồng ý.
  - Khả năng = 1.5 − (Y đòi / Y công bằng) + quan hệ/200 + tính cách (thương nhân +0.15, ôn hòa +0.05, hiếu chiến −0.1, cô lập −0.2), giới hạn 0 → 95%. "Y công bằng" là số họ sẽ trả cho X theo giá trao đổi một lần (§9.4).
  - Mức: Rất có thể (≥80%), Có thể (≥55%), Khó (≥30%), Rất khó (>0), Không thể.
  - Gia tộc từ chối khi quan hệ Căng thẳng trở xuống. Bị từ chối → phải đợi lượt sau mới đề nghị lại với gia tộc đó.
- **Ký:** quan hệ +8 ngay (sự kiện, mờ dần), và +15 suốt thời gian hợp đồng còn chạy (§9.3). Mỗi lượt (lúc kết thúc lượt): đưa X, nhận Y, quan hệ +1.
- **Thiếu hàng để giao:** lượt đó bỏ qua, quan hệ −3.
- **Hết hạn:** quan hệ +3 (và mất +15 của hợp đồng). **Người chơi hủy:** quan hệ −20. **Quan hệ xuống Thù địch:** gia tộc tự hủy.

### 9.6 Chiến tranh (M9)

**Trạng thái:** mỗi gia tộc ở **Hòa bình** hoặc **Chiến tranh** với vương quốc.

**Sức mạnh quân sự** = số lính của gia tộc (tối đa = giá trị trong file dữ liệu). Hồi 2 lính mỗi lượt tới mức tối đa. Quân của gia tộc dùng các loại lính như người chơi, theo tỉ lệ `army_units` trong file gia tộc.

**Bắt đầu chiến tranh:**
- Người chơi **tuyên chiến** (nút trên bản đồ thế giới, bấm 2 lần): quan hệ với họ xuống Thù địch, các gia tộc khác −5.
- Gia tộc tự tuyên chiến khi quan hệ **Thù địch**, mỗi lượt có khả năng: hiếu chiến 15%, cô lập 5%, thương nhân 5%, ôn hòa 2%. Gia tộc **hiếu chiến** còn có thể tuyên chiến từ mức **Căng thẳng** (5% mỗi lượt).
- Chỉ gia tộc **giáp biên** mới đánh nhau được. Chiến tranh nổ ra thì hợp đồng giao thương với họ tự hủy.

**Quân xâm lược (họ đánh mình):** khi đang chiến tranh, mỗi lượt 25% khả năng (cách lần trước ít nhất 3 lượt), họ đem **60% quân** tới. Trận đánh như đánh cướp (màn hình trận, có rút lui).
- Thua: luật thua chung (§7.6), **mất tối đa 6 ô lãnh thổ gần cạnh phía họ nhất** (ô thành đất hoang, công trình trên đó bị phá, thành chính không bao giờ mất) và **bị cướp phá 40%** mỗi loại tài nguyên (nặng hơn cướp: 30%).
- Thắng: họ mất số lính tử trận.

**Đi xâm lược (mình đánh họ):** nút **Tấn công** trên bản đồ thế giới, khi đang chiến tranh, 1 lần mỗi lượt. Toàn bộ quân tham chiến; họ phòng thủ bằng toàn bộ quân.
- Thắng: mỗi lính địch tử trận = +1 lương thực, +1 gỗ, +1 đá chiến lợi phẩm.
- Thua: **mất toàn bộ quân** (rút lui thì đơn vị chưa vỡ giữ 50%) và **bồi thường 25%** mỗi loại tài nguyên.

**Sáp nhập:** khi người chơi thắng và sức mạnh của họ còn dưới 15% tối đa, họ đầu hàng:
- Gia tộc bị sáp nhập (không còn giao thiệp).
- **Bản đồ vương quốc nới rộng thêm 2 hàng/cột đất hoang về phía họ** (ví dụ 12×12 → 12×14; trước là 4, giảm để đất không dư thừa). Đất hoang vẽ màu ô liu nhạt và bản đồ có viền mép để thấy rõ phần mới. Người chơi tự đặt mảnh đất để chiếm.
- Gia tộc ở xa có đường nối với họ trở thành **láng giềng mới cùng hướng** đó.

**Nghị hòa:** thương thảo như hợp đồng, hiện khả năng đồng ý:
- Khả năng = 0.1 + 0.8 × (tỉ lệ quân họ đã mất) + quan hệ/200 + giá trị bồi thường/100, tối đa 95%. Mỗi lượt đề nghị 1 lần.
- Hòa xong: quan hệ ít nhất −30 (Căng thẳng), **đình chiến 10 lượt** (không bên nào tuyên chiến lại).

### 9.7 Liên minh & bất tương xâm (M9b)

**Bạn bè giữa các gia tộc** (cố định trong dữ liệu, `friends` trong `data/clans/`, luôn hai chiều):

| Gia tộc | Bạn |
|---|---|
| Lang Tộc Phương Bắc | Vương Quốc Kim Ưng |
| Vương Quốc Kim Ưng | Lang Tộc Phương Bắc, Thương Hội Đông Hải |
| Thương Hội Đông Hải | Vương Quốc Kim Ưng |
| Hắc Sơn Bảo | Bộ Lạc Thảo Nguyên |
| Bộ Lạc Thảo Nguyên | Hắc Sơn Bảo, Điền Trang Nam Lâm |
| Điền Trang Nam Lâm | Bộ Lạc Thảo Nguyên |

**Liên minh:**
- Chỉ đề nghị được khi quan hệ **Thân thiết (≥ 60)** và không chiến tranh. Hiện khả năng đồng ý trước khi gửi:
  - Khả năng = 0.3 + (quan hệ − 60) / 80 + tính cách (như hợp đồng: thương nhân +0.15, ôn hòa +0.05, hiếu chiến −0.1, cô lập −0.2) − Uy hiếp / 200, giới hạn 0 → 95%.
  - Bị từ chối → **3 lượt** sau mới đề nghị lại được.
- Thời hạn **20 lượt**. Trong **5 lượt cuối** có thể **gia hạn** thêm 20 lượt (lại tính khả năng đồng ý). Hết hạn thì phải ký lại từ đầu.
- Khi đang liên minh, **quan hệ +30** ngay (yếu tố lâu dài, §9.3); hết liên minh thì mất +30 ngay. Uy hiếp vẫn tác động.
- Quan hệ tụt xuống dưới **Thân thiện (< 20)** → liên minh tự tan. Người chơi chủ động hủy → quan hệ **−30**.

**Đồng minh gửi quân:**
- Vào mọi trận của vương quốc: bị cướp, bị xâm lược, đi đánh. Mỗi đồng minh gửi **30% sức mạnh hiện có** (cùng loại lính theo `army_units`), đứng chung phe người chơi, vẽ màu cờ của họ.
- Không gửi nếu sức mạnh của họ dưới 30% tối đa, hoặc kẻ địch là **bạn** của họ.
- Lính đồng minh chết hay mất khi thua thì sức mạnh của đồng minh giảm thật (luật thua chung §7.6, không chịu luật "mất toàn bộ quân" khi đi đánh thua), rồi hồi dần như thường.
- Thắng trận chung: quan hệ **+5**. Thua: **−10**.

**Hiệp ước bất tương xâm:**
- Ký được khi quan hệ **Thân thiện (≥ 20)** trở lên và không chiến tranh, luôn được đồng ý. Kéo dài **10 lượt**, hết hạn thì ký lại.
- Đang có hiệp ước: **quan hệ +10** (yếu tố lâu dài, §9.3); hết hạn hoặc bị phá thì mất +10 ngay.
- Trong thời gian đó gia tộc **không tuyên chiến** với vương quốc, dù quan hệ có tụt. Có thể ký cùng lúc với liên minh (đồng minh vẫn gửi quân như thường).

**Khi bạn đánh một gia tộc:**
- Bạn của họ gửi **30% quân** sang giúp họ phòng thủ (cùng điều kiện ≥ 30% sức mạnh), trừ khi người bạn đó là đồng minh của bạn hoặc đang có bất tương xâm với bạn. Lính họ mất cũng trừ vào sức mạnh của họ.
- Người chơi tuyên chiến: bạn của mục tiêu **−15** quan hệ (thay cho −5 như các gia tộc khác).
- **Phá hiệp ước:** tuyên chiến với đồng minh → liên minh tan, mọi gia tộc khác thêm **−20**. Tuyên chiến khi đang bất tương xâm → hiệp ước mất, mọi gia tộc khác thêm **−10**.
- Chiến tranh nổ ra (bất kể bên nào tuyên chiến) thì liên minh và bất tương xâm với gia tộc đó mất.

### 9.8 Ý tưởng ngoại giao để sau

- Tăng độ khó: gia tộc hồi quân nhanh hơn / mạnh dần theo thời gian, quân xâm lược đông hơn ở giai đoạn sau.

- Kết thông gia (quan hệ tăng lâu dài, cần tướng/người trong gia đình — M11).
- Yêu sách / cống nạp: gia tộc mạnh đòi nộp tài nguyên mỗi lượt, từ chối thì quan hệ giảm và dễ bị xâm lược; người chơi mạnh cũng có thể đòi lại.
- Mượn đường quân sự (đánh gia tộc ở xa qua đất láng giềng — M9).
- Sự kiện ngoại giao ngẫu nhiên: sứ giả đến, gia tộc gặp nạn đói xin viện trợ, hai gia tộc gây chiến với nhau…

## 9b. Thắng / thua (M11a, đã chốt)

Không giới hạn số lượt: chơi tới khi thắng hoặc thua.

**Hai đường chiến thắng** (đạt đường nào trước cũng được; chốt lại sau khi chơi thử, gộp ngoại giao với kinh tế):

| Đường | Điều kiện |
|---|---|
| **Chinh phục** | Sáp nhập mọi gia tộc. Thắng ngay khi gia tộc cuối cùng đầu hàng. |
| **Hòa bình thịnh vượng** | Cùng lúc: mọi gia tộc chưa bị sáp nhập đều đang là đồng minh (**ít nhất 1** đồng minh), **từ 120 ô lãnh thổ**, thu nhập ròng (sau nuôi quân, phí công trình, hợp đồng) **từ +50 mỗi loại tài nguyên cơ bản (lương thực, gỗ, đá) mỗi lượt**; giữ như vậy **10 lượt liền**. |

Các con số sẽ cân bằng lại sau.

- Bộ đếm "giữ liền" tăng ở cuối mỗi lượt khi điều kiện đang đúng, và về 0 ngay khi điều kiện sai.
- Thắng → **màn chiến thắng** với thống kê (số lượt, lãnh thổ, số lính, trận thắng/thua, gia tộc sáp nhập / đồng minh). Chọn **Chơi tiếp** (ván tiếp tục, không báo thắng lại) hoặc **Về menu chính**.

**Thất bại: thành chính thất thủ.** Thua một trận xâm lược khi vương quốc **không còn ô đất nào ngoài thành chính** thì thành chính bị chiếm và ván kết thúc. Màn thất bại có **Tải game** và **Về menu chính**. Khi chỉ còn từ 6 ô đất trở xuống ngoài thành chính, bảng Mục tiêu và thông báo cuối lượt cảnh báo.

**Theo dõi:** nút **Mục tiêu** trên thanh trên cùng mở bảng giữa màn hình (2 cột). Mỗi đường chiến thắng có thanh tiến độ, từng điều kiện kèm số hiện tại / số cần (ví dụ "Lãnh thổ 72/120"), và số lượt đã giữ ("Đã giữ 4/10 lượt"). Bảng có cả mục cảnh báo thành chính.

Thống kê trận thắng/thua và trạng thái thắng/thua được lưu cùng ván (§10.1).

**Để sau:** bản đồ sẽ có thêm nhiều gia tộc, và khi bắt đầu ván người chơi chọn một trong vài gia tộc để chơi. Điều kiện thắng sẽ được chỉnh lại cho khó hơn lúc đó (code đã tính theo số gia tộc thực tế, không cố định 6).

## 9c. Sự kiện ngẫu nhiên (M11b, đã chốt)

**Xuất hiện:** đầu mỗi lượt, từ lượt 3, sau trận đánh đầu lượt (nếu có). Số sự kiện mỗi lượt:

| Số sự kiện | Khả năng |
|---|---|
| 0 | 50% |
| 1 | 30% |
| 2 | 15% |
| 3 | 5% |

- Mỗi sự kiện có **trọng số** và **thời gian nghỉ** riêng (ví dụ được mùa không lặp lại trong 8 lượt). Một lượt không ra 2 lần cùng một sự kiện.
- Mỗi sự kiện có **điều kiện** ghi trong dữ liệu (`data/events/*.tres`): lượt tối thiểu, kho tài nguyên, có công trình, có quân, đang chiến tranh, có đồng minh, có gia tộc ở mức quan hệ phù hợp, vừa đánh thắng cướp ở lượt trước… Sự kiện ngoại giao tự chọn một gia tộc phù hợp. Thêm sự kiện mới chỉ cần thêm file.
- Sự kiện hiện lần lượt ở **bảng giữa màn hình**, phải chọn mới đi tiếp. Sự kiện chưa giải quyết được lưu cùng ván (tải lại vẫn còn).

**Lựa chọn, hậu quả ẩn một phần:** mỗi sự kiện có 1–3 lựa chọn.
- **Cái giá** (tài nguyên bỏ ra) luôn hiện rõ; không đủ thì lựa chọn bị khóa.
- **Kết quả** chỉ ghi gợi ý; có thể ngẫu nhiên giữa vài kết quả. Chọn xong mới hiện kết quả thật và danh sách thay đổi.
- Hậu quả có thể là: được/mất tài nguyên (số cố định hoặc phần trăm), quan hệ với một gia tộc hoặc mọi gia tộc (nguồn "Sự kiện" trong chi tiết quan hệ, mờ dần), thêm đơn vị lính, mất một phần lính, bổ sung quân, thêm mảnh đất vào tay, gia tộc mạnh/yếu đi, gia tộc tuyên chiến.

**Bộ sự kiện đầu tiên:**
- Kinh tế: được mùa, sâu bệnh mất mùa, thương nhân lạ, cháy kho gỗ, phát hiện mạch đá.
- Ngoại giao: gia tộc gặp nạn đói xin viện trợ, sứ giả mang quà, gia tộc mạnh đòi cống nạp, đồng minh nhờ giúp.
- Quân sự: người tình nguyện đầu quân, lính đòi tăng lương, dịch bệnh trong doanh trại, bọn cướp bị bắt xin tha (chỉ khi lượt trước vừa đánh thắng cướp).
- Việc trong vương quốc: lễ hội mùa, nông dân xin khai hoang, thầy thuốc ghé qua.

**Để sau (cần tướng, quân sư):** chiêu mộ tướng / quân sư của gia tộc vừa bị đánh bại; nhặt được trang bị tốt (chỉ tướng và quân sư dùng được).

## 10. Quyết định kỹ thuật

| Vấn đề | Quyết định |
|---|---|
| Dữ liệu tĩnh (địa hình, mảnh, đơn vị, công trình) | `Resource` (`.tres`) trong `data/`, nạp theo thư mục |
| Trạng thái ván chơi | Lớp `RefCounted` thuần logic (`BoardData`, …), không phụ thuộc Node |
| Hiển thị | Node riêng (`BoardView`, …) chỉ đọc dữ liệu, không tự sửa |
| Lưu game | JSON có trường `save_version`; **không** dùng `ResourceSaver`/`.tres` cho file save |
| Kiểm thử | Script headless tự viết trong `tests/`, không dùng thư viện ngoài |
| Độ phân giải | Khung thiết kế 1280×720, cửa sổ mặc định 1920×1080 (phóng to tự động, chữ vẫn nét), `stretch = canvas_items`, `aspect = expand` để vừa mọi tỉ lệ màn hình |
| Nền tảng | Windows trước; **Android (APK)** sau. Renderer GL Compatibility hợp với Android. Giao diện mới không được chỉ dựa vào rê chuột hay phím tắt |
| Tên lớp | Tránh trùng lớp có sẵn của Godot (ví dụ dùng `CellData`, không dùng `TileData`) |

### 10.1 Lưu / tải (M10, đã chốt)

- **Ô lưu:** 1 ô **Tự động** + **3 ô lưu tay**. Mỗi ô hiện: lượt, số ô lãnh thổ, số lính, ngày giờ lưu.
- **Tự động lưu** mỗi khi sang lượt mới, sau khi trận đánh đầu lượt (nếu có) đã xong; và lúc bắt đầu ván mới.
- **Lưu tay bất cứ lúc nào ở màn vương quốc**, kể cả giữa lượt: giữ nguyên mảnh đất trên tay, tài nguyên, giới hạn quà / giao thương / đề nghị của lượt. Không lưu được khi đang xem trận đánh hay đang mở bản đồ thế giới. Ghi đè ô đã có phải bấm 2 lần.
- **Tải lại thì gieo lại ngẫu nhiên:** mảnh đất đang trên tay giữ nguyên, nhưng các mảnh sau, cướp, xâm lược, gia tộc đồng ý hay không đều ra kết quả mới.
- **Menu chính** khi mở game: Tiếp tục (bản lưu mới nhất) · Ván mới · Tải game · **Cách chơi** · **Giới thiệu** (M14c) · Cài đặt · Thoát; góc dưới phải ghi phiên bản ("v0.1 Early Access"). Phía sau là **cảnh nền chạy mờ** (M14j, kiểu Kairosoft): một trận đánh gia tộc và một ải thảo phạt chiếu luân phiên, do một vương quốc dựng tạm đánh (đạo quân, tướng, mưu sĩ ngẫu nhiên; không lưu gì). Cảnh rộng gấp 1,8 lần màn hình, camera **lia chậm qua lại** (18 giây mỗi chiều) để giao tranh lộ ra hai bên bảng menu; làm mờ, tối nhẹ, không có tiếng, không chữ; trận nền chạy x2; hết cảnh chờ 2 giây rồi mờ dần sang cảnh kia. Trong ván: nút **Menu** trên thanh trên cùng → Tiếp tục chơi · Lưu game · Tải game · Về menu chính.
- **Kỹ thuật:**
  - File JSON trong `user://saves/` (`auto.json`, `slot_1.json`…), ghi ra file tạm rồi mới đổi tên để không hỏng file cũ khi game tắt giữa chừng.
  - Mỗi file có `save_version`. Bản cũ hơn được nâng cấp từng bước (`v1 → v2 → …`) khi tải. Bản mới hơn phiên bản game thì báo lỗi, không tải.
  - Chỉ lưu trạng thái ván. Dữ liệu tĩnh (địa hình, lính, gia tộc…) đọc lại từ `data/`. Gia tộc hay loại lính không còn trong dữ liệu thì bỏ qua; gia tộc mới thêm vào dữ liệu thì dùng giá trị ban đầu.

### 10.2 Cảm ứng và Android (để cuối dự án, M15)

**Chốt sau khi chơi thử trên điện thoại:** hoàn thiện bản máy tính trước, bản điện thoại làm sau cùng. Toàn bộ phần cảm ứng và Android dưới đây nằm sẵn trên nhánh `m13/touch-apk` (chưa merge); tới M15 cập nhật nhánh đó theo main rồi làm tiếp. Bản máy tính chỉ lấy các phần dùng tốt với chuột (M12f):
- Bấm lên bản đồ là đặt / xây / chuyển ngay như cũ (rê chuột xem trước); kéo chuột trái (hoặc phải / giữa) để cuộn bản đồ, con lăn hoặc chụm trên touchpad để zoom.
- Bấm một ô trống thì khung thông tin giữ ô đó (viền vàng); bấm khung để thu gọn.
- Bấm một tài nguyên trên thanh gỗ mở bảng thu / chi (ngoài tooltip khi rê chuột).
- Kéo trên bất kỳ danh sách nào để cuộn, kể cả khi bắt đầu trên nút hay thẻ; kéo xong không bị tính là bấm. Dòng tướng sĩ mở khi thả chuột trên dòng.
- Cửa sổ và menu tự vừa khi cửa sổ game nhỏ; icon game là thành trì pixel.

Thiết kế bản điện thoại (đã chốt, làm ở M15):

**Một cách điều khiển chung** cho điện thoại và máy tính (chuột coi như một ngón tay):
- **Đặt mảnh đất / xây / di chuyển công trình:** chọn mảnh hoặc công trình, rồi chạm (bấm) một ô: bóng mờ dừng ở đó và **thanh xác nhận** hiện ra với nút **Đặt** (hoặc Xây / Chuyển tới) và **Hủy**, kèm sản lượng hay lý do chưa đặt được (nút Đặt khóa khi không hợp lệ). Chạm ô khác để dời; kéo ngón tay trên bóng thì bóng chạy theo. Trên máy tính, rê chuột vẫn hiện bóng xem trước khi chưa chạm; Enter = Đặt khi thanh xác nhận đang mở, Esc = Hủy.
- **Xem ô:** khi không cầm gì, chạm ô trống thì ô được viền sáng và khung thông tin góc dưới hiện ô đó (khung thu gọn được); chạm công trình mở bảng công trình như trước.
- **Bản đồ:** kéo một ngón để cuộn (chuột phải / giữa vẫn kéo được), chụm hai ngón để zoom (con lăn vẫn zoom). Bảng, cửa sổ và danh sách cuộn bằng vuốt.
- **Thanh tài nguyên:** chạm một tài nguyên mở khung nhỏ chi tiết thu / chi (thay cho tooltip khi rê chuột).
- **Phím tắt:** đều đã có nút (mảnh đất 1–3 = thẻ mảnh, Enter = Kết thúc lượt, Space = Tạm dừng trận); nút Back của Android = Esc (đóng cửa sổ, bỏ chọn). G (tọa độ) chỉ còn trên máy tính.

**Màn hình:** chỉ nằm ngang. Bố cục giữ như hiện tại; trên điện thoại chữ và nút được phóng to cho vừa ngón tay (nút tối thiểu ~48 px theo kích thước thật của màn hình).

**Xuất APK:** file cấu hình xuất Android trong project (`export_presets.cfg`: tên "Kingdom Tiles: Rise of Realms", gói `com.koyomikotori.kingdomtiles`, màn ngang, icon thành trì pixel). Người chơi tự cài export templates của Godot 4.5.1, JDK 17 và Android SDK theo `docs/android_export_guide.md`; xuất bản debug để cài thử.

## 11. Lộ trình

| Mốc | Nội dung | Trạng thái |
|---|---|---|
| M1 | Lưới 12×12, thành 2×2, zoom/pan, xem thông tin ô | Xong |
| M2 | Mảnh đất (hướng cố định), xem trước, kết nối, đè thay thế, ô quan trọng | Xong |
| ⏸ | **Chơi thử: xếp đất có vui không? Chỉnh trước khi đi tiếp** | Xong (ổn) |
| M3 | Sản lượng mỗi lượt, kết thúc lượt, nhận mảnh đầu lượt, ô ◆ ×2 | Xong |
| M4 | Công trình, dữ liệu đơn vị, doanh trại, tuyển quân, nuôi quân, mở khóa theo địa hình | Xong |
| M5 | Logic trận đánh theo pha + **cướp** (ngẫu nhiên, không báo trước) + trạm lính canh + bảng thống kê sau trận | Xong |
| M6 | **Chiến đấu v2** (logic): chỉ số mới, sĩ khí, charge, súng 1 loạt, cung theo thời gian nạp, mô phỏng theo tick, rút lui + **quản lý đơn vị** (bổ sung quân, giới hạn theo doanh trại, giải tán) | Xong |
| M7 | Màn hình trận đánh cinematic (10/18/44/18/10, hoạt ảnh, tạm dừng, tăng tốc, rút lui, bỏ qua) | Xong |
| M8 | Bản đồ thế giới làm sẵn + gia tộc + quan hệ + giao thương + hợp đồng dài hạn | Xong |
| M9 | Chiến tranh: tuyên chiến, quân xâm lược (mất đất theo hướng), đi xâm lược, nghị hòa, sáp nhập + mở rộng bản đồ | Xong |
| M9b | Liên minh: hiệp ước, đồng minh gửi quân vào trận, bất tương xâm | Xong |
| M10 | Lưu/tải (JSON có version), menu chính | Xong |
| M11a | Điều kiện thắng/thua, bảng Mục tiêu, màn kết thúc | Xong |
| M11b | Sự kiện ngẫu nhiên (dữ liệu .tres, có lựa chọn và hậu quả) | Xong |
| M11c | Kinh tế mới: cấp thành chính, công trình khai thác, Khoáng sản / Gỗ cứng / Ngựa | Xong |
| M11d | Tướng: sao 1–6, Võ lực / Thống suất / đặc tính theo lãnh thổ, một tổng tướng + cận vệ kỵ binh trong trận, tử trận / bị thương, sự kiện chiêu mộ | Xong |
| M11e | Kinh nghiệm và cấp: đơn vị 3 cấp (huấn luyện tới Cựu binh, pha loãng khi bổ sung), tướng lên cấp và tự cộng điểm | Xong |
| M11f | Mưu sĩ: 3 chức Nội chính / Ngoại giao / Quân sự, 3 chỉ số, bộ mưu kế đầu trận, chiêu hiền chung với tướng; **Kinh tế v2**: chỉ công trình cho tài nguyên, công trình 6 cấp, giới hạn theo cấp thành | Xong |
| M12a | **Đồ họa (1/3):** hệ thống ảnh pixel vẽ bằng script, bản đồ (địa hình, ô ◆, thành, công trình có cấp, mảnh đất trong tay), giao diện gỗ + giấy cuộn, icon tài nguyên (§13) | Xong |
| M12b | **Đồ họa (2/3):** trận đánh: lính từng loại, cận vệ tướng cưỡi ngựa, quân cướp / gia tộc, mũi tên, nền chiến trường, hiệu ứng mưu kế | Xong |
| M12c | **Tab Tướng sĩ** kiểu Ninja Village + chân dung pixel ghép bộ phận + bản đồ thế giới vẽ lại | Xong |
| M12d | **Bố cục tab + thi công mất lượt:** tab rộng và đều, bảng Xây dựng / Tuyển lính giữa màn hình có danh mục, xây và nâng cấp mất lượt, đội thợ (§8) | Xong |
| M12e | **Trang bị** cho tướng và mưu sĩ: 5 bậc độ hiếm, Xưởng rèn, chiến lợi phẩm, kho 20 món, vũ khí hiện trong trận, khung chân dung theo sao, sửa hình ngựa và vũ khí lính (§8 Trang bị) | Xong |
| M12f | Phần tiện cho chuột lấy từ M13: kéo chuột trái để cuộn bản đồ, kéo danh sách để cuộn, bấm ô / tài nguyên xem chi tiết, cửa sổ vừa màn hình, icon game (§10.2) | Xong |
| M13 | **Công trình và lính mới:** Doanh trại 6 cấp với 3 bậc lính, Chuồng ngựa chiến, Trại bắn tên, Võ trường, Học viện quân sự, 21 loại lính (kỵ binh, nỏ xuyên giáp, đao thuẫn, pháo, hỏa mai) (§8); M13b tiện ích, M13c bản đồ sinh động | Xong |
| M14 | M14a âm thanh (§14, xong); M14b chiến dịch (bản đồ 5×5, 24 gia tộc, chỉ thắng bằng thống nhất, bảng thông báo, §15, xong); M14d ruộng đất xung quanh, tháp canh, thành chứa quân, doanh trại hồi quân (§8, xong); **M14e công trình hành chính**: Chợ, Kho lương, Học quán, Y quán, Quan phủ, Sở cảnh sát với đặc vụ (§8); M14c build Windows, phát hành bản máy tính | Đang làm |
| M15 | **Bản điện thoại:** cảm ứng (chạm xem trước + thanh Đặt/Hủy, chụm để zoom, nút Back), giao diện cho màn nhỏ, xuất APK, giả lập (nhánh `m13/touch-apk`, §10.2) | Để cuối |

Đồ họa được đưa lên trước cảm ứng (chốt sau M11f) để lần sắp xếp lại bố cục dùng luôn giao diện mới. Bản điện thoại dời xuống cuối (chốt sau khi chơi thử M13 trên điện thoại): hoàn thiện bản máy tính trước.

Lưu/tải được đưa lên trước sự kiện và tướng, vì trạng thái game càng nhiều thì càng khó thêm lưu game về sau.

## 13. Đồ họa (M12, đã chốt)

**Nguồn ảnh:** pixel art **tự vẽ bằng script** (Python + Pillow, nằm trong `tools/art/`), xuất PNG vào `assets/`. Chạy lại script là vẽ lại toàn bộ, nên chỉnh màu / hình dễ và đồng bộ. Ảnh vẽ tay có thể thả vào thay file cùng tên.

**Phong cách:** **Đông Á cổ, tươi sáng kiểu Kairosoft**: thành mái ngói cong, tường đá, cờ hiệu; ruộng lúa, rừng tre / thông, đồi đá; lính đội nón, giáp vảy. Màu tươi, nét viền đậm, bảng màu chung cho cả game.

**Độ phân giải:** ô bản đồ **16×16** hiện ở **32×32** (phóng ×2, lọc nearest để giữ nét pixel); lính 16×16; chân dung 96×96 (bộ phận vẽ sẵn 48×48 phóng ×2).

**Giao diện:** **gỗ và giấy cuộn**: bảng nền giấy dó viền gỗ, nút gỗ nổi (thường / rê chuột / bấm / khóa), tab như thẻ treo, thanh trên cùng và cột bên phải nền gỗ. Dùng một `Theme` chung cho mọi bảng. **Font giữ nguyên** (đọc tiếng Việt rõ), chỉ đổi màu chữ và viền chữ cho hợp nền giấy; font pixel có thể thêm sau.

**M12a — bản đồ và giao diện:**
- Địa hình: cỏ, ruộng lúa, rừng, đồi đá, đất hoang ngoài lãnh thổ (tối, sương mờ), viền lãnh thổ; ô ◆ có dấu riêng.
- Thành chính (đổi theo cấp thành: tường, mái, cờ), doanh trại, trạm lính canh, nông trại, xưởng gỗ, mỏ; công trình khai thác có dấu cấp.
- Mảnh đất trong tay và bóng xem trước khi đặt dùng cùng ảnh ô.
- Icon 6 tài nguyên trên thanh trên cùng và trong các bảng.
- Menu chính và khung các cửa sổ (bảng công trình, ngoại giao, lưu / tải, báo cáo trận, sự kiện, mục tiêu).

**M12b — trận đánh (đã chốt):**
- Lính 16×16 hiện ×2. Hoạt ảnh **2 khung** cho mỗi trạng thái: **đứng, đi, đánh** (chém / đâm giáo / bắn cung), **ngã**, và **mừng chiến thắng** (phe thắng giơ vũ khí khi trận kết thúc). Thử 2 khung trước, thêm khung sau nếu cần.
- Mỗi loại lính một kiểu vẽ (vũ khí, mũ, giáp) khai báo theo loại lính, để sau này thêm loại lính mới chỉ cần thêm một mục.
- **Trang phục theo phe:** quân mình mang **màu chủ đạo của người chơi** (hiện là xanh lam; sau này người chơi tự chọn chủ tướng, cờ và màu khi bắt đầu ván mới); quân gia tộc mang màu cờ gia tộc; **quân cướp áo rách nâu, khăn bịt đầu**; đồng minh mang màu cờ của họ.
- **Tướng** to hơn lính và nổi bật: chiến mã giáp màu phe viền vàng, che mặt sắt, tua đỏ; giáp mạ vàng, mũ vàng cắm hai lông trĩ, áo choàng bay; vũ khí riêng to hơn hẳn lính (**Thanh long đao** lưỡi trăng lớn, cán sơn đỏ đai vàng, tua đỏ); cờ vàng. Tướng cưỡi ở đầu đội **cận vệ cưỡi ngựa** (giáp lá sắt trên áo màu phe, mũ sắt tua đỏ, thương có cờ đuôi nheo) cho tới khi ngã.
- **Tướng di chuyển tự do** (chỉ phần hình ảnh): xông thẳng vào quân địch trước mặt trên cùng hàng; nếu hàng đó không còn địch thì phi sang hàng gần nhất còn địch (kể cả cung thủ phía sau).
- **Mưu sĩ** (khi có mưu sĩ Quân sự) đứng phía sau quân mình, áo thụng màu phe, mũ văn quan, quạt lông; giơ quạt khi dùng mưu kế.
- Nhân vật pixel sẽ chi tiết dần, nhất là tướng và mưu sĩ (sau này có nhiều kiểu tướng đẹp để chiêu mộ).
- **Nền theo loại trận:** phòng thủ (cướp, xâm lược) có tường thành và mái nhà phía sau quân mình; đi đánh gia tộc có doanh trại và cờ gia tộc phía sau quân địch. Trời, mây, núi xa kiểu tranh, đồng cỏ.
- Mũi tên, đạn; hiệu ứng mưu kế (lửa, mưa tên, trống…).

**M12c — tab Tướng sĩ (kiểu Ninja Village, đã chốt):**
- Tab thứ 4 ở cột bên phải: Mảnh đất / Xây dựng / Quân đội / **Tướng sĩ**. Bảng thành chính chỉ còn **Thông tin / Nâng cấp / Chiêu hiền**; mọi việc quản lý chuyển sang tab Tướng sĩ.
- Danh sách: mỗi người một dòng với **hình pixel lúc ra trận** của chính người đó, tên, sao, chức vụ (Tổng tướng / Dự bị / Nội chính / Ngoại giao / Quân sự / chưa giữ chức), cấp, tình trạng (bị thương), dấu báo còn điểm cộng.
- Bấm vào một người → bảng chi tiết giữa màn hình: **chân dung pixel** bên trái, 2 tab **Chỉ số** (chỉ số có thanh, cấp và kinh nghiệm, đặc tính hoặc bộ mưu kế, chức vụ và tác dụng, phí nuôi) và **Trang bị** (3 ô vũ khí / giáp / phụ kiện còn trống, ghi "sắp có" cho tới M12d); các nút bên dưới: tướng — Làm tổng tướng, cộng điểm, Sa thải; mưu sĩ — Giao chức, cộng điểm, Sa thải.
- **Diện mạo** mỗi người (lưu trong bản lưu): giới tính (50% nam / 50% nữ, tên theo giới), màu da, kiểu tóc và màu tóc, kiểu mắt, lông mày, râu (nam), màu nhấn (mũ, lông trĩ, viền áo). Bản lưu cũ chưa có diện mạo thì tự tạo từ tên (luôn ra cùng một diện mạo).
- **Chân dung 96×96** ghép từ bộ phận vẽ sẵn (mặt, mắt, mày, miệng, tóc sau / tóc trước, râu, mũ / trâm, áo), tô màu theo diện mạo; tướng mặc giáp, mưu sĩ mặc áo văn quan; sao cao có khung viền vàng. Chân dung vẽ tay / vẽ bằng AI (96×96, nền trong suốt, không khung) đặt vào `assets/portraits/pool/` theo nhóm (`general_m_01.png`, `advisor_f_02.png`…): mỗi người tự nhận một ảnh trong nhóm đúng loại và giới tính, cố định và lưu lại; game tự vẽ nền và khung; nhóm chưa có ảnh thì dùng chân dung ghép. Hướng dẫn: `docs/portrait_ai_guide.md`.
- **Hình ra trận theo người:** tướng và mưu sĩ có bản nam và nữ, tóc và màu nhấn theo diện mạo; trận đánh và danh sách dùng cùng hình.
- **Bản đồ thế giới kiểu tranh cổ trên giấy:** nền giấy dó, núi, sông, rừng vẽ như bản đồ cổ; mỗi gia tộc là một tòa thành nhỏ cắm cờ màu của họ; đường nối là đường đất; biểu tượng chiến tranh / liên minh / bất tương xâm vẽ pixel.

**Để sau:** thêm gia tộc mới, mỗi gia tộc một nét riêng; tướng / mưu sĩ chiêu mộ từ gia tộc nào mang phong cách trang phục của gia tộc đó.

## 12. Câu hỏi mở

- Đè lên ô có công trình (ngoài thành): cấm hẳn, hay cho phép phá công trình và hoàn lại một phần tài nguyên?
- Sau khi chơi thử: có nên cho người chơi xoay mảnh không?
- Số mảnh mỗi lượt và tỉ lệ xuất hiện ô quan trọng.
- Bản đồ cố định 12×12, hay mở rộng biên khi nâng cấp thành?
- Bộ asset pixel art sẽ dùng (Kenney, itch.io…).

## 14. Âm thanh (M14a, đã chốt)

M14 chia 3 đợt: **M14a âm thanh**, M14b cân bằng, M14c bản phát hành Windows.

**Nguồn:** tất cả âm thanh **tự tạo bằng script** (`tools/audio/sound_gen.py`, Python + numpy, kiểu 8-bit Kairosoft), xuất WAV vào `assets/audio/sfx/` và `assets/audio/music/`. Người chơi bỏ file .ogg / .wav / .mp3 **trùng tên** vào `assets/audio/custom/` để thay bất kỳ âm thanh hay bản nhạc nào.

**Nhạc nền** (chiptune, âm giai ngũ cung Á Đông, lặp lại): menu chính, bản đồ vương quốc (thanh bình), trận đánh; đoạn ngắn thắng / thua khi trận kết thúc và ở màn hình kết thúc ván. Chuyển bản có fade.

**Hiệu ứng:** bấm nút (mọi nút), lỗi (thao tác không được), đặt đất, đặt nền móng / bắt đầu nâng cấp, xây xong, tuyển lính, phá hủy, kết thúc lượt (cồng), sự kiện, rèn, chiêu mộ tướng sĩ, buôn bán / tặng quà (tiếng xu). Trận đánh theo sự kiện: trống trận lúc bắt đầu, dây cung, nỏ, súng, pháo, kỵ binh xung phong, tiếng kim loại khi giáp lá cà (giới hạn số tiếng cùng lúc), tù và khi một đơn vị tan vỡ / rút lui, tướng ngã, mưu kế.

**Âm nền bản đồ (nhẹ):** thỉnh thoảng chim hót, tiếng búa khi đang có công trình thi công; tắt cùng "Hiệu ứng bản đồ" và im khi đang đánh trận.

**Cửa sổ Cài đặt** (nút "Cài đặt" ở Menu trong game và ở menu chính): thanh âm lượng Nhạc nền và Âm thanh hiệu ứng (0–100%), Hiệu ứng bản đồ Bật/Tắt, Toàn màn hình Bật/Tắt. Lưu theo máy (`user://settings.cfg`), không nằm trong file save.

## 15. Chiến dịch (M14b, đã chốt)

Mục tiêu: biến game thành chơi kiểu **chiến dịch**, mở rộng dần từ một góc bản đồ, mục tiêu rõ ràng, dễ tiếp cận hơn kiểu tự do. Thay cho phần bản đồ thế giới 6 gia tộc (§9.1–9.2), thắng hòa bình thịnh vượng (§9b) và hiệp ước bất tương xâm (§9.7).

**Bản đồ chiến dịch:** lưới **5×5**, vẽ trên một tấm bản đồ cổ lớn hơn màn hình, kéo chuột để di chuyển; các thành không xếp thẳng hàng mà lệch nhau tự nhiên, đường đất uốn lượn, có sông, hồ, dãy núi tuyết, rừng thông, đồi và xóm làng. Vương quốc của bạn ở ô góc trên-trái, **24 ô còn lại là 24 gia tộc**. Hai ô kề nhau (trên / dưới / trái / phải) là láng giềng. Lúc đầu chỉ có 2 láng giềng; đánh xong thì gặp thêm gia tộc mới, càng vào giữa bản đồ càng giáp nhiều mặt: mở rộng quá nhanh thì phải đối đầu nhiều gia tộc hiếu chiến cùng lúc, đánh quá chậm thì quân cướp ngày càng đông và mạnh.

**Khoảng cách** tính từ lãnh thổ hiện tại (ô gốc + mọi gia tộc đã thôn tính), theo số bước trên lưới:
- **Giáp ranh (1 bước):** tuyên chiến, tấn công được; chỉ những gia tộc này mới tuyên chiến và xâm lược bạn.
- **Trong 2 bước:** giao thương, tặng quà, hợp đồng giao thương, liên minh.
- **Xa hơn:** chỉ xem trên bản đồ, chưa qua lại được.

**Sức mạnh gia tộc** theo vành (số bước từ góc của bạn, 1–8) và tăng dần theo thời gian:
- Vành 1–2 dùng lính bậc nông dân; vành 3–4 có lính tinh nhuệ; vành 5 trở đi có cấm quân, kỵ binh nặng, hỏa khí. Quân số tối đa tăng theo vành. Góc đối diện là gia tộc mạnh nhất.
- Quân số tối đa của mọi gia tộc tăng 1% mỗi lượt (tối đa gấp đôi).
- Mọi gia tộc hồi **10% quân số tối đa mỗi lượt** (trước đây +2 lính).

**Thôn tính và mở đất:** cứ thôn tính **2 gia tộc** thì bản đồ vương quốc thêm 2 hàng / cột đất hoang (mở đất chậm, dễ kiểm soát), lần lượt theo chiều kim đồng hồ **trên → phải → dưới → trái**, không phụ thuộc gia tộc ở hướng nào. Tối đa 8 lần (2 vòng, sau 16 gia tộc): bản đồ từ 12×12 lên 20×20. Chỉ thôn tính mới mở đất: thắng trận phòng thủ, hay đánh thắng mà gia tộc chưa đầu hàng, thì không. Thua một trận bị xâm lược thì mất đất ở cạnh bản đồ hướng về phía gia tộc đó.

**Thành trì bị khóa theo chiến công:** muốn lên cấp thành phải đã thôn tính đủ số gia tộc: cấp 2 cần 1, cấp 3 cần 3, cấp 4 cần 6, cấp 5 cần 10, cấp 6 cần 15 (vẫn trả tài nguyên và mất lượt như trước). **Đồng minh tính như đã thôn tính** cho mốc thành; liên minh bị phá thì không tính nữa (thành đã lên cấp vẫn giữ).

**Sau lượt chơi thử đầu tiên:** mốc cấp 5 / 6 giảm từ 12 / 24 xuống 10 / 15 gia tộc. Trên chiến trường mỗi hình lính đại diện 7 lính (trước là 4) để đỡ giật khi quân đông. Bảng kết quả trận gộp theo **loại quân** cho cả hai phe (số đội, đầu trận, tử trận, còn lại, hạ được, số đội bị vỡ; quân đồng minh cho mượn tách riêng theo gia tộc), không liệt kê từng đội.

**Chiến thắng duy nhất: thống nhất** — mọi gia tộc trên bản đồ hoặc đã bị thôn tính, hoặc đang là đồng minh. Bỏ thắng hòa bình thịnh vượng, bỏ nút "Mục tiêu". Thua vẫn như cũ: thành chính thất thủ.

**Bỏ hiệp ước bất tương xâm** (không còn coi trọng hòa bình). *Có lại từ M16a, luật mới ở §17.*

**Quân cướp** nhiều và mạnh dần theo lượt: cứ mỗi 10 lượt tỉ lệ cướp tăng (có trần), số đội cướp tăng như trước, về sau có thêm kỵ binh cướp.

**Bảng thông báo** (cột bên trái, thu gọn được cả cột): thống kê mỗi lượt và những gì đang diễn ra, không ghi tài nguyên đã thu. Ba nhóm, mỗi dòng có tiêu đề với nút mũi tên bên phải để xổ ra / thu lại phần chi tiết, mặc định mở, người chơi tự ẩn dòng không quan tâm (nhớ theo máy):
- **Công trình:** đang thi công (còn mấy lượt), vừa xây / nâng cấp xong, xưởng rèn, thiếu phí duy trì.
- **Ngoại giao:** đang chiến tranh với…, vừa tuyên chiến, đình chiến, hợp đồng giao thương (đưa / nhận gì, còn mấy lượt), đang liên minh với… (còn mấy lượt), liên minh hết hạn / tan vỡ.
- **Quân đội & tướng sĩ:** bổ sung quân, lính bỏ trốn vì thiếu lương, tướng sĩ bị thương / vừa lành, ứng viên mới, thành chính nguy hiểm.
Bảng thông tin ô đất chuyển xuống đáy cột này.

**Bảng báo cáo quan trọng (M14g, đã chốt):** đầu lượt, sau trận cướp / xâm lược (và bảng kết quả trận), trước các sự kiện ngẫu nhiên, nếu có tin quan trọng thì hiện một bảng giữa màn hình, chỉ tắt bằng nút **OK** hoặc **Enter** (Esc cũng được). Gồm: bị tuyên chiến, đặc vụ bị lộ (trốn về / bị giết), tổng tướng bị thương / tử trận và mưu sĩ bị thương trong trận đầu lượt, lính đào ngũ vì thiếu lương, đồng minh rời bỏ, thành chính nguy hiểm; sau này thêm vùng đạo tặc xuất hiện (M14i). Không có tin nào thì không hiện. Trận người chơi tự đi đánh đã có bảng kết quả riêng nên không lặp lại.

**Ván mới, độ khó và tướng địch (M14h, đã chốt):**
- Bấm **Ván mới** mở bảng chọn: trên cùng là hình **thành trì cấp 6, tổng tướng và lính** của người chơi, đổi màu ngay theo màu đang chọn (mái và cờ thành trì cũng đổi màu trên bản đồ); rồi **tên gia tộc / vương quốc** (để trống = "Vương quốc của bạn"; hiện trên bản đồ thế giới và tên phe trong trận), **màu chủ đạo** (8 màu: áo quân, cờ, người đi tuần trên bản đồ, vương quốc trên bản đồ thế giới) và gần cuối bảng là **độ khó**; hai nút **Bắt đầu chơi** và **Về màn hình chính**. Cả ba lựa chọn lưu trong bản lưu; bản lưu cũ là Bình thường, tên và màu mặc định.
- **Độ khó** quyết định số lính mỗi đơn vị địch so với đơn vị tiêu chuẩn của người chơi: **Dễ 75%, Bình thường 100%, Khó 150%, Huyền thoại 200%**. Số đơn vị giữ nguyên, mỗi đơn vị to/nhỏ hơn; quân lực gia tộc trên bản đồ cũng nhân theo. Áp dụng cho quân gia tộc (đánh, xâm lược, gửi quân giúp nhau) và cướp (sau này cả thảo phạt). Bảng lưu game và màn kết thúc ghi độ khó.
- **Huyền thoại** mở cho các ván sau khi thắng (thống nhất) một ván Bình thường, Khó hoặc Huyền thoại (nhớ theo máy).
- **Tướng và mưu sĩ của gia tộc**, theo quân lực hiện tại của gia tộc (không tính hệ số độ khó): **yếu** (dưới 150 lính) không có ai ra trận; **trung bình** (150–399) có **một tướng hoặc một mưu sĩ** 1–2 sao (mỗi gia tộc luôn cùng một loại); **mạnh** (từ 400) có **cả tướng lẫn mưu sĩ 3 sao**. Huyền thoại: trung bình +1 sao, mạnh +2 sao. Không có trang bị, không có đặc tính. Gia tộc lớn lên thì được người mới sao cao hơn; bị đánh yếu đi thì tạm không cho họ ra trận.
- Họ ra trận như của ta: tướng có đội cận vệ và cộng chỉ số cho quân gia tộc (không cho quân được gửi sang giúp), đội cận vệ tan thì cả quân mất nhuệ khí; mưu sĩ dùng mưu kế đầu trận. Tướng địch ngã ngựa: **30% tử trận** (gia tộc có tướng mới sau 5 lượt), không thì bị thương 3 lượt; mưu sĩ địch thua trận có 50% bị thương 3 lượt. Người bị thương ở nhà. Bảng kết quả trận ghi số phận của họ; bảng gia tộc trên bản đồ ghi tên và sao của họ.

**Thảo phạt đạo tặc (M14i, đã chốt):**
- **Vùng nổi loạn:** từ lượt 8, khi chưa có vùng nào, mỗi lượt có **10%** xuất hiện một vùng **3×3** trên đất của vương quốc, chạm rìa lãnh thổ, không bao giờ trùng thành chính; chỉ một vùng cùng lúc, dẹp xong phải chờ ít nhất **5 lượt** mới có vùng mới. Báo trong bảng báo cáo quan trọng.
- Ô trong vùng **bị khóa hẳn**: công trình không sản xuất, không tính để mở lính / tác dụng; không đặt đất, không xây, không nâng cấp, không di chuyển công trình vào hay ra. Vùng nhấp nháy đỏ, có lính cướp đứng trong đó.
- Chưa có đội thảo phạt thì cứ **2 lượt** vùng lan thêm một ô về mọi phía còn lan được (chỉ trên đất của mình); dừng khi chạm thành chính. Đất mất đi thì ô đó rời vùng. Bỏ mặc chỉ khóa công trình, không mất gì thêm.
- **Bảng thảo phạt** (bấm vào vùng đỏ): tab **Quân địch** (số ô, số ải và trận phục kích, quân cướp mỗi trận, tỉ lệ gặp tướng nổi loạn, phần thưởng) và tab **Cử quân**: tối đa **1 tướng, 1 mưu sĩ, 10 đơn vị lính** (không tốn chi phí); bấm **Tiến hành thảo phạt** thì bảng đóng. Đang đi thì bấm vào vùng đỏ xem tiến trình và nút **Xem trận ải N**.
- **Số ải theo cấp thành** 1–6: 1/1/2/2/3/4 ải, mỗi ải 1/1/2/2/3/3 trận phục kích liền nhau. **Mỗi lượt đi một ải** (đánh vào cuối lượt). Mỗi trận 1–5 đơn vị cướp (theo ải, số vùng đã dẹp và độ lớn vùng; nhân theo độ khó), ải sau lính cướp có cấp cao hơn. **Cuối mỗi ải có thể gặp tướng nổi loạn** (15% + 20% mỗi ải sau + 5% mỗi vùng đã dẹp, tối đa 90%) dẫn thêm một đơn vị.
- Trận vẫn là giả lập như thường; đơn vị **bỏ chạy hoặc bị tiêu diệt là mất luôn** (khỏi quân đội); **hết ải cả đội hồi phục đủ quân**. Thua một trận là cả đội tan như thua trận thường: lính mất hết, tướng ngã ngựa 30% tử trận (không thì bị thương), mưu sĩ 50% bị thương; vùng đỏ vẫn còn, cử đội khác được.
- **Màn phát lại** (ải được đánh và tính xong ngay khi kết thúc lượt — kinh nghiệm, vật phẩm, lính về nhà — nên lính vừa về có thể phòng thủ trận đầu lượt sau; mỗi ải **tự phát đầu lượt sau, trước** trận xâm lược / cướp và bảng tin quan trọng; bấm vùng đỏ để xem lại bất kỳ ải nào đã đánh): màn hình ngang, đội đi từ trái sang phải, **mỗi đơn vị một nhân vật**, xếp **cột 3 hàng ngang** (tướng đứng đầu, rồi kỵ binh, cận chiến, đánh xa, mưu sĩ theo sau), thanh máu dưới chân; toán cướp xông ra từ bên phải, hai bên giáp nhau, ai hết quân / vỡ trận thì **văng xoay ra khỏi màn hình**; đánh liên tục các trận; nhạc riêng; x1/x2/x4, Bỏ qua; xong thì **bảng thống kê** ải (trận, tướng nổi loạn, mỗi đơn vị: lính, mất, hạ, kết cục).
- **Phần thưởng khi đội về** (thắng hay thua đều nhận phần đã kiếm được): mỗi trận thắng tướng / mưu sĩ +30, lính +20 kinh nghiệm; mỗi ải vượt qua **40 × số thứ tự ải × độ lớn vùng** mỗi loại lương thực / gỗ / đá và **một món trang bị** (ải sau dễ ra đồ hiếm, có cơ hội nhỏ ra Huyền thoại).
- **Khi đi vắng:** tướng / mưu sĩ không chỉ huy, không giữ tác dụng chức (vd. Ngoại giao) và không ra trận ở nhà, **không sa thải được**; tổng tướng đi vắng thì quân ở nhà đánh không có tướng. Lính đi vắng vẫn chiếm chỗ và tốn phí nuôi, không đánh trận ở nhà, không tự bổ sung, không giải tán được. Danh sách tướng sĩ và quân đội ghi "đang thảo phạt".

**Bản lưu cũ** (bản đồ 6 gia tộc) không tải được nữa: báo phiên bản cũ, bắt đầu ván mới.

**Sửa lỗi kèm theo:** khi chiêu mộ hoặc cộng điểm cho tướng sĩ, cửa sổ không còn co giãn làm khựng.

## 16. Bản phát hành Windows (M14c, đã chốt)

- **Bản 0.1 Early Access**, chỉ gửi bạn bè: file zip gồm `KingdomTiles.exe` (dữ liệu game gói luôn trong exe) và `Doc truoc.txt` (cách chạy, cảnh báo SmartScreen vì chưa ký số, chỗ để bản lưu và nhật ký).
- Phiên bản lấy từ `application/config/version` trong `project.godot`, hiện ở góc menu chính và bảng Giới thiệu.
- **Cách chơi:** bảng 6 tab (Bắt đầu, Đất đai, Xây dựng, Quân đội, Ngoại giao, Thảo phạt), mỗi tab vài đoạn ngắn.
- **Giới thiệu:** tab Trò chơi (tác giả, công cụ, nguồn đồ họa / chân dung AI / âm thanh), tab Bản quyền (giấy phép MIT của Godot và mọi thành phần bên thứ ba lấy thẳng từ engine), tab Báo lỗi (đường dẫn thư mục nhật ký và bản lưu, nút mở thư mục).
- **Nhật ký:** game luôn ghi log vào `user://logs/godot.log` (giữ vài lần chơi gần nhất); lúc mở menu ghi một dòng phiên bản, Godot và hệ điều hành.
- Build lại: `python tools/release/build_windows.py` (export preset "Windows Desktop" trong `export_presets.cfg`, ra `build/KingdomTiles_v<phiên bản>_Windows.zip`). Exe chưa có icon riêng (cần rcedit), cửa sổ game vẫn dùng icon của game.
- Thư mục `assets/audio/custom/` chỉ có tác dụng khi chạy trong Godot editor; bản build dùng nhạc đã gói sẵn.
- **Nhạc bản đồ vương quốc làm lại** (người chơi thấy bản cũ tone quá cao): nhẹ và chill hơn, 76 BPM, thấp hơn một quãng tám, giai điệu gảy mềm kiểu đàn tranh thưa nốt trên pad hợp âm ấm, arpeggio khẽ, trống rất nhẹ, có tiếng vang; khoảng 2 phút rồi lặp lại liền mạch. Các bài khác giữ nguyên.

## 17. Cân bằng và ngoại giao (M16a, đã chốt)

Sau khi chơi bản 0.1: về late game mọi gia tộc đều Thù địch và tỉ lệ liên minh luôn 0%, dù tặng quà hay có mưu sĩ Ngoại giao giỏi.

**Nguyên nhân:** mức đe dọa của vương quốc tăng mãi theo đất, số gia tộc bị thôn tính (+15 mỗi gia tộc) và số lính. Ở save lượt 158 đe dọa là 267: cảnh giác trừ quan hệ từ 87 đến 211 điểm, và tỉ lệ liên minh bị trừ thêm 133%.

**Cảnh giác có giới hạn:**
- Cảnh giác trừ tối đa **40** điểm quan hệ (trước khi tính mưu sĩ Ngoại giao). Bản lưu cũ có cảnh giác cao hơn bị hạ ngay về 40 khi tải.
- Phần đe dọa trừ vào tỉ lệ liên minh tối đa **25%**.
- **Đồng minh không cảnh giác** với vương quốc.

**Mưu sĩ Ngoại giao mạnh hơn:** mỗi điểm giảm **4%** cảnh giác (trước 3%) và **+3%** khả năng gia tộc đồng ý hợp đồng / liên minh / bất tương xâm / nghị hòa (trước 2%).

**Hiệp định bất tương xâm trở lại:**
- Ký được từ quan hệ **Trung lập (≥ −19)**, không chiến tranh, trong tầm 2 vùng, chưa liên minh.
- Tỉ lệ đồng ý = 40% + 1% mỗi điểm quan hệ trên −19 + tính cách (như hợp đồng) + 3% mỗi điểm Ngoại giao, tối đa 95%. Từ chối thì chờ **3 lượt** mới đề nghị lại.
- Kéo dài **10 lượt**, quan hệ **+10** trong thời gian đó; hết hạn có thông báo, ký lại được.
- Gia tộc đang có hiệp định **không tuyên chiến** (kể cả qua sự kiện) và không gửi quân giúp bạn của họ khi vương quốc đánh bạn họ.
- Người chơi tuyên chiến khi đang có hiệp định: hiệp định mất, mọi gia tộc khác mất thêm **20** quan hệ. Ký liên minh thì hiệp định không cần nữa (liên minh đã bao gồm).

**Hồi quân doanh trại giảm một nửa:** 5% + 0.5% × cấp mỗi doanh trại (xem §8).

**Thảo phạt đạo tặc thành công:** mọi gia tộc chưa bị thôn tính **+5 quan hệ** (ký ức "Dẹp loạn đạo tặc", mờ dần như quà tặng). Thua thì không có.

## 18. Sự kiện chiến tranh và đạo tặc (M16b, đã chốt)

Thêm vào hệ sự kiện (§9c), cùng cách tung 0–3 sự kiện mỗi lượt. Sự kiện chiến tranh chỉ vào danh sách khi đang có chiến tranh; mỗi cái chờ 8–12 lượt mới lặp lại. Lựa chọn có tỉ lệ thì hiện "Khả năng thành công: X%" ngay dưới nút.

| Sự kiện | Khi nào | Lựa chọn |
|---|---|---|
| **Kho lương bị đánh úp** | Đang chiến tranh với gia tộc đó, kho ≥ 40 lương | Đánh trả: mất 10% lương. Mặc kệ: mất 35% lương |
| **Cơ hội ám sát** | Có đặc vụ đang làm nhiệm vụ ở một gia tộc có tướng hoặc mưu sĩ | Ám sát tướng / Ám sát mưu sĩ: thành công 50% + 5% × sao đặc vụ → mục tiêu bị thương nặng hoặc chết (mỗi bên một nửa; chết thì 5 lượt sau mới có người thay). Thất bại: đặc vụ bị lộ, quan hệ −10, có thể bị giết (như bị bắt), không thì phải trốn về. Chưa phải lúc: không có gì |
| **Tướng bất mãn** | Có tướng ở nhà, từ lượt 10 | Ban thưởng: 40 lương + 10 khoáng sản. Phớt lờ: 40% một tướng bỏ đi (trả lại trang bị) |
| **Dân chúng cầu cứu** | Đang chiến tranh, có công trình sản xuất | Cứu trợ: 30 lương + 15 gỗ + 15 đá. Bỏ qua: 60% có 1–3 công trình sản xuất (nông trại, xưởng gỗ, mỏ) bị bỏ hoang 5 lượt: không sản xuất, vẽ xám có số lượt còn lại |
| **Tù binh quan trọng** | Đang chiến tranh với gia tộc đó | Đòi tiền chuộc: 50% + 5% × sao mưu sĩ Ngoại giao → 60 lương, 40 gỗ, 40 đá, 15 khoáng sản. Chiêu hàng (cần còn chỗ tướng hoặc mưu sĩ): cùng tỉ lệ → một tướng hoặc mưu sĩ (một nửa mỗi loại) gia nhập; sao theo sức gia tộc: yếu 1–2, trung bình 2–3, mạnh 3–4 |
| **Nhóm người khả nghi** | Ván có đạo tặc | Điều tra: 40% + 10% × cấp Sở cảnh sát → dẹp ổ đạo tặc, nhận 30 lương, 30 gỗ, 20 đá, 10 khoáng sản; thất bại thì đạo tặc chắc chắn kéo đến lượt sau. Bỏ qua: 50% đạo tặc kéo đến lượt sau |
| **Đạo tặc cầu hòa** | Có vùng nổi loạn, hoặc vừa đánh thắng cướp trong 3 lượt | Chấp nhận: 30 lương, 20 gỗ, 20 đá và 1–3 đơn vị lính nông dân đủ quân (nếu còn chỗ). Từ chối: không có gì |
| **Địch dụ hàng** | Đang chiến tranh, có tướng hoặc mưu sĩ ở nhà | Tăng đãi ngộ: 50 lương + 10 khoáng sản + 10 gỗ cứng, giữ chân tất cả. Mặc kệ: một tướng hoặc mưu sĩ ngẫu nhiên bỏ theo địch với tỉ lệ 50% − 5% × sao của người đó |

"Đạo tặc kéo đến lượt sau" chỉ thay cho lần tung tỉ lệ cướp; nếu lượt đó có gia tộc xâm lược thì trận cướp dời sang lượt kế. Tướng hoặc mưu sĩ đang đi thảo phạt không bị các sự kiện này ảnh hưởng.

Để sang M16e (cần trận đánh hoặc nhuệ khí tối đa): Đạo tặc bắt quan chức, Mật thư bị đánh cắp, Đặc vụ báo tin khẩn cấp.

## 19. Đột phá giới hạn (M16c, đã chốt)

Tướng và mưu sĩ đã đạt cấp tối đa có thể đột phá để lên tiếp.

- **Mỗi lần đột phá:** trần mỗi chỉ số +2 (10 → 12 → 14 → 16) và cấp tối đa +2. Điểm mới phải kiếm lại bằng kinh nghiệm; điểm đang dư thì dùng ngay được.
- **Số lần theo sao:** 1–2★ được 1 lần, 3–4★ được 2 lần, 5–6★ được 3 lần.
- **Điều kiện:** đạt cấp tối đa hiện tại, không đang đi thảo phạt.
- **Chi phí lần N:** N × (100 lương, 100 gỗ, 100 đá, 20 khoáng sản, 20 gỗ cứng, 20 ngựa) và N cuốn Bí kíp đột phá.
- **Bí kíp đột phá:** chỉ có khi thảo phạt thắng (dẹp yên vùng nổi loạn): 1 cuốn mỗi 2 ải, tối thiểu 1 (1–2 ải: 1, 3–4 ải: 2). Thảo phạt thua không có. Chợ đen (M16d) sẽ bán thêm.
- **Giao diện:** tab Chỉ số của cửa sổ tướng sĩ có mục "Đột phá N/M" (lần tới được gì, cần gì, nút Đột phá bấm hai lần để xác nhận, hoặc lý do chưa được). Tab Tướng sĩ ghi số Bí kíp đang có, "Đột phá N" cạnh cấp và "Có thể đột phá" khi đủ điều kiện.

### Yêu cầu và chi phí bằng icon (M16c, sau góp ý của người chơi)

Mọi bảng thông tin / nâng cấp trình bày điều kiện bằng hình thay vì câu chữ (`RequirementView`):
- **YÊU CẦU:** mỗi điều kiện một dòng, dấu ✓ xanh khi đạt, ✗ đỏ khi chưa (thành chính cấp N, đội thợ rảnh, còn chỗ, công trình cần có, số gia tộc, cấp tối đa, Bí kíp…).
- **CHI PHÍ:** ô icon tài nguyên + số, xanh khi đủ, đỏ khi thiếu; rê chuột xem cần / đang có. Thời gian có icon đồng hồ cát.
- **NHẬN ĐƯỢC / TÁC DỤNG:** mũi tên vàng cho từng lợi ích; sản lượng và phí duy trì là ô icon.
- Áp dụng ở: tab Thông tin và Nâng cấp của mọi công trình và thành chính, cửa sổ Xây dựng, Tuyển lính, tab Rèn, Chiêu hiền, Chiêu mộ đặc vụ, mục Đột phá và phí nuôi trong cửa sổ tướng sĩ.
- **Gọn hơn (góp ý lần 2):** mô tả công trình chỉ còn công dụng (giới hạn, cấp thành, địa hình, phí duy trì đã có dòng riêng); mỗi tác dụng một dòng; tab Thông tin không liệt kê lính nữa (xem ở tab Quân đội); tab Nâng cấp chỉ hiện ô hình + tên các loại lính tuyển được ngay sau khi lên cấp, loại còn thiếu công trình khác gộp thành "+N loại lính khác…"; công trình không nâng cấp được thì không có tab Nâng cấp; hồi quân hiện "+1% → +1.5%".

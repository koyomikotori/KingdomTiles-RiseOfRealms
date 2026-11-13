class_name HowToPlayWindow
extends TextPagesWindow
## "Cách chơi" from the main menu (M14c): a short guide, one tab per part of the game.

const PAGES := [
	["Bắt đầu", [
		"# Mục tiêu",
		"Thống nhất vùng đất: mọi gia tộc trên bản đồ chiến dịch hoặc đã bị bạn thôn tính, hoặc đang là đồng minh của bạn.",
		"Bạn thua khi thành chính thất thủ: thua một trận xâm lược lúc không còn ô đất nào ngoài thành.",
		"# Ván mới",
		"Đặt tên vương quốc, chọn màu quân, độ khó, chúa công (6 mẫu, đặt tên riêng) và một trong hai cố vấn: Linh Nhi vui tươi hay Tử Uyên điềm tĩnh. Cố vấn sẽ kể sự kiện, báo cáo trận đánh và nhận xét kết quả suốt ván. Mỗi ván mới, cố vấn dẫn từng bước trong mấy lượt đầu (bấm \"Bỏ qua hướng dẫn\" lúc nào cũng được).",
		"# Thành tựu",
		"Nút \"Thành tựu\" ở màn hình chính liệt kê 46 thành tựu, giữ qua mọi ván (vài cái ẩn tới khi đạt được). Đạt thành tựu thì một thông báo hiện ở góc trên phải. Một số thành tựu mở màu quân, danh hiệu và khung chân dung chúa công mới, chọn ở màn Ván mới (nút \"Thay đổi\" cạnh chúa công).",
		"# Một lượt",
		"1. Đặt các mảnh đất mới để mở rộng hoặc cải tạo lãnh thổ.",
		"2. Xây công trình, tuyển lính, chiêu mộ tướng sĩ, ngoại giao.",
		"3. Bấm Kết thúc lượt (Enter): thu tài nguyên, trả phí nuôi quân và công trình.",
		"4. Đầu lượt mới có thể có trận đánh, bảng tin quan trọng, sự kiện và chợ đen.",
		"# Điều khiển",
		"Lăn chuột để phóng to / thu nhỏ, kéo chuột để di chuyển bản đồ. Phím 1–3 chọn mảnh đất, Enter kết thúc lượt, Esc đóng cửa sổ hoặc bỏ chọn, Space tạm dừng trận đánh.",
		"Trên điện thoại: chạm một ô để đặt bản xem trước rồi bấm Đặt / Xây; kéo một ngón để di chuyển, chụm hai ngón để phóng to; nhấn giữ một nút để xem chú thích; nút Quay lại của máy = Esc.",
		"Cột thông báo bên trái tóm tắt những gì đang diễn ra; bấm vào từng dòng để xem chi tiết.",
	]],
	["Đất đai", [
		"# Mảnh đất",
		"Mỗi lượt bạn nhận 3 mảnh đất hình khối (kiểu Tetris). Mảnh không xoay được; mảnh chưa đặt sẽ bị bỏ khi hết lượt.",
		"Mảnh phải chạm cạnh lãnh thổ của bạn, hoặc đặt đè lên đất cũ. Đặt đè sẽ thay địa hình ô đó, nhưng không đè được lên thành chính và công trình.",
		"# Địa hình",
		"Cỏ: đất trống để xây. Ruộng: lương thực. Rừng: gỗ. Đồi đá: đá.",
		"Đất tự nó không cho tài nguyên: xây Nông trại trên ruộng, Xưởng gỗ trên rừng, Mỏ trên đồi đá. Mỗi ô cùng loại đất còn trống kề bên công trình cho thêm tài nguyên, nên hãy gom đất cùng loại quanh công trình.",
		"Ô có dấu ◆ là ô quý: công trình trên đó làm ra gấp đôi, ô ◆ kề bên cho thêm nhiều hơn. Đặt đè lên sẽ mất nó.",
	]],
	["Xây dựng", [
		"# Công trình",
		"Tab Xây dựng: chọn công trình rồi bấm lên ô trống. Công trình mất vài lượt để xây xong và tốn phí duy trì mỗi lượt.",
		"Bấm vào công trình để nâng cấp, di chuyển hoặc phá bỏ.",
		"# Thành chính",
		"Thành chính mở khóa công trình và giới hạn mới. Muốn lên cấp thành, bạn phải đã thôn tính (hoặc liên minh với) đủ số gia tộc.",
		"Bấm vào thành để Chiêu hiền: chiêu mộ tướng và mưu sĩ.",
		"# Thiếu tài nguyên",
		"Không đủ lương nuôi quân thì lính bỏ trốn. Không đủ phí duy trì thì công trình tạm ngừng tác dụng.",
	]],
	["Quân đội", [
		"# Lính",
		"Tab Quân đội: tuyển các đơn vị lính (cần Doanh trại và các công trình quân sự). Lính có kinh nghiệm và lên cấp sau mỗi trận.",
		"Đơn vị thiếu quân tự bổ sung dần mỗi lượt nhờ Doanh trại.",
		"# Tướng sĩ",
		"Tướng chỉ huy cả đạo quân (tổng tướng), cộng sức đánh và sĩ khí. Tướng có thể bị thương hoặc tử trận.",
		"Mưu sĩ dùng mưu kế đầu trận (hỏa công, mưa tên…) và giữ chức vụ trong triều để tăng kinh tế, ngoại giao.",
		"# Trận đánh",
		"Trận đánh diễn ra tự động. Bạn có thể tăng tốc, bỏ qua hoặc rút lui (giữ lại một phần quân).",
		"Hết 120 giây mà bên tấn công chưa thắng thì bên tấn công thua.",
	]],
	["Tướng sĩ", [
		"# Tướng và mưu sĩ",
		"Tab Tướng sĩ liệt kê tướng, mưu sĩ và đặc vụ; bấm vào một người để cộng điểm, trang bị đồ, giao chức hoặc sa thải. Tướng sĩ càng nhiều sao càng giỏi và có hình, hào quang riêng.",
		"Lò rèn chế tạo trang bị; thắng trận cũng có thể nhặt được trang bị, kể cả đồ Huyền thoại có tên riêng.",
		"# Đột phá",
		"Tướng sĩ đã đạt cấp tối đa có thể đột phá để nâng thêm cấp và trần chỉ số. Cần tài nguyên và Bí kíp (thắng thảo phạt hoặc mua ở chợ đen).",
		"# Luyện tập",
		"Tướng từ 3★ có thể Tỉ thí với một võ nhân giang hồ: bấm Space hoặc chuột trái khi kim vào vùng đỏ / vàng để đánh, bấm đúng W A S D khi vòng thu vào vòng xanh để né. Trên điện thoại: chạm bất kỳ đâu để đánh, vuốt theo hướng mũi tên để né.",
		"Mưu sĩ từ 3★ có thể Đấu trí lật thẻ với chúa công: lật 2 thẻ giống nhau để lấy cặp, trúng thì được lật tiếp, ai nhiều cặp hơn thắng.",
		"Thắng hay thua đều có kinh nghiệm (thắng nhiều hơn); mỗi người nghỉ 5 lượt giữa hai lần. Đôi khi chính tướng sĩ tự xin luyện tập: nhận lời thì được thêm 50% kinh nghiệm.",
		"# Chợ đen",
		"Cứ 8 lượt, gã chợ đen ghé thành một lượt: bán trang bị và Bí kíp, mua lại đồ bạn không dùng. Có thể đổi hàng tối đa 3 lần.",
	]],
	["Ngoại giao", [
		"# Bản đồ chiến dịch",
		"Nút Ngoại giao mở bản đồ 24 gia tộc. Gia tộc giáp ranh có thể tuyên chiến và tấn công nhau; gia tộc trong 2 bước có thể giao thương, tặng quà, ký hợp đồng, bất tương xâm và liên minh.",
		"Mưu sĩ giữ chức Ngoại giao giúp gia tộc khác dễ đồng ý hơn và bớt cảnh giác khi vương quốc lớn mạnh.",
		"# Giao thương",
		"Mỗi gia tộc chỉ có một lượng hàng để đổi, hồi dần mỗi lượt; hết hàng thì phải đợi hoặc tìm gia tộc khác. Bán dồn một thứ cho cùng gia tộc thì giá giảm dần. Mỗi gia tộc thỉnh thoảng cần gấp một thứ và trả giá cao hơn cho thứ đó.",
		"Quà là thứ họ thiếu hoặc cần gấp thì quý hơn; tặng liên tục thì họ quen dần, quà kém tác dụng.",
		"# Cống nạp",
		"Gia tộc giáp ranh đông quân hơn hẳn có thể đòi ta cống nạp: nộp thì yên ổn một thời gian, khước từ thì có thể bị tuyên chiến. Khi quân ta đông gấp đôi một gia tộc giáp ranh, ta cũng có thể đòi họ cống nạp, đổi lại quan hệ giảm.",
		"# Chiến tranh",
		"Tuyên chiến với gia tộc giáp ranh (hoặc bị họ tuyên chiến), rồi tấn công họ từ bản đồ. Thắng thì được chiến lợi phẩm và làm gia tộc yếu đi; khi quân số của họ xuống thấp, họ đầu hàng và bị thôn tính.",
		"Cứ thôn tính 2 gia tộc, bản đồ vương quốc rộng thêm. Thua trận xâm lược thì mất đất ở rìa.",
		"# Đặc vụ",
		"Sở cảnh sát cho phép cử đặc vụ tới gia tộc khác để tăng quan hệ hoặc phá hoại (mỗi gia tộc 1 đặc vụ). Đặc vụ ở càng lâu càng dễ bị lộ.",
	]],
	["Thảo phạt", [
		"# Quân nổi loạn",
		"Từ lượt 8, đạo tặc có thể nổi loạn chiếm một vùng đất của bạn (ô đỏ nhấp nháy). Công trình ở đó ngừng hoạt động và vùng đỏ lan dần nếu không dẹp.",
		"# Cử quân",
		"Bấm vào vùng đỏ để xem quân địch và cử đội thảo phạt: 1 tướng, 1 mưu sĩ và tối đa 10 đơn vị lính. Đội đi vắng thì không phòng thủ ở nhà.",
		"Mỗi lượt đội đánh một ải gồm vài trận phục kích, cuối ải có thể gặp tướng nổi loạn. Trận được phát lại ở đầu lượt sau.",
		"Thắng hết các ải thì vùng đỏ được dẹp, đội về nhà mang theo kinh nghiệm, tài nguyên, trang bị và Bí kíp; mọi gia tộc cũng quý vương quốc hơn. Thua một trận là cả đội tan.",
		"Tướng nổi loạn có thể thách đấu tay đôi giữa đường; có thể chọn trước khi xuất quân là nhận hay tránh.",
		"# Sự kiện",
		"Mỗi lượt có thể có vài sự kiện: thương nhân, thiên tai, tù binh, tướng địch thách đấu, đặc vụ báo tin… Cố vấn kể lại tình hình; mỗi lựa chọn ghi rõ cái giá phải trả, còn kết quả chỉ biết sau khi chọn. Có sự kiện dẫn thẳng vào trận đánh.",
	]],
]


func open() -> void:
	open_frame("Cách chơi", 0.55)
	for page: Array in PAGES:
		add_page(page[0], page[1])

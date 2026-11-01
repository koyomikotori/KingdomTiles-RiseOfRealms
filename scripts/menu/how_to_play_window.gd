class_name HowToPlayWindow
extends TextPagesWindow
## "Cách chơi" from the main menu (M14c): a short guide, one tab per part of the game.

const PAGES := [
	["Bắt đầu", [
		"# Mục tiêu",
		"Thống nhất vùng đất: mọi gia tộc trên bản đồ chiến dịch hoặc đã bị bạn thôn tính, hoặc đang là đồng minh của bạn.",
		"Bạn thua khi thành chính thất thủ: thua một trận xâm lược lúc không còn ô đất nào ngoài thành.",
		"# Một lượt",
		"1. Đặt các mảnh đất mới để mở rộng hoặc cải tạo lãnh thổ.",
		"2. Xây công trình, tuyển lính, chiêu mộ tướng sĩ, ngoại giao.",
		"3. Bấm Kết thúc lượt (Enter): thu tài nguyên, trả phí nuôi quân và công trình.",
		"4. Đầu lượt mới có thể có trận đánh, bảng tin quan trọng và sự kiện.",
		"# Điều khiển",
		"Lăn chuột để phóng to / thu nhỏ, kéo chuột để di chuyển bản đồ. Phím 1–3 chọn mảnh đất, Enter kết thúc lượt, Esc đóng cửa sổ hoặc bỏ chọn, Space tạm dừng trận đánh.",
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
		"Lò rèn chế tạo trang bị cho tướng sĩ; thắng trận cũng có thể nhặt được trang bị.",
		"# Trận đánh",
		"Trận đánh diễn ra tự động. Bạn có thể tăng tốc, bỏ qua hoặc rút lui (giữ lại một phần quân).",
		"Hết 120 giây mà bên tấn công chưa thắng thì bên tấn công thua.",
	]],
	["Ngoại giao", [
		"# Bản đồ chiến dịch",
		"Nút Ngoại giao mở bản đồ 24 gia tộc. Gia tộc giáp ranh có thể tuyên chiến và tấn công nhau; gia tộc trong 2 bước có thể giao thương, tặng quà, ký hợp đồng, bất tương xâm và liên minh.",
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
		"Thắng hết các ải thì vùng đỏ được dẹp, đội về nhà mang theo kinh nghiệm, tài nguyên và trang bị. Thua một trận là cả đội tan.",
	]],
]


func open() -> void:
	open_frame("Cách chơi", 0.55)
	for page: Array in PAGES:
		add_page(page[0], page[1])

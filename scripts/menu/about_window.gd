class_name AboutWindow
extends TextPagesWindow
## "Giới thiệu" from the main menu (M14c): who made the game and with what, the licenses the
## game must show (Godot's MIT license and its third-party parts, read from the engine), and
## where the log files are, for reporting a crash.

const LOG_FOLDER := "user://logs"
const SAVE_FOLDER := "user://saves"


## "v0.1 Early Access" from the project's version (application/config/version).
static func version_text() -> String:
	return "v%s Early Access" % ProjectSettings.get_setting("application/config/version", "0.1")


func open() -> void:
	open_frame("Giới thiệu", 0.55)
	add_page("Trò chơi", [
		"# Kingdom Tiles : Rise Of Realms",
		"Phiên bản %s. Đây là bản chơi thử sớm: luật chơi và cân bằng còn thay đổi, bản lưu có thể không dùng được ở phiên bản sau." % version_text(),
		"# Thực hiện",
		"Thiết kế và phát triển: koyomikotori.",
		"Lập trình cùng Claude Code (Anthropic).",
		"Đồ họa pixel: vẽ bằng script (Python + Pillow). Chân dung tướng sĩ: tạo bằng AI (Grok, Gemini).",
		"Âm thanh và nhạc nền: tạo bằng script (chiptune, Python + numpy).",
		"Làm bằng Godot Engine %s (godotengine.org)." % Engine.get_version_info().string,
	])
	add_page("Bản quyền", _license_paragraphs(), 12)
	var report := add_page("Báo lỗi", [
		"Nếu game báo lỗi, đứng hình hoặc tự tắt, hãy gửi file nhật ký cho tác giả kèm vài dòng kể lại bạn đang làm gì.",
		"Nhật ký nằm trong thư mục dưới đây (file godot.log là lần chơi gần nhất, các file có ngày giờ là những lần trước):",
		ProjectSettings.globalize_path(LOG_FOLDER),
		"Bản lưu game nằm ở:",
		ProjectSettings.globalize_path(SAVE_FOLDER),
	])
	report.add_child(_button("Mở thư mục nhật ký", func() -> void: _open_folder(LOG_FOLDER)))
	report.add_child(_button("Mở thư mục bản lưu", func() -> void: _open_folder(SAVE_FOLDER)))


func _open_folder(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var error := OS.shell_open(ProjectSettings.globalize_path(folder))
	if error != OK:
		set_status("Không mở được thư mục (lỗi %s)." % error_string(error), false)


## Godot's license, then every third-party part bundled with the engine and its license.
func _license_paragraphs() -> Array:
	var result: Array = ["# Godot Engine (giấy phép MIT)", Engine.get_license_text(), "# Thành phần bên thứ ba trong Godot"]
	for info: Dictionary in Engine.get_copyright_info():
		var lines: Array[String] = [String(info.name)]
		for part: Dictionary in info.parts:
			for holder: String in part.copyright:
				lines.append("© " + holder)
			lines.append("Giấy phép: " + String(part.license))
		result.append("\n".join(lines))
	result.append("# Toàn văn các giấy phép")
	var licenses := Engine.get_license_info()
	for license_name: String in licenses:
		result.append("%s\n%s" % [license_name, licenses[license_name]])
	return result

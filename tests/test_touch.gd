extends "res://tests/test_suite.gd"
## M15a: touch support (GDD §10.2): the automatic UI scale and the "Cỡ giao diện" setting.

const TEST_SETTINGS := "user://test_touch_settings.cfg"
const BASE := Vector2(1280, 720)


## Every script under res://scripts compiles (M15a: a member added to ModalWindow clashed with one
## in EventWindow, which no other test loads, and the game broke only when that window opened).
func test_every_script_compiles() -> void:
	var broken: Array[String] = []
	for path in _scripts_under("res://scripts"):
		var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as GDScript
		if script == null or not script.can_instantiate():
			broken.append(path)
	check(broken.is_empty(), "Scripts that do not compile: %s" % ", ".join(broken))


func _scripts_under(folder: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			found.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		found.append_array(_scripts_under(folder.path_join(sub)))
	return found


func test_auto_scale_is_one_on_a_computer() -> void:
	check_eq(Touch.auto_ui_scale(Vector2(1920, 1080), 96.0, BASE, false), 1.0, "Computers keep the layout as is")
	check_eq(Touch.auto_ui_scale(Vector2(2400, 1080), 0.0, BASE, true), 1.0, "Unknown density: no change")


func test_auto_scale_grows_buttons_on_a_phone() -> void:
	# A 2400×1080 phone at 400 dpi: 1.5× stretch makes a 40 px button 60 screen px (~3.8 mm).
	var phone := Touch.auto_ui_scale(Vector2(2400, 1080), 400.0, BASE, true)
	check(phone > 1.0, "Phones get a bigger UI")
	check(phone <= Touch.MAX_AUTO_SCALE, "Capped so the layout still fits")
	# A big low-density tablet already has finger-sized buttons.
	var tablet := Touch.auto_ui_scale(Vector2(2560, 1600), 160.0, BASE, true)
	check_eq(tablet, 1.0, "Large screens need no extra scale")


func test_ui_scale_stops_where_windows_still_fit() -> void:
	# A 2400×1080 phone: 1600×720 logical at scale 1, so 720 / 500 = 1.44 at most.
	check(is_equal_approx(Touch.fitting_scale(Vector2(2400, 1080), BASE), 1.44), "Height limits a wide phone")
	check(is_equal_approx(Touch.fitting_scale(Vector2(1280, 720), BASE), 1280.0 / 960), "Width limits the design size")
	check(Touch.MAX_AUTO_SCALE <= Touch.fitting_scale(Vector2(2400, 1080), BASE), "Auto scale fits a common phone")


func test_key_hints_drop_in_touch_mode() -> void:
	check_eq(Touch.strip_key_hint("Đóng (Esc)"), "Đóng", "Esc hint dropped")
	check_eq(Touch.strip_key_hint("Kết thúc lượt (Enter)"), "Kết thúc lượt", "Enter hint dropped")
	check_eq(Touch.strip_key_hint("Xem người khác (phím ← →)"), "Xem người khác", "Arrow hint dropped")
	check_eq(Touch.strip_key_hint("Làm mới (còn 3 lần)"), "Làm mới (còn 3 lần)", "Other brackets kept")
	var was := Touch.active
	Touch.active = false
	check_eq(Touch.keys("Đóng (Esc)"), "Đóng (Esc)", "Mouse play keeps the hint")
	Touch.active = was


func test_spar_swipe_direction() -> void:
	check_eq(SparScreen.swipe_direction(Vector2(10, 5)), &"", "Too short")
	check_eq(SparScreen.swipe_direction(Vector2(60, 10)), &"right", "Right")
	check_eq(SparScreen.swipe_direction(Vector2(-60, 20)), &"left", "Left")
	check_eq(SparScreen.swipe_direction(Vector2(10, -50)), &"up", "Up")
	check_eq(SparScreen.swipe_direction(Vector2(-20, 70)), &"down", "Down")


func test_black_market_page_fits_two_columns() -> void:
	var wide := BlackMarketWindow.page_size(3)
	var narrow := BlackMarketWindow.page_size(2)
	check(narrow.x < wide.x and narrow.y > wide.y, "Two columns: narrower and taller")


func test_ui_scale_setting_is_kept_and_clamped() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	GameSettings.use_file(TEST_SETTINGS)
	check_eq(GameSettings.ui_scale(), GameSettings.AUTO_UI_SCALE, "Automatic by default")
	GameSettings.set_ui_scale(5.0)
	check_eq(GameSettings.ui_scale(), GameSettings.MAX_UI_SCALE, "Clamped to the largest size")
	GameSettings.set_ui_scale(1.3)
	GameSettings.use_file(TEST_SETTINGS)
	check(is_equal_approx(GameSettings.ui_scale(), 1.3), "Read back from the file")
	GameSettings.set_ui_scale(GameSettings.AUTO_UI_SCALE)
	check_eq(GameSettings.ui_scale(), GameSettings.AUTO_UI_SCALE, "Back to automatic")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	GameSettings.use_file(GameSettings.PATH)

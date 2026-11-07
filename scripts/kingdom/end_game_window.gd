class_name EndGameWindow
extends ModalWindow
## Victory or defeat screen (GDD §9b) with the game's statistics. After a victory the player may
## keep playing; after a defeat only loading a save or going back to the menu are left. It cannot
## be closed with Esc.

const VICTORY_COLOR := Color(0.62, 0.42, 0.08)
const DEFEAT_COLOR := UiPalette.WARNING

var _state: KingdomState
var _system: SaveSystem
var _host: Node


## `path` is the Victory.Path won, or Victory.NO_PATH for a defeat. `host` is where the load
## window opens.
func open(state: KingdomState, path: int, system: SaveSystem, host: Node) -> void:
	_state = state
	_system = system
	_host = host
	var won := path != Victory.NO_PATH
	Sfx.sting(&"victory" if won else &"defeat")
	var title := "Chiến thắng: %s!" % Victory.PATH_NAMES[path] if won else "Thành chính thất thủ!"
	var body := build_frame(title, VICTORY_COLOR if won else DEFEAT_COLOR, 0.42, false)
	var story := _label(_story(path), 16)
	body.add_child(story)
	var counsel := Counsel.lines(&"victory" if won else &"defeat", state.counselor, Counsel.context(state))
	if not counsel.is_empty():
		var box := CounselBox.new()
		box.setup(counsel, get_viewport_rect().size.x * 0.42 - 60.0)
		body.add_child(box)
	if won and Difficulty.unlocks_legendary(state.difficulty):
		var opened := not GameSettings.legendary_unlocked()
		GameSettings.unlock_legendary()
		if opened:
			var unlocked := _label("Đã mở độ khó Huyền thoại cho ván sau!", 16)
			unlocked.add_theme_color_override("font_color", VICTORY_COLOR)
			body.add_child(unlocked)
	body.add_child(HSeparator.new())
	body.add_child(_label(_statistics(), 15))
	if won:
		add_action("Chơi tiếp", close)
	else:
		add_action("Tải game", _open_load)
	add_action("Về menu chính", func() -> void: GameLaunch.to_menu(get_tree()))


func _story(path: int) -> String:
	match path:
		Victory.Path.CONQUEST:
			return "Mọi gia tộc đã quy phục hoặc kết minh dưới cờ của bạn. Thiên hạ giờ là một."
	return "Quân địch tràn vào thành chính. Vương quốc của bạn đã sụp đổ."


func _statistics() -> String:
	var annexed := 0
	var allies := 0
	for clan in _state.diplomacy.clans.values():
		annexed += 1 if clan.annexed else 0
		allies += 1 if clan.is_allied() else 0
	return "\n".join([
		"Độ khó: %s" % Difficulty.NAMES[_state.difficulty],
		"Số lượt: %d" % _state.turn,
		"Lãnh thổ: %d ô" % _state.board.count_owned_cells(),
		"Quân: %d lính (%d đơn vị)" % [_state.army.count_soldiers(), _state.army.count_squads()],
		"Trận đánh: thắng %d, thua %d" % [_state.stats.battles_won, _state.stats.battles_lost],
		"Gia tộc: %d sáp nhập, %d đồng minh" % [annexed, allies],
	])


func _open_load() -> void:
	var window := SaveSlotWindow.new()
	_host.add_child(window)
	window.open(SaveSlotWindow.Mode.LOAD, _system)
	window.load_requested.connect(func(slot: String) -> void:
		var error := GameLaunch.load_game(get_tree(), _system, slot)
		if error != "":
			window.show_error(error))

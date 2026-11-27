class_name SubmissionWindow
extends ModalWindow
## A weak neighbor asks to become our vassal (GDD §38, M18f-b2c), shown at the start of the turn
## after its battles: who they are, their king, the tribute they would pay, the counselor's words;
## Chấp nhận / Từ chối (asked again 5 turns after a refusal). Not closable: the player decides.

signal decided(accepted: bool)

const WIDTH := 0.46

var _state: KingdomState


func open(state: KingdomState, counsel: Array[Dictionary] = []) -> void:
	_state = state
	var realm := state.realm
	var nation: Realm.Nation = realm.nations[realm.pending_submission]
	var body := build_frame("%s xin quy phục" % nation.name, UiPalette.GOLD, WIDTH, false)
	if not counsel.is_empty():
		var box := CounselBox.new()
		box.setup(counsel, get_viewport_rect().size.x * WIDTH - 60.0)
		body.add_child(box)
		body.add_child(HSeparator.new())
	body.add_child(_label("Sứ giả %s dâng thư: nước nhỏ chỉ còn %d trấn, xin làm chư hầu của %s." % [nation.name,
			realm.count_owned(nation.id), Counsel.kingdom_label(state.kingdom_name)], 15))
	var view := RequirementView.new()
	body.add_child(view)
	var stars := Realm.king_stars(nation, state.difficulty)
	view.line(&"achievement_military", "Sức họ %d lính · sức ta %d lính" % [RealmDiplomacy.power(realm, state, nation.id),
			RealmDiplomacy.power(realm, state, Realm.PLAYER)])
	view.line(&"scroll", "Vua chư hầu %d★ · trung thành %d/%d" % [stars, Realm.LOYALTY_START, Realm.LOYALTY_MAX])
	var king := General.new()
	king.stars = stars
	view.amounts("Cống nạp mỗi lượt", Realm.tribute_of(king))
	for text in ["Họ giữ các trấn của mình (trấn họ chiếm được cũng là của họ), đánh và hòa theo ta, có đạo quân riêng.",
			"Trung thành giảm 5 mỗi lượt khi họ không kém ta, 10 khi ta mất một trấn, 20 khi mất kinh đô; về 0 thì họ ly khai và tuyên chiến.",
			"Từ chối: %d lượt sau họ mới xin lại." % Realm.SUBMIT_REFUSE_WAIT]:
		var note := _label(text, 13)
		note.add_theme_color_override("font_color", UiPalette.MUTED)
		body.add_child(note)
	add_action("Từ chối", _decide.bind(false))
	add_action("Chấp nhận", _decide.bind(true))


func _decide(accepted: bool) -> void:
	if accepted:
		_state.realm.accept_submission(_state)
		Sfx.play(&"complete")
	else:
		_state.realm.refuse_submission(_state)
	decided.emit(accepted)
	close()

extends SceneTree

## TutorialDirector + GameSettings [tutorial] 旗标与步骤流。
const SETTINGS := "user://settings.cfg"

var _failed: int = 0

func _initialize() -> void:
	_case_flags_roundtrip()
	_case_should_auto()
	_case_step_flow()
	_case_multiplayer_marks_seen()
	_case_replay_after_seen()
	print("tutorial_director_test: %d failed" % _failed)
	quit(_failed)

func _case_flags_roundtrip() -> void:
	_wipe_settings()
	GameSettings.load_from_disk()
	_expect(not GameSettings.is_tutorial_seen(), "默认未 seen")
	GameSettings.set_tutorial_replay_requested(true)
	GameSettings.save_to_disk()
	GameSettings.load_from_disk()
	_expect(GameSettings.is_tutorial_replay_requested(), "replay 持久化")
	GameSettings.mark_tutorial_seen()
	_expect(GameSettings.is_tutorial_seen(), "seen 写入")
	_expect(not GameSettings.is_tutorial_replay_requested(), "seen 清 replay")

func _case_should_auto() -> void:
	_wipe_settings()
	GameSettings.load_from_disk()
	TutorialDirector.set_online_blocked(false)
	_expect(TutorialDirector.should_auto_show(), "未 seen 应自动开")
	GameSettings.mark_tutorial_seen()
	_expect(not TutorialDirector.should_auto_show(), "seen 后不自动开")
	GameSettings.set_tutorial_replay_requested(true)
	_expect(TutorialDirector.should_auto_show(), "replay 可自动开")
	TutorialDirector.set_online_blocked(true)
	_expect(not TutorialDirector.should_auto_show(), "联机不自动开")
	TutorialDirector.set_online_blocked(false)

func _case_step_flow() -> void:
	_wipe_settings()
	GameSettings.load_from_disk()
	GameSettings.set_tutorial_replay_requested(true)
	TutorialDirector.try_begin_on_main_menu()
	_expect(TutorialDirector.is_active(), "try_begin 激活")
	_expect(TutorialDirector.current_step() == TutorialDirector.Step.T00_WELCOME, "从欢迎开始")
	TutorialDirector.advance_from_host()
	TutorialDirector.advance_from_host()
	_expect(TutorialDirector.current_step() == TutorialDirector.Step.T01_HIGHLIGHT_SOLO, "欢迎后进 T01")
	TutorialDirector.notify_solo_rail_pressed()
	_expect(TutorialDirector.current_step() == TutorialDirector.Step.T02_CREATE_OR_PICK, "Solo 后进 T02")
	TutorialDirector.skip_all()
	_expect(not TutorialDirector.is_active(), "skip 结束")
	_expect(GameSettings.is_tutorial_seen(), "skip 写 seen")
	_expect(GameSettings.is_tutorial_skipped(), "skip 写 skipped")

func _case_multiplayer_marks_seen() -> void:
	_wipe_settings()
	GameSettings.load_from_disk()
	TutorialDirector.try_begin_on_main_menu()
	_expect(TutorialDirector.is_active(), "引导激活")
	TutorialDirector.on_multiplayer_entered()
	_expect(not TutorialDirector.is_active(), "联机卸层")
	_expect(GameSettings.is_tutorial_seen(), "联机写 seen")

func _case_replay_after_seen() -> void:
	## 回归：关设置时不得先清 replay，否则已 seen 时 try_begin 会空跑。
	_wipe_settings()
	GameSettings.load_from_disk()
	GameSettings.mark_tutorial_seen()
	TutorialDirector.request_replay()
	_expect(GameSettings.is_tutorial_replay_requested(), "replay 已请求")
	TutorialDirector.on_settings_closed(false)
	_expect(TutorialDirector.is_active(), "关设置后应激活引导")
	_expect(TutorialDirector.current_step() == TutorialDirector.Step.T00_WELCOME, "从欢迎重开")
	_expect(not GameSettings.is_tutorial_replay_requested(), "begin 后清 replay")

func _wipe_settings() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(SETTINGS)

func _expect(ok: bool, msg: String) -> void:
	if ok:
		return
	_failed += 1
	push_error("FAIL: %s" % msg)

extends SceneTree

## TutorialDirector + GameSettings 旗标。
const SETTINGS := "user://settings.cfg"

var _failed: int = 0

func _initialize() -> void:
	_case_flags_roundtrip()
	_case_should_auto()
	_case_step_flow()
	print("tutorial_director_test: %d failed" % _failed)
	quit()

func _case_flags_roundtrip() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and FileAccess.file_exists(SETTINGS):
		dir.remove(SETTINGS.get_file())
	GameSettings.load_from_disk()
	_expect(not GameSettings.is_tutorial_seen(), "默认未 seen")
	GameSettings.set_tutorial_replay_requested(true)
	GameSettings.save_to_disk()
	GameSettings.load_from_disk()
	_expect(GameSettings.is_tutorial_replay_requested(), "replay 持久化")
	GameSettings.mark_tutorial_seen()
	_expect(GameSettings.is_tutorial_seen(), "seen 写入")

func _case_should_auto() -> void:
	GameSettings.load_from_disk()
	GameSettings.mark_tutorial_seen()
	_expect(not TutorialDirector.should_auto_start_on_main_menu(), "seen 后不自动开")
	GameSettings.set_tutorial_replay_requested(true)
	_expect(TutorialDirector.should_auto_start_on_main_menu(), "replay 请求可自动开")

func _case_step_flow() -> void:
	GameSettings.set_tutorial_replay_requested(true)
	TutorialDirector.try_begin_on_main_menu()
	_expect(TutorialDirector.is_active(), "try_begin 激活")
	TutorialDirector.advance_from_host()
	TutorialDirector.advance_from_host()
	_expect(TutorialDirector.current_step() == TutorialDirector.Step.T01_OPEN_PLAY, "欢迎后进入 T01")
	TutorialDirector.notify_solo_rail_pressed()
	_expect(TutorialDirector.current_step() == TutorialDirector.Step.T02_CREATE_OR_PICK, "Solo 后进 T02")
	TutorialDirector.skip_all()
	_expect(not TutorialDirector.is_active(), "skip 结束")

func _expect(ok: bool, msg: String) -> void:
	if ok:
		return
	_failed += 1
	push_error("FAIL: %s" % msg)

"""Sinh toàn bộ nhạc + ambience + SFX thế giới cho Chick Fighter vào game/audio/.

Chạy:  python tools/audio/generate_audio.py <project_root> [--only tên1,tên2] [--no-analyze]
Tất định (seed cố định); chạy lại sẽ ghi đè cùng nội dung.
"""
from __future__ import annotations

import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import dsp  # noqa: E402
import music  # noqa: E402
import ambience  # noqa: E402
import world_sfx as ws  # noqa: E402

SFX_SR = 22050


def _oneshot(fn, peak_db):
	def run():
		x = fn()
		return dsp.fades(dsp.peak_normalize(x, peak_db), SFX_SR, 0.002, 0.01)
	return run


def _engine(rms_db, **kw):
	def run():
		x = ws.engine_loop(SFX_SR, **kw)
		return dsp.master(x[None, :], SFX_SR, rms_db, -1.0, drive=1.2, loop=True, hp_hz=25.0)[0]
	return run


# (tên file, hàm sinh, sample rate, loop?)
JOBS = [
	("music_village", lambda: music.village(32000), 32000, True),
	("music_title", lambda: music.title(24000), 24000, True),
	("music_memory", lambda: music.memory(24000), 24000, True),
	("music_battle", lambda: music.battle(24000), 24000, True),
	("music_final", lambda: music.final(24000), 24000, True),
	("jingle_victory", lambda: music.jingle_victory(24000), 24000, False),
	("jingle_defeat", lambda: music.jingle_defeat(24000), 24000, False),
	("jingle_reward", lambda: music.jingle_reward(24000), 24000, False),
	("amb_birds", lambda: ambience.birds(16.0), 22050, True),
	("amb_leaves", lambda: ambience.leaves(16.0), 22050, True),
	("amb_river", lambda: ambience.river(16.0), 22050, True),
	("amb_crickets", lambda: ambience.crickets(16.0), 22050, True),
	("amb_crowd", lambda: ambience.crowd(16.0), 22050, True),
	("amb_village", lambda: ambience.village(20.0), 22050, True),
	("loop_bike_idle", _engine(-18.0, fire_hz=25.0, cycles=75, kind="dream", seed=11), SFX_SR, True),
	("loop_bike_run", _engine(-17.0, fire_hz=82.0, cycles=246, kind="dream", seed=12, road=0.25), SFX_SR, True),
	("loop_npc_bike", _engine(-17.0, fire_hz=68.0, cycles=204, kind="npc", seed=13, road=0.2), SFX_SR, True),
	("loop_boat", _engine(-17.0, fire_hz=14.0, cycles=56, kind="boat", seed=14), SFX_SR, True),
	("sfx_bike_start", _oneshot(ws.bike_start, -3.0), SFX_SR, False),
	("sfx_bike_stop", _oneshot(ws.bike_stop, -4.0), SFX_SR, False),
	("sfx_bike_horn", _oneshot(ws.bike_horn, -4.0), SFX_SR, False),
	("sfx_step_dirt_1", _oneshot(lambda: ws.step_dirt(SFX_SR, 1), -10.0), SFX_SR, False),
	("sfx_step_dirt_2", _oneshot(lambda: ws.step_dirt(SFX_SR, 2), -10.0), SFX_SR, False),
	("sfx_step_dirt_3", _oneshot(lambda: ws.step_dirt(SFX_SR, 3), -10.0), SFX_SR, False),
	("sfx_step_wood_1", _oneshot(lambda: ws.step_wood(SFX_SR, 1), -9.0), SFX_SR, False),
	("sfx_step_wood_2", _oneshot(lambda: ws.step_wood(SFX_SR, 2), -9.0), SFX_SR, False),
	("sfx_splash_1", _oneshot(lambda: ws.splash(SFX_SR, 1, 1.0), -4.0), SFX_SR, False),
	("sfx_splash_2", _oneshot(lambda: ws.splash(SFX_SR, 2, 1.4), -3.0), SFX_SR, False),
	("sfx_fish_jump", _oneshot(ws.fish_jump, -6.0), SFX_SR, False),
	("sfx_coin", _oneshot(ws.coin, -6.0), SFX_SR, False),
	("sfx_harvest", _oneshot(ws.harvest, -6.0), SFX_SR, False),
	("sfx_brick", _oneshot(ws.brick, -5.0), SFX_SR, False),
	("sfx_school_bell", _oneshot(ws.school_bell, -3.0), SFX_SR, False),
	("sfx_temple_bell", _oneshot(ws.temple_bell, -5.0), SFX_SR, False),
	("sfx_rooster_crow", _oneshot(lambda: ws.rooster_crow(SFX_SR, 0), -3.0), SFX_SR, False),
	("sfx_ferry_creak", _oneshot(ws.ferry_creak, -6.0), SFX_SR, False),
	("sfx_paddle", _oneshot(ws.paddle, -6.0), SFX_SR, False),
	("sfx_ui_move", _oneshot(ws.ui_move, -12.0), SFX_SR, False),
	("sfx_ui_confirm", _oneshot(ws.ui_confirm, -9.0), SFX_SR, False),
	("sfx_dialog_blip", _oneshot(ws.dialog_blip, -14.0), SFX_SR, False),
	("sfx_levelup", _oneshot(ws.levelup, -4.0), SFX_SR, False),
]


def main(argv: list[str]) -> int:
	if len(argv) < 2:
		print(__doc__)
		return 2
	root = os.path.abspath(argv[1])
	out_dir = os.path.join(root, "game", "audio")
	os.makedirs(out_dir, exist_ok=True)
	only = None
	if "--only" in argv:
		only = set(argv[argv.index("--only") + 1].split(","))
	for i, (name, fn, sr, loop) in enumerate(JOBS):
		if only and name not in only:
			continue
		t0 = time.time()
		x = fn()
		path = os.path.join(out_dir, name + ".wav")
		dsp.write_wav(path, x, sr, loop=loop, seed=i)
		print(f"  wrote {name}.wav  ({time.time() - t0:.1f}s)")
	if "--no-analyze" not in argv:
		import analyze_audio
		return analyze_audio.main([argv[0], out_dir])
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv))

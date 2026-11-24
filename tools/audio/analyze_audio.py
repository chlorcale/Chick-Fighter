"""Phân tích file WAV đã sinh: thời lượng, sample rate, kênh, đỉnh, RMS, DC, điểm nối loop.

Chạy:  python tools/audio/analyze_audio.py <game/audio dir> [--spectro <out_dir> name1,name2,...]
Mã thoát 1 nếu có file clip, lệch DC, câm, hoặc điểm nối loop có click.
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

import dsp  # noqa: E402


def seam_metrics(x: np.ndarray, sr: int) -> tuple[float, float, float]:
	"""(|cuối−đầu| lớn nhất, bước nhảy tại seam / bước trung bình, RMS 10 ms qua seam / RMS file [dB])."""
	jump = float(np.max(np.abs(x[:, -1] - x[:, 0])))
	steps = np.abs(np.diff(x, axis=1))
	ratio = jump / (float(np.mean(steps)) + 1e-12)
	w = int(0.005 * sr)
	win = np.concatenate([x[:, -w:], x[:, :w]], axis=1)
	rel = dsp.rms_db(win) - dsp.rms_db(x)
	return jump, ratio, rel


def analyze(path: str) -> dict:
	sr, x, info = dsp.read_wav(path)
	name = os.path.splitext(os.path.basename(path))[0]
	loop = info["smpl"] is not None
	r = {
		"name": name, "sr": sr, "ch": x.shape[0], "dur": x.shape[1] / sr, "peak": dsp.peak_db(x),
		"rms": dsp.rms_db(x), "dc": float(np.max(np.abs(np.mean(x, axis=1)))), "loop": loop,
		"size": os.path.getsize(path), "smpl": info["smpl"], "frames": x.shape[1],
	}
	if loop:
		r["jump"], r["ratio"], r["seam_rel"] = seam_metrics(x, sr)
	problems = []
	if r["peak"] > -0.9:
		problems.append("peak>-1dBFS")
	if r["dc"] > 0.002:
		problems.append("DC")
	if r["rms"] < -50:
		problems.append("silent")
	if loop:
		if r["smpl"][2] != r["frames"]:
			problems.append("loop_end!=frames")
		# click: bước nhảy ở seam lớn bất thường so với bước trung bình của chính file
		if r["ratio"] > 8.0 and r["jump"] > 0.01:
			problems.append("seam click")
		if abs(r["seam_rel"]) > 12.0 and r["seam_rel"] > 0:
			problems.append("seam loud")
	else:
		edge = float(max(np.max(np.abs(x[:, :2])), np.max(np.abs(x[:, -2:]))))
		if edge > 0.003:
			problems.append("edge not faded")
	r["problems"] = problems
	return r


def spectrogram(path: str, out_png: str, fmax: float | None = None, seconds: float | None = None) -> None:
	import matplotlib
	matplotlib.use("Agg")
	import matplotlib.pyplot as plt
	sr, x, _ = dsp.read_wav(path)
	m = x.mean(axis=0)
	if seconds:
		m = m[:int(seconds * sr)]
	fig, ax = plt.subplots(figsize=(14, 5), dpi=100)
	nfft = 4096 if sr >= 24000 else 2048
	ax.specgram(m, NFFT=nfft, Fs=sr, noverlap=nfft * 3 // 4, cmap="magma", vmin=-130, vmax=-30)
	if fmax:
		ax.set_ylim(0, fmax)
	ax.set_title(os.path.basename(path))
	ax.set_xlabel("s")
	ax.set_ylabel("Hz")
	fig.tight_layout()
	fig.savefig(out_png)
	plt.close(fig)


def main(argv: list[str]) -> int:
	d = argv[1]
	files = sorted(f for f in os.listdir(d) if f.lower().endswith(".wav"))
	total = 0
	bad = 0
	print(f"{'file':<22}{'sr':>6}{'ch':>3}{'dur s':>8}{'peak':>7}{'rms':>7}{'dc':>8}{'size KB':>9}  seam(jump/ratio/rel dB)  status")
	for f in files:
		r = analyze(os.path.join(d, f))
		total += r["size"]
		seam = f"{r['jump']:.4f}/{r['ratio']:.2f}/{r['seam_rel']:+.1f}" if r["loop"] else "-"
		status = "OK" if not r["problems"] else "PROBLEM: " + ",".join(r["problems"])
		bad += bool(r["problems"])
		print(f"{r['name']:<22}{r['sr']:>6}{r['ch']:>3}{r['dur']:>8.2f}{r['peak']:>7.1f}{r['rms']:>7.1f}{r['dc']:>8.4f}"
			f"{r['size'] / 1024:>9.0f}  {seam:<24} {status}")
	print(f"TOTAL {len(files)} files, {total / 1024 / 1024:.1f} MB, {bad} with problems")
	if "--spectro" in argv:
		i = argv.index("--spectro")
		out = argv[i + 1]
		names = argv[i + 2].split(",")
		os.makedirs(out, exist_ok=True)
		for nm in names:
			spec = nm.split(":")
			fmax = float(spec[1]) if len(spec) > 1 and spec[1] else None
			secs = float(spec[2]) if len(spec) > 2 else None
			spectrogram(os.path.join(d, spec[0] + ".wav"), os.path.join(out, spec[0] + ".png"), fmax, secs)
			print("spectrogram:", os.path.join(out, spec[0] + ".png"))
	return 1 if bad else 0


if __name__ == "__main__":
	sys.exit(main(sys.argv))

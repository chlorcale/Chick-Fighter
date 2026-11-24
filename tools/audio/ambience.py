"""Âm thanh nền (ambience) loop liền mạch: chim, lá, sông, côn trùng, đám đông, làng xa.

Mọi lớp dựng trong bộ đệm vòng tròn (sự kiện vượt cuối được cộng về đầu, nhiễu định hình
bằng FFT, LFO có số chu kỳ nguyên) → điểm nối loop không có bước nhảy.
"""
from __future__ import annotations

import numpy as np

import dsp
from dsp import TAU, rng, rcos, fades, lp, hp, bp, reson

SR = 22050


def _env(n: int, sr: int, a: float, r: float) -> np.ndarray:
	e = np.ones(n)
	na = min(n, max(2, int(a * sr)))
	nr = min(n - na, max(2, int(r * sr)))
	e[:na] = rcos(na)
	if nr > 0:
		e[n - nr:] *= rcos(nr)[::-1]
	return e


def _tone(sr: int, f_curve: np.ndarray, harm=(1.0,), phase0: float = 0.0) -> np.ndarray:
	ph = TAU * np.cumsum(f_curve) / sr + phase0
	out = np.zeros_like(f_curve)
	for k, a in enumerate(harm, start=1):
		mask = np.clip((0.45 * sr - k * f_curve) / (0.05 * sr), 0, 1)
		out += a * mask * np.sin(k * ph)
	return out


def _finish(m: dsp.Mix, sr: int, target_rms: float, ir_params: dict | None, wet: float, ceiling: float = -3.0,
		mono: bool = False) -> np.ndarray:
	dry = sum(m.buses.values())
	out = dry
	if ir_params:
		out = dry + dsp.reverb(dry, dsp.make_ir(sr, **ir_params), True) * wet
	if mono:
		out = out.mean(axis=0, keepdims=True)
	return dsp.master(out, sr, target_rms, ceiling, drive=1.0, loop=True, hp_hz=30.0)


# ===================================================================== chim

def _chirp(sr, g, f0, f1, dur, harm2=0.12, trill=0.0):
	n = int(dur * sr)
	u = np.arange(n) / max(n - 1, 1)
	f = f0 * (f1 / f0) ** u
	if trill:
		f = f * (1.0 + trill * np.sin(TAU * g.uniform(25, 45) * np.arange(n) / sr))
	x = _tone(sr, f, (1.0, harm2))
	return x * np.sin(np.pi * u) ** 2


def _sparrow(sr, g):
	parts = []
	for _ in range(g.integers(5, 11)):
		f0 = g.uniform(4200, 6500)
		c = _chirp(sr, g, f0, f0 * g.uniform(0.55, 0.8), g.uniform(0.03, 0.07), 0.18)
		parts.append(c * g.uniform(0.5, 1.0))
		parts.append(np.zeros(int(g.uniform(0.025, 0.09) * sr)))
	return np.concatenate(parts)


def _dove(sr, g):
	"""Chim cu gáy: 'cúc cu… cu' trầm, âm ấm."""
	sylls = [(0.0, 0.13, 560, 520, 0.7), (0.19, 0.34, 610, 545, 1.0), (0.78, 0.42, 530, 470, 0.85)]
	total = int(1.3 * sr)
	out = np.zeros(total)
	base = g.uniform(0.92, 1.08)
	for t0, d, fa, fb, a in sylls:
		n = int(d * sr)
		u = np.arange(n) / n
		f = (fa + (fb - fa) * u ** 1.5) * base
		x = _tone(sr, f, (1.0, 0.22, 0.06)) * _env(n, sr, 0.045, 0.08) * a
		s = int(t0 * sr)
		out[s:s + n] += x
	return lp(out, 1800.0, sr)


def _robin(sr, g):
	"""Chích chòe: chuỗi tiếng huýt có luyến."""
	parts = []
	f = g.uniform(2200, 3200)
	for _ in range(g.integers(4, 8)):
		f_next = np.clip(f * g.choice([0.8, 0.9, 1.12, 1.25, 1.35]), 1800, 4800)
		d = g.uniform(0.07, 0.2)
		n = int(d * sr)
		u = np.arange(n) / n
		fc = f + (f_next - f) * u ** 2
		fc = fc * (1.0 + 0.025 * np.sin(TAU * g.uniform(20, 35) * np.arange(n) / sr) * g.uniform(0, 1))
		parts.append(_tone(sr, fc, (1.0, 0.06)) * _env(n, sr, 0.01, 0.025) * g.uniform(0.6, 1.0))
		parts.append(np.zeros(int(g.uniform(0.02, 0.08) * sr)))
		f = f_next
	return np.concatenate(parts)


def _bulbul(sr, g):
	"""Chào mào: cụm 3–5 âm líu lo lên xuống."""
	parts = []
	for _ in range(g.integers(3, 6)):
		d = g.uniform(0.09, 0.16)
		n = int(d * sr)
		u = np.arange(n) / n
		lo, hi = g.uniform(1500, 2100), g.uniform(2600, 3500)
		fc = lo + (hi - lo) * np.sin(np.pi * u * g.uniform(0.8, 1.6)) ** 2
		parts.append(_tone(sr, fc, (1.0, 0.2, 0.05)) * _env(n, sr, 0.008, 0.02) * g.uniform(0.6, 1.0))
		parts.append(np.zeros(int(g.uniform(0.01, 0.05) * sr)))
	return np.concatenate(parts)


def birds(seconds: float = 16.0, sr: int = SR) -> np.ndarray:
	g = rng(1001)
	n = int(seconds * sr)
	m = dsp.Mix(sr, n, True)
	# lớp xa: chíp chíp rất nhỏ, mờ
	for _ in range(40):
		c = _chirp(sr, g, g.uniform(3500, 6000), g.uniform(2500, 5000), g.uniform(0.03, 0.08))
		m.place("far", lp(c, 3500.0, sr) * g.uniform(0.04, 0.1), g.uniform(0, seconds), g.uniform(-0.9, 0.9))
	events = [("sparrow", 6), ("pair", 7), ("dove", 2), ("robin", 2), ("bulbul", 3)]
	for kind, count in events:
		times = (np.arange(count) + g.uniform(0.1, 0.9, count)) * seconds / count
		for t0 in times:
			pan = g.uniform(-0.85, 0.85)
			if kind == "sparrow":
				x = _sparrow(sr, g) * 0.32
			elif kind == "pair":
				f0 = g.uniform(3000, 5000)
				a = _chirp(sr, g, f0 * 0.8, f0 * 1.3, 0.06, trill=0.0)
				b = _chirp(sr, g, f0 * 1.2, f0 * 0.75, 0.09)
				x = np.concatenate([a, np.zeros(int(0.05 * sr)), b]) * 0.35
			elif kind == "dove":
				x = _dove(sr, g) * 0.55
				x = np.concatenate([x, np.zeros(int(0.5 * sr)), _dove(sr, g) * 0.5])
				pan *= 0.5
			elif kind == "robin":
				x = _robin(sr, g) * 0.3
			else:
				x = _bulbul(sr, g) * 0.32
			m.place("near", fades(x, sr, 0.005, 0.01), t0, pan)
	ir = dict(seconds=1.2, rt=(0.9, 0.8, 0.6, 0.4), seed=31, predelay=0.012, early=6)
	return _finish(m, sr, -27.0, ir, 0.22, ceiling=-4.0)


# ===================================================================== lá

def leaves(seconds: float = 16.0, sr: int = SR) -> np.ndarray:
	g = rng(1002)
	n = int(seconds * sr)
	m = dsp.Mix(sr, n, True)
	gust_main = dsp.periodic_lfo(n, sr, g, 0.22, 0.04)
	gust = 0.25 + 0.75 * np.clip(0.5 + 0.6 * gust_main, 0, 1) ** 1.6
	bands = [(250, 800, 0.9), (700, 2600, 0.7), (2400, 8000, 0.45)]
	for ch in range(2):
		chan = np.zeros(n)
		for lo, hi, a in bands:
			lfo = 0.5 + 0.5 * dsp.periodic_lfo(n, sr, g, 0.35, 0.05)
			noise = dsp.periodic_noise(n, sr, g, dsp.pink_band(lo, hi, 2.0, 0.3))
			chan += noise * a * gust * (0.6 + 0.4 * lfo)
		m.bus("wind")[ch] += chan * 0.2
	# tiếng lá khô lạo xạo: xung thưa, mật độ theo cơn gió
	kernel_n = int(0.004 * sr)
	kern = g.standard_normal(kernel_n) * np.exp(-np.arange(kernel_n) / (0.0008 * sr))
	for ch in range(2):
		rate = 260.0 * gust ** 2.2 / sr
		hits = g.random(n) < rate
		imp = np.zeros(n)
		imp[hits] = g.exponential(1.0, int(hits.sum())) * g.choice([-1.0, 1.0], int(hits.sum()))
		y = dsp.fold(np.convolve(imp, kern), n)
		y = hp(y, 1800.0, sr, 2, circular=True)
		m.bus("crackle")[ch] += y * 0.05
	# tàu dừa vỗ: cụm xung trầm ở đỉnh gió
	peaks = np.where((gust[1:-1] > gust[:-2]) & (gust[1:-1] >= gust[2:]) & (gust[1:-1] > 0.7))[0]
	for p in peaks:
		for k in range(g.integers(2, 5)):
			d = int(0.05 * sr)
			x = bp(g.standard_normal(d), 350.0, 1600.0, sr) * np.exp(-np.arange(d) / (0.012 * sr))
			m.place("slap", fades(x, sr, 0.003, 0.01) * 0.12, p / sr + k * g.uniform(0.07, 0.16), g.uniform(-0.7, 0.7))
	return _finish(m, sr, -29.0, None, 0.0)


# ===================================================================== sông

def _bubble(sr, g, f0, tau):
	d = min(0.15, tau * 5.0)
	n = int(d * sr)
	t = np.arange(n) / sr
	f = f0 * (1.0 + g.uniform(4.0, 14.0) * t)
	return fades(np.sin(TAU * np.cumsum(f) / sr) * np.exp(-t / tau), sr, 0.002, 0.005)


def river(seconds: float = 16.0, sr: int = SR) -> np.ndarray:
	g = rng(1003)
	n = int(seconds * sr)
	m = dsp.Mix(sr, n, True)
	swell = 0.6 + 0.4 * dsp.periodic_lfo(n, sr, g, 0.3, 0.05)
	for ch in range(2):
		low = dsp.periodic_noise(n, sr, g, dsp.pink_band(60, 450, 2.0, 0.4))
		mid = dsp.periodic_noise(n, sr, g, dsp.pink_band(300, 1400, 2.0, 0.2))
		mlfo = 0.5 + 0.5 * dsp.periodic_lfo(n, sr, g, 0.9, 0.2)
		m.bus("wash")[ch] += low * swell * 0.5 + mid * mlfo ** 2 * swell * 0.12
	t0 = 0.0
	while t0 < seconds:
		d = g.uniform(0.35, 0.7)
		k = int(d * sr)
		u = np.arange(k) / k
		env = np.sin(np.pi * u ** 0.6) ** 2
		x = bp(g.standard_normal(k), g.uniform(200, 350), g.uniform(700, 1300), sr) * env
		m.place("lap", x * g.uniform(0.12, 0.25), t0, g.uniform(-0.6, 0.6))
		t0 += g.uniform(0.7, 1.8)
	for _ in range(55):
		c = g.uniform(0, seconds)
		for j in range(g.integers(1, 4)):
			b = _bubble(sr, g, g.uniform(350, 1300), g.uniform(0.012, 0.035))
			m.place("bub", b * g.uniform(0.04, 0.11), c + j * g.uniform(0.02, 0.09), g.uniform(-0.8, 0.8))
	for _ in range(5):
		k = int(0.12 * sr)
		x = hp(g.standard_normal(k), 1500.0, sr) * np.exp(-np.arange(k) / (0.03 * sr))
		m.place("spl", fades(x, sr, 0.004, 0.01) * 0.06, g.uniform(0, seconds), g.uniform(-0.8, 0.8))
	ir = dict(seconds=1.0, rt=(0.8, 0.7, 0.5, 0.3), seed=33, predelay=0.01, early=4)
	return _finish(m, sr, -28.0, ir, 0.15)


# ===================================================================== côn trùng

def crickets(seconds: float = 16.0, sr: int = SR) -> np.ndarray:
	g = rng(1004)
	n = int(seconds * sr)
	m = dsp.Mix(sr, n, True)
	t = np.arange(n) / sr

	def q(f):  # làm tròn tần số → số chu kỳ nguyên trong loop
		return round(f * seconds) / seconds

	# dế mèn: cụm 3–4 xung, lặp đều
	for v in range(4):
		fc = q(g.uniform(4300, 5200))
		period = g.uniform(0.38, 0.7)
		count = max(1, round(seconds / period))
		period = seconds / count
		pulses = int(g.integers(3, 5))
		car = np.sin(TAU * fc * t + g.uniform(0, TAU))
		env = np.zeros(n)
		pl = int(0.016 * sr)
		pe = np.sin(np.pi * np.arange(pl) / pl) ** 2
		off = g.uniform(0, period)
		for c in range(count):
			base = off + c * period + g.normal(0, 0.004)
			for p in range(pulses):
				s = int((base + p * 0.03) * sr) % n
				idx = (s + np.arange(pl)) % n
				env[idx] += pe * (0.7 + 0.3 * (p == 1))
		dist = g.uniform(0.25, 0.9)
		m.place("crk", car * env * 0.08 * dist, 0.0, g.uniform(-0.9, 0.9))
	# dế cây: rung liên tục ~50 xung/ giây, biên độ trôi chậm
	for v in range(2):
		fc = q(g.uniform(2700, 3300))
		rate = q(g.uniform(42, 58))
		am = (0.5 + 0.5 * np.sin(TAU * rate * t)) ** 3
		slow = 0.5 + 0.5 * dsp.periodic_lfo(n, sr, g, 0.12, 0.02)
		m.place("tree", np.sin(TAU * fc * t) * am * slow * 0.035, 0.0, g.uniform(-0.6, 0.6))
	# châu chấu/ sâu đêm: 'xè' ngắn tần cao
	for _ in range(10):
		k = int(g.uniform(0.12, 0.25) * sr)
		x = bp(g.standard_normal(k), 6500.0, 9500.0, sr) * (0.5 + 0.5 * np.sin(TAU * 90 * np.arange(k) / sr)) ** 2
		m.place("kat", fades(x, sr, 0.01, 0.03) * 0.04, g.uniform(0, seconds), g.uniform(-0.9, 0.9))
	# ếch nhái 'ộp ộp' xa
	for _ in range(9):
		c = g.uniform(0, seconds)
		f0 = g.uniform(170, 300)
		for j in range(g.integers(2, 4)):
			k = int(g.uniform(0.09, 0.16) * sr)
			tt = np.arange(k) / sr
			f = f0 * (1.0 + 0.15 * np.exp(-tt / 0.03))
			src = _tone(sr, f, tuple(1.0 / (h ** 0.7) for h in range(1, 14)))
			x = reson(src, sr, g.uniform(550, 900), 3.0) + 0.4 * reson(src, sr, g.uniform(1300, 1900), 4.0)
			x = x * _env(k, sr, 0.008, 0.05)
			m.place("frog", lp(x, 2500.0, sr) * 0.12, c + j * g.uniform(0.18, 0.3), g.uniform(-0.7, 0.7))
	ir = dict(seconds=1.4, rt=(1.0, 0.9, 0.7, 0.4), seed=34, predelay=0.015, early=5)
	return _finish(m, sr, -28.0, ir, 0.3)


# ===================================================================== đám đông

VOWELS = [(700, 1200), (400, 2000), (300, 2300), (500, 900), (350, 800), (600, 1700), (450, 1500)]


def crowd(seconds: float = 16.0, sr: int = SR) -> np.ndarray:
	"""Tiếng ồn đám đông (walla) không thành lời: nhiều giọng tổng hợp lọc formant."""
	g = rng(1005)
	n = int(seconds * sr)
	m = dsp.Mix(sr, n, True)
	swell_t = [g.uniform(2, 6), g.uniform(9, 13)]
	tt = np.arange(n) / sr
	swell = np.ones(n)
	for s in swell_t:
		d = np.minimum(np.abs(tt - s), seconds - np.abs(tt - s))
		swell += 0.9 * np.exp(-(d / 0.9) ** 2)
	for v in range(34):
		f0 = g.uniform(95, 140) if v % 2 else g.uniform(170, 260)
		pan = g.uniform(-0.9, 0.9)
		dist = g.uniform(0.35, 1.0)
		t0 = g.uniform(0, seconds)
		t = 0.0
		while t < seconds:
			d = g.uniform(0.09, 0.28)
			k = int(d * sr)
			u = np.arange(k) / k
			idx = int(((t0 + t) % seconds) * sr)
			sw = swell[idx]
			f = f0 * sw ** 0.25 * (1.0 + 0.12 * np.sin(np.pi * u) * g.uniform(-1, 1))
			harm = tuple(1.0 / h for h in range(1, int(3500 / (f0 * 1.4))))
			src = _tone(sr, f, harm)
			f1, f2 = VOWELS[g.integers(len(VOWELS))]
			x = reson(src, sr, f1 * g.uniform(0.9, 1.1), 4.0) + 0.6 * reson(src, sr, f2 * g.uniform(0.9, 1.1), 6.0)
			x = x * np.sin(np.pi * u) ** 1.5 * g.uniform(0.5, 1.0) * sw
			m.place("v", x * dist * 0.05, t0 + t, pan)
			t += d + (g.uniform(0.02, 0.1) if g.random() < 0.85 else g.uniform(0.4, 1.2))
	for ch in range(2):
		bed = dsp.periodic_noise(n, sr, g, dsp.pink_band(200, 2500, 2.0, 0.3))
		m.bus("bed")[ch] += bed * swell * 0.025
	ir = dict(seconds=1.6, rt=(1.4, 1.2, 0.8, 0.4), seed=35, predelay=0.02)
	out = _finish(m, sr, -26.0, ir, 0.45)
	return lp(out, 5000.0, sr, 2, circular=True)


# ===================================================================== làng xa

def village(seconds: float = 20.0, sr: int = SR) -> np.ndarray:
	import world_sfx
	g = rng(1006)
	n = int(seconds * sr)
	m = dsp.Mix(sr, n, True)
	far = lambda x, f=2500.0: lp(x, f, sr, 2)
	crow = world_sfx.rooster_crow(sr, seed=77)
	m.place("ev", far(crow, 2800.0) * 0.18, 2.5, 0.0)
	for k, t0 in enumerate([10.6, 11.0, 11.55]):
		m.place("ev", far(world_sfx.dog_bark(sr, seed=80 + k), 2000.0) * 0.16, t0, 0.0)
	boat = world_sfx.engine_loop(sr, fire_hz=14.0, cycles=84, kind="boat", seed=91)
	k = boat.shape[-1]
	env = np.sin(np.pi * np.arange(k) / k) ** 2
	m.place("ev", far(boat, 700.0) * env * 0.12, 13.0, 0.0)
	for _ in range(8):
		c = _chirp(sr, g, g.uniform(3000, 5000), g.uniform(2500, 4500), g.uniform(0.04, 0.09))
		m.place("ev", far(c, 3000.0) * 0.06, g.uniform(0, seconds), 0.0)
	bed = dsp.periodic_noise(n, sr, g, dsp.pink_band(80, 900, 2.0, 0.5))
	m.bus("bed")[0] += bed * 0.012
	m.bus("bed")[1] += bed * 0.012
	ir = dict(seconds=1.5, rt=(1.2, 1.0, 0.6, 0.3), seed=36, predelay=0.03)
	return _finish(m, sr, -31.0, ir, 0.35, ceiling=-6.0, mono=True)

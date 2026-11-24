"""Xe cộ (xe Dream, xe máy NPC, ghe máy) và các âm thanh thế giới (one-shot)."""
from __future__ import annotations

import numpy as np

import dsp
from dsp import TAU, rng, rcos, fades, lp, hp, bp, reson, modal
import instruments as ins

SR = 22050

# ===================================================================== động cơ

ENGINE = {
	# xe Dream 4 thì: tiếng 'bùm bùm' tròn, ống pô có tiêu âm
	"dream": dict(res=[(160, 3.5, 1.0), (420, 4.5, 0.55), (1050, 3.0, 0.22), (2300, 2.5, 0.06)], tau=0.0011,
		combust=0.15, lp=2400.0, valve=0.04, mech=0.014, jitter=0.008, amp_var=0.10),
	# xe máy NPC: mũi hơn, rè hơn
	"npc": dict(res=[(210, 3.0, 0.9), (620, 5.5, 0.7), (1450, 4.0, 0.3), (2900, 3.0, 0.1)], tau=0.0009,
		combust=0.3, lp=3200.0, valve=0.07, mech=0.05, jitter=0.015, amp_var=0.14),
	# ghe máy đuôi tôm: pô hở, 'tạch tạch' giòn
	"boat": dict(res=[(120, 2.5, 1.0), (330, 3.0, 0.8), (900, 2.5, 0.5), (2100, 2.0, 0.25)], tau=0.0007,
		combust=0.6, lp=4500.0, valve=0.03, mech=0.03, jitter=0.02, amp_var=0.18),
}


def _pulse_kernel(sr: int, tau: float, combust: float, g: np.random.Generator) -> np.ndarray:
	n = int(0.02 * sr)
	t = np.arange(n) / sr
	p = (t / tau) * np.exp(1.0 - t / tau)
	p -= 0.45 * ((t / (tau * 2.6)) * np.exp(1.0 - t / (tau * 2.6)))
	nz = hp(g.standard_normal(n), 800.0, sr) * np.exp(-t / 0.003) * combust
	k = p + nz
	k[-int(0.003 * sr):] *= rcos(int(0.003 * sr))[::-1]
	return k


def _engine(sr: int, n: int, pulse_times: np.ndarray, amps: np.ndarray, kind: str, seed: int, circular: bool,
		rate_hz: np.ndarray | float) -> np.ndarray:
	"""Chuỗi xung nổ → bộ cộng hưởng ống xả + tiếng cơ khí (xu-páp, xích)."""
	c = ENGINE[kind]
	g = rng(seed)
	kern = _pulse_kernel(sr, c["tau"], c["combust"], g)
	imp = np.zeros(n)
	pos = np.round(pulse_times * sr).astype(int)
	if circular:
		pos %= n
	ok = (pos >= 0) & (pos < n)
	np.add.at(imp, pos[ok], amps[ok])
	y = np.convolve(imp, kern)
	y = dsp.fold(y, n) if circular else y[:n]
	out = lp(y, 900.0, sr, 2, circular) * 0.5
	for f, q, a in c["res"]:
		out += reson(y, sr, f, q, circular) * a
	out = lp(out, c["lp"], sr, 2, circular)
	# tiếng xu-páp gõ nhẹ (2 lần/ chu kỳ) + xích, nhiễu cơ khí điều biên theo nhịp nổ
	tick = np.zeros(n)
	rate = np.broadcast_to(np.asarray(rate_hz, float), (n,)) if np.ndim(rate_hz) else np.full(n, float(rate_hz))
	for frac in (0.32, 0.66):
		tp = pulse_times + frac / np.interp(np.clip(pulse_times * sr, 0, n - 1), np.arange(n), rate)
		pp = np.round(tp * sr).astype(int)
		if circular:
			pp %= n
		okp = (pp >= 0) & (pp < n)
		np.add.at(tick, pp[okp], g.uniform(0.5, 1.0, int(okp.sum())))
	tk = int(0.004 * sr)
	tkern = g.standard_normal(tk) * np.exp(-np.arange(tk) / (0.0008 * sr))
	tick = np.convolve(tick, tkern)
	tick = dsp.fold(tick, n) if circular else tick[:n]
	out += hp(tick, 3000.0, sr, 2, circular) * c["valve"]
	if circular:
		mech = dsp.periodic_noise(n, sr, g, dsp.band_shape(1500, 5000))
	else:
		mech = bp(g.standard_normal(n), 1500.0, 5000.0, sr)
	env = lp(np.abs(out), 60.0, sr, 1, circular)
	out += mech * c["mech"] * (0.4 + env / (np.max(env) + 1e-9))
	return out


def engine_loop(sr: int = SR, fire_hz: float = 25.0, cycles: int = 75, kind: str = "dream", seed: int = 0,
		road: float = 0.0) -> np.ndarray:
	"""Loop động cơ ổn định: số chu kỳ nổ nguyên → nối liền mạch, chịu được pitch ±25%."""
	c = ENGINE[kind]
	g = rng(seed)
	n = int(round(cycles / fire_hz * sr))
	period = n / sr / cycles
	jit = g.normal(0, c["jitter"] * period, cycles)
	jit -= np.mean(jit)
	times = (np.arange(cycles) + 0.5) * period + jit
	amps = 1.0 + c["amp_var"] * g.standard_normal(cycles)
	# nhịp không đều nhẹ, tuần hoàn trong loop (máy nổ 'ì ạch' chút ít)
	amps *= 1.0 + 0.08 * np.sin(TAU * np.arange(cycles) * 3 / cycles)
	out = _engine(sr, n, times, amps, kind, seed + 1, True, fire_hz)
	if kind == "boat":
		# 2 thì: tiếng 'tạch' phụ nửa chu kỳ + nước xoáy chân vịt
		out += _engine(sr, n, times + period * 0.5, amps * 0.22, kind, seed + 2, True, fire_hz) * 0.8
		wash = dsp.periodic_noise(n, sr, g, dsp.pink_band(150, 1500, 2.0, 0.3))
		t = np.arange(n) / sr
		churn = 0.6 + 0.4 * np.sin(TAU * fire_hz * t) ** 2
		swell = 0.7 + 0.3 * np.sin(TAU * 1 * t / (n / sr))
		out += wash * churn * swell * 0.18 * np.std(out)
		spray = dsp.periodic_noise(n, sr, g, dsp.band_shape(2500, 8000))
		out += spray * 0.04 * np.std(out)
	if road > 0:
		rn = dsp.periodic_noise(n, sr, g, dsp.pink_band(40, 400, 2.0, 0.3))
		out += rn * road * np.std(out)
	return out


def engine_sweep(sr: int, rate_pts, amp_pts, dur: float, kind: str = "dream", seed: int = 0) -> np.ndarray:
	"""Động cơ đổi vòng tua (khởi động/ tắt máy) theo các điểm (giây, Hz) và (giây, biên độ)."""
	n = int(dur * sr)
	t = np.arange(n) / sr
	rate = np.interp(t, [p[0] for p in rate_pts], [p[1] for p in rate_pts])
	amp = np.interp(t, [p[0] for p in amp_pts], [p[1] for p in amp_pts])
	cyc = np.cumsum(rate) / sr
	idx = np.where(np.floor(cyc[1:]) > np.floor(cyc[:-1]))[0] + 1
	idx = idx[amp[idx] > 0.01]
	g = rng(seed)
	amps = amp[idx] * (1.0 + 0.1 * g.standard_normal(idx.shape[0]))
	return _engine(sr, n, idx / sr, amps, kind, seed + 1, False, rate)


def _clunk(sr: int, g, vel: float = 1.0) -> np.ndarray:
	body = modal(sr, 0.18, [140.0, 310.0, 870.0, 2300.0], [0.05, 0.03, 0.015, 0.006], [1.0, 0.6, 0.4, 0.3], g)
	m = int(0.01 * sr)
	body[:m] += hp(g.standard_normal(m), 1500.0, sr) * np.exp(-np.arange(m) / (0.002 * sr)) * 0.6
	return body * vel


def bike_start(sr: int = SR) -> np.ndarray:
	g = rng(2001)
	dur = 1.3
	n = int(dur * sr)
	out = np.zeros(n)
	for t0, v in [(0.0, 0.7), (0.07, 0.4)]:
		c = _clunk(sr, g, v)
		s = int(t0 * sr)
		out[s:s + c.shape[0]] += c[:n - s]
	# cần đạp + bánh răng
	rk = int(0.18 * sr)
	ratchet = np.zeros(rk)
	for i in range(7):
		p = int((0.012 + i * 0.022) * sr)
		ratchet[p:p + 30] += np.exp(-np.arange(30) / 6.0)
	ratchet = hp(np.convolve(ratchet, g.standard_normal(40))[:rk], 2500.0, sr) * 0.08
	out[int(0.03 * sr):int(0.03 * sr) + rk] += ratchet
	eng = engine_sweep(sr, [(0.0, 0.0), (0.2, 0.0), (0.21, 11.0), (0.32, 28.0), (0.55, 68.0), (0.7, 60.0), (1.0, 27.0), (1.3, 25.0)],
		[(0.0, 0.0), (0.2, 0.0), (0.21, 0.5), (0.4, 0.9), (0.6, 1.0), (0.9, 0.75), (1.3, 0.7)], dur, "dream", 2002)
	out += eng / (np.max(np.abs(eng)) + 1e-9) * 0.9
	return fades(out, sr, 0.003, 0.06)


def bike_stop(sr: int = SR) -> np.ndarray:
	dur = 0.65
	eng = engine_sweep(sr, [(0.0, 25.0), (0.25, 17.0), (0.5, 9.0), (0.65, 6.0)],
		[(0.0, 0.75), (0.25, 0.6), (0.45, 0.35), (0.55, 0.1), (0.6, 0.0)], dur, "dream", 2003)
	g = rng(2004)
	out = eng / (np.max(np.abs(eng)) + 1e-9)
	c = _clunk(sr, g, 0.12)
	s = int(0.52 * sr)
	out[s:s + c.shape[0]] += c[:out.shape[0] - s]
	return fades(out, sr, 0.003, 0.08)


def bike_horn(sr: int = SR) -> np.ndarray:
	"""Còi điện xe máy 'tin tin': màng rung giàu hài, cộng hưởng loa còi."""
	g = rng(2005)
	out = np.zeros(int(0.55 * sr))
	for t0, d in [(0.0, 0.15), (0.24, 0.2)]:
		n = int(d * sr)
		t = np.arange(n) / sr
		f = 432.0 * (1.0 + 0.015 * (1.0 - np.exp(-t / 0.02)))
		ph = TAU * np.cumsum(f) / sr
		x = np.zeros(n)
		k = 1
		while k * 440.0 < 0.44 * sr:
			x += np.sin(k * ph + g.uniform(0, TAU)) / k ** 0.75
			k += 1
		x = dsp.saturate(x * 0.8, 2.0)
		x = reson(x, sr, 2400.0, 3.0) + 0.7 * reson(x, sr, 3400.0, 4.0) + 0.3 * x
		x = fades(x, sr, 0.005, 0.02)
		s = int(t0 * sr)
		out[s:s + n] += x
	return lp(out, 7000.0, sr)


# ===================================================================== tiếng gà gáy, chó sủa

def rooster_crow(sr: int = SR, seed: int = 0) -> np.ndarray:
	"""'Ò ó o o': nguồn hài có cao độ thay đổi, formant quét theo thời gian, độ khàn."""
	g = rng(3000 + seed)
	dur = 1.55
	n = int(dur * sr)
	t = np.arange(n) / sr
	f0 = np.interp(t, [0.0, 0.16, 0.19, 0.38, 0.41, 0.6, 0.86, 0.89, 1.15, 1.35, 1.55],
		[480, 560, 560, 790, 760, 800, 740, 720, 640, 430, 400]) * g.uniform(0.95, 1.05)
	f0 = f0 * (1.0 + 0.012 * lp(g.standard_normal(n), 30.0, sr) / 0.1)
	syll = [(0.0, 0.17, 0.75), (0.19, 0.39, 0.95), (0.41, 0.86, 1.0), (0.89, 1.38, 0.8)]
	amp = np.zeros(n)
	for a, b, v in syll:
		sa, sb = int(a * sr), int(b * sr)
		e = np.ones(sb - sa)
		na = int(0.018 * sr)
		nr = int((0.04 if b < 1.0 else 0.25) * sr)
		e[:na] = rcos(na)
		e[-nr:] *= rcos(nr)[::-1]
		if b > 1.0:
			e *= np.linspace(1.0, 0.6, sb - sa)
		amp[sa:sb] = np.maximum(amp[sa:sb], e * v)
	F1 = np.interp(t, [0, 0.19, 0.41, 0.9, 1.4], [850, 1250, 1150, 1050, 800])
	F2 = np.interp(t, [0, 0.19, 0.41, 0.9, 1.4], [2100, 2800, 2600, 2400, 1900])
	F3 = np.full(n, 3700.0)
	ph = TAU * np.cumsum(f0) / sr
	src = np.zeros(n)
	for k in range(1, 30):
		fk = k * f0
		if np.min(fk) > 0.45 * sr:
			break
		mask = np.clip((0.45 * sr - fk) / 500.0, 0, 1)
		h = sum(w / (1.0 + ((fk - F) / (bw / 2.0)) ** 2) for F, bw, w in ((F1, 500.0, 1.0), (F2, 650.0, 0.7), (F3, 900.0, 0.25)))
		src += mask * (h + 0.04) * np.sin(k * ph + g.uniform(0, TAU)) / k ** 0.6
	# khàn: điều biên + hạ bồi ở các âm dài
	rough = 1.0 + 0.35 * np.sin(TAU * 46.0 * t + 2.0 * lp(g.standard_normal(n), 20.0, sr) / 0.1)
	rough = np.where(t > 0.41, rough, 1.0 + 0.1 * (rough - 1.0))
	sub = 0.15 * np.sin(ph / 2.0) * (t > 0.41)
	asp = bp(g.standard_normal(n), 1200.0, 4500.0, sr) * 0.05
	out = (src * rough + sub + asp) * amp
	out = lp(hp(out, 300.0, sr, 2), 6000.0, sr, 2)
	return fades(out / (np.max(np.abs(out)) + 1e-9), sr, 0.005, 0.05)


def dog_bark(sr: int = SR, seed: int = 0) -> np.ndarray:
	g = rng(3100 + seed)
	d = 0.22
	n = int(d * sr)
	t = np.arange(n) / sr
	f0 = np.interp(t, [0, 0.03, 0.12, 0.22], [380, 560, 450, 300]) * g.uniform(0.9, 1.1)
	ph = TAU * np.cumsum(f0) / sr
	src = sum(np.sin(k * ph) / k ** 0.6 for k in range(1, 18) if k * 560 < 0.45 * sr)
	x = reson(src, sr, 900.0, 3.0) + 0.6 * reson(src, sr, 1800.0, 4.0) + 0.2 * bp(g.standard_normal(n), 500, 3000, sr)
	env = np.exp(-np.maximum(0, t - 0.03) / 0.06) * np.minimum(1.0, t / 0.01)
	return fades(x * env, sr, 0.004, 0.02)


# ===================================================================== one-shot thế giới

def _noise_burst(sr, g, dur, lo, hi, tau, attack=0.002):
	n = int(dur * sr)
	t = np.arange(n) / sr
	x = bp(g.standard_normal(n), lo, hi, sr) * np.exp(-t / tau)
	return fades(x, sr, attack, 0.01)


def _place(out, x, t0, sr, gain=1.0):
	s = int(t0 * sr)
	k = min(x.shape[0], out.shape[0] - s)
	if k > 0:
		out[s:s + k] += x[:k] * gain


def step_dirt(sr: int = SR, seed: int = 0) -> np.ndarray:
	g = rng(4000 + seed)
	out = np.zeros(int(0.2 * sr))
	_place(out, _noise_burst(sr, g, 0.09, 150, 1600, 0.02, 0.003), 0.0, sr, 1.0)
	_place(out, _noise_burst(sr, g, 0.1, 400, 3500, 0.025, 0.003), g.uniform(0.025, 0.04), sr, 0.7)
	for _ in range(14):
		_place(out, _noise_burst(sr, g, 0.01, 2500, 8000, 0.0015, 0.001), g.uniform(0.005, 0.12), sr, g.uniform(0.1, 0.35))
	out += lp(g.standard_normal(out.shape[0]), 200.0, sr) * np.exp(-np.arange(out.shape[0]) / sr / 0.015) * 0.6
	return fades(out, sr, 0.003, 0.03)


def step_wood(sr: int = SR, seed: int = 0) -> np.ndarray:
	g = rng(4100 + seed)
	j = g.uniform(0.92, 1.08)
	out = np.zeros(int(0.25 * sr))
	knock = modal(sr, 0.2, np.array([175.0, 410.0, 760.0, 1300.0]) * j, [0.06, 0.035, 0.02, 0.01], [1.0, 0.7, 0.4, 0.2], g, 0.002)
	_place(out, knock, 0.0, sr)
	_place(out, _noise_burst(sr, g, 0.03, 800, 5000, 0.004), 0.0, sr, 0.5)
	_place(out, knock * 0.4, g.uniform(0.03, 0.045), sr)
	return fades(out, sr, 0.003, 0.03)


def splash(sr: int = SR, seed: int = 0, size: float = 1.0) -> np.ndarray:
	g = rng(4200 + seed)
	dur = 0.6 + 0.3 * size
	n = int(dur * sr)
	t = np.arange(n) / sr
	impact = bp(g.standard_normal(n), 350 / size, 6000, sr) * np.exp(-t / (0.06 * size)) * np.minimum(1, t / 0.004)
	spray = hp(g.standard_normal(n), 2000.0, sr) * np.exp(-t / (0.2 * size)) * np.minimum(1, t / 0.03) * 0.35
	out = impact + spray
	for _ in range(int(25 * size)):
		f = g.uniform(300, 1400) / size ** 0.5
		b = _bubble(sr, g, f, g.uniform(0.01, 0.03))
		_place(out, b, g.uniform(0.02, dur * 0.7), sr, g.uniform(0.05, 0.2))
	return fades(out, sr, 0.003, 0.08)


def _bubble(sr, g, f0, tau):
	d = min(0.15, tau * 5.0)
	n = int(d * sr)
	t = np.arange(n) / sr
	f = f0 * (1.0 + g.uniform(4.0, 14.0) * t)
	return fades(np.sin(TAU * np.cumsum(f) / sr) * np.exp(-t / tau), sr, 0.002, 0.005)


def fish_jump(sr: int = SR) -> np.ndarray:
	g = rng(4300)
	out = np.zeros(int(0.55 * sr))
	n = int(0.06 * sr)
	t = np.arange(n) / sr
	plop = np.sin(TAU * np.cumsum(260 * (1 + 25 * t)) / sr) * np.exp(-t / 0.02)
	_place(out, fades(plop, sr, 0.002, 0.005), 0.0, sr, 0.8)
	_place(out, splash(sr, 7, 0.45), 0.02, sr, 0.6)
	for k in range(4):
		_place(out, _bubble(sr, g, g.uniform(900, 1800), 0.012), 0.25 + k * g.uniform(0.04, 0.07), sr, 0.15)
	return fades(out, sr, 0.003, 0.05)


def coin(sr: int = SR) -> np.ndarray:
	g = rng(4400)
	out = np.zeros(int(0.6 * sr))
	for t0, f in [(0.0, 1975.5), (0.075, 2637.0)]:
		x = modal(sr, 0.5, [f, f * 2.76, f * 5.4], [0.22, 0.08, 0.03], [1.0, 0.35, 0.12], g, 0.002)
		_place(out, x, t0, sr)
	_place(out, _noise_burst(sr, g, 0.01, 3000, 9000, 0.002), 0.0, sr, 0.3)
	return fades(out, sr, 0.002, 0.05)


def harvest(sr: int = SR) -> np.ndarray:
	"""Liềm cắt lúa: 'xoẹt' + bó lúa gãy lạo xạo."""
	g = rng(4500)
	dur = 0.45
	n = int(dur * sr)
	t = np.arange(n) / sr
	sw = np.zeros(n)
	sn = int(0.16 * sr)
	u = np.arange(sn) / sn
	noise = g.standard_normal(sn)
	lo = bp(noise, 1200, 2500, sr)
	hi = bp(noise, 3000, 7000, sr)
	sw[:sn] = (lo * (1 - u) + hi * u) * np.sin(np.pi * u) ** 2
	out = sw * 0.8
	for _ in range(30):
		_place(out, _noise_burst(sr, g, 0.006, 2000, 8000, 0.0012, 0.001), 0.09 + g.uniform(0, 0.08), sr, g.uniform(0.2, 0.6))
	out += hp(g.standard_normal(n), 2500.0, sr) * np.exp(-np.maximum(0, t - 0.15) / 0.08) * (t > 0.12) * 0.12
	return fades(out, sr, 0.004, 0.05)


def brick(sr: int = SR) -> np.ndarray:
	g = rng(4600)
	out = np.zeros(int(0.35 * sr))
	_place(out, modal(sr, 0.25, [165.0, 420.0, 960.0, 1900.0], [0.05, 0.03, 0.015, 0.008], [1.0, 0.6, 0.35, 0.2], g, 0.002), 0.0, sr)
	_place(out, _noise_burst(sr, g, 0.08, 100, 700, 0.025), 0.0, sr, 0.9)
	for _ in range(16):
		_place(out, _noise_burst(sr, g, 0.008, 2500, 8000, 0.0015, 0.001), g.uniform(0.01, 0.07), sr, g.uniform(0.05, 0.2))
	return fades(out, sr, 0.003, 0.04)


def school_bell(sr: int = SR) -> np.ndarray:
	"""Trống trường 'tùng tùng tùng'."""
	out = np.zeros(int(2.5 * sr))
	for i, t0 in enumerate([0.0, 0.55, 1.1]):
		x = ins.trong(sr, f0=78.0, vel=0.9 if i < 2 else 1.0, seed=4700 + i, tau=0.5, dur=1.3, slap=0.5)
		_place(out, x, t0, sr)
	st = np.vstack([out, out])
	wet = dsp.reverb(st, dsp.make_ir(sr, 1.4, (1.2, 1.0, 0.6, 0.3), 0.02, 41), False)
	return fades(out + wet.mean(axis=0) * 0.35, sr, 0.003, 0.2)


def temple_bell(sr: int = SR) -> np.ndarray:
	return ins.bowl(sr, f0=392.0, vel=0.9, seed=4800, dur=4.0)


def ferry_creak(sr: int = SR) -> np.ndarray:
	"""Đò gỗ kẽo kẹt: ma sát dính-trượt kích các mode gỗ + nước vỗ mạn."""
	g = rng(4900)
	dur = 1.2
	n = int(dur * sr)
	t = np.arange(n) / sr
	rate = np.interp(t, [0, 0.15, 0.45, 0.75, 0.9], [35, 90, 120, 60, 30])
	cyc = np.cumsum(rate * (1 + 0.15 * g.standard_normal(n))) / sr
	imp = np.zeros(n)
	idx = np.where(np.floor(cyc[1:]) > np.floor(cyc[:-1]))[0] + 1
	imp[idx] = g.uniform(0.5, 1.0, idx.shape[0])
	env = np.interp(t, [0, 0.08, 0.6, 0.85, 0.95], [0, 1, 0.9, 0.3, 0])
	imp *= env
	creak = sum(reson(imp, sr, f, q) * a for f, q, a in [(330, 9, 1.0), (690, 10, 0.8), (1250, 8, 0.5), (2300, 6, 0.25)])
	water = bp(g.standard_normal(n), 200, 900, sr) * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2 * 0.06
	return fades(creak * 3.0 + water, sr, 0.005, 0.1)


def paddle(sr: int = SR) -> np.ndarray:
	g = rng(5000)
	dur = 0.8
	n = int(dur * sr)
	t = np.arange(n) / sr
	u = np.clip(t / 0.35, 0, 1)
	noise = g.standard_normal(n)
	sw = (bp(noise, 250, 700, sr) * (1 - u) + bp(noise, 600, 1600, sr) * u) * np.sin(np.pi * u) ** 2
	out = sw * 0.6
	for _ in range(10):
		_place(out, _bubble(sr, g, g.uniform(350, 900), g.uniform(0.015, 0.03)), g.uniform(0.12, 0.4), sr, g.uniform(0.1, 0.25))
	for k in range(3):
		_place(out, _bubble(sr, g, g.uniform(1200, 2200), 0.01), 0.48 + k * g.uniform(0.05, 0.09), sr, 0.12)
	return fades(out, sr, 0.005, 0.05)


def ui_move(sr: int = SR) -> np.ndarray:
	g = rng(5100)
	return modal(sr, 0.08, [1650.0, 2580.0, 4100.0], [0.022, 0.012, 0.006], [1.0, 0.45, 0.2], g, 0.002)


def ui_confirm(sr: int = SR) -> np.ndarray:
	out = np.zeros(int(0.55 * sr))
	_place(out, ins.pluck(sr, 783.99, 0.6, ring=0.6, seed=5201), 0.0, sr)
	_place(out, ins.pluck(sr, 1046.5, 0.7, ring=0.5, seed=5202), 0.07, sr)
	return fades(out, sr, 0.005, 0.08)


def dialog_blip(sr: int = SR) -> np.ndarray:
	n = int(0.075 * sr)
	t = np.arange(n) / sr
	f = 640.0 * (1.0 - 0.04 * t / 0.075)
	ph = TAU * np.cumsum(f) / sr
	x = (np.sin(ph) + 0.18 * np.sin(2 * ph)) * np.exp(-t / 0.028)
	return fades(x, sr, 0.005, 0.015)


def levelup(sr: int = SR) -> np.ndarray:
	out = np.zeros(int(1.5 * sr))
	notes = [523.25, 587.33, 698.46, 783.99, 880.0, 1046.5, 1174.7, 1396.9]
	for i, f in enumerate(notes):
		_place(out, ins.pluck(sr, f, 0.45 + 0.05 * i, ring=1.0, seed=5300 + i), i * 0.055, sr)
	_place(out, ins.bowl(sr, 1046.5, 0.5, seed=5310, dur=1.0, bright=0.5), 0.45, sr)
	_place(out, ins.bowl(sr, 1568.0, 0.3, seed=5311, dur=0.9, bright=0.4), 0.47, sr)
	st = np.vstack([out, out])
	wet = dsp.reverb(st, dsp.make_ir(sr, 1.0, (0.9, 0.8, 0.5, 0.3), 0.01, 42), False)
	return fades(out + wet.mean(axis=0) * 0.25, sr, 0.003, 0.15)

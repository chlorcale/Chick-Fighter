"""Nhạc cụ tổng hợp: đàn tranh, đàn kìm, đàn bầu, sáo trúc, bass, pad, bộ gõ.

Tất cả là tổng hợp cộng (additive/modal) có giới hạn băng tần: không alias,
đường bao cosine mềm (≥ 5 ms cho nốt có cao độ).
"""
from __future__ import annotations

import numpy as np
from dsp import TAU, rng, hz, fades, rcos, lp, hp, bp, peq, reson, modal

# ------------------------------------------------------------------ dây gảy (tranh / kìm)


def pluck(sr: int, freq: float, vel: float = 0.8, ring: float = 2.6, bend=None, seed: int = 0,
		pos: float = 0.19, tau_scale: float = 1.0, bright: float = 1.0, partials: int = 18,
		detune_cents: float = 2.5, noise: float = 0.05, inharm: float = 1.2e-4) -> np.ndarray:
	"""Dây gảy modal (kiểu đàn tranh). bend = [(giây, nửa cung), ...] — nhấn/ láy sau khi gảy."""
	g = rng(seed)
	tau1 = float(np.clip(2.0 * (196.0 / freq) ** 0.55, 0.45, 3.2)) * tau_scale
	dur = min(ring, tau1 * 4.5)
	n = max(int(dur * sr), int(0.06 * sr))
	t = np.arange(n) / sr
	if bend:
		bt = [b[0] for b in bend]
		bs = [b[1] for b in bend]
		semis = np.interp(t, bt, bs)
	else:
		semis = np.zeros(n)
	f = freq * 2.0 ** (semis / 12.0)
	ph = TAU * np.cumsum(f) / sr
	fmax = float(np.max(f))
	out = np.zeros(n)
	norm = 0.0
	ratio = 2.0 ** (detune_cents / 1200.0)
	for k in range(1, partials + 1):
		ke = k * np.sqrt(1.0 + inharm * k * k)
		if ke * fmax * ratio > 0.42 * sr:
			break
		a = abs(np.sin(np.pi * k * pos)) / k ** 0.85 * np.exp(-(k - 1) * 0.09 * (1.7 - vel * bright))
		tau = tau1 / (1.0 + 0.45 * (k - 1) ** 1.3)
		e1 = np.exp(-t / tau)
		e2 = np.exp(-t / (tau * 0.8))
		out += a * (e1 * np.sin(ke * ph + g.uniform(0, TAU)) + 0.33 * e2 * np.sin(ke * ph * ratio + g.uniform(0, TAU)))
		norm += a
	out /= max(norm, 1e-9) * 0.75
	m = min(n, int(0.015 * sr))
	nz = g.standard_normal(m) * np.exp(-np.arange(m) / (0.0025 * sr))
	nz = hp(nz, 2200.0, sr)
	out[:m] += noise * nz * 3.0
	return fades(out * vel, sr, 0.005, 0.04)


def kim(sr: int, freq: float, vel: float = 0.8, seed: int = 0, ring: float = 1.2, bend=None) -> np.ndarray:
	"""Đàn kìm (nguyệt cầm): gảy gần ngựa đàn → tiếng 'tưng' sáng, tắt nhanh."""
	return pluck(sr, freq, vel, ring=ring, bend=bend, seed=seed, pos=0.11, tau_scale=0.42, bright=1.3,
		partials=14, detune_cents=4.0, noise=0.07)


# ------------------------------------------------------------------ nhạc cụ hơi/ dây kéo cao độ (bầu, sáo)

LEAD = {
	"bau": dict(harm=[1.0, 0.20, 0.10, 0.05, 0.025, 0.012], bright_floor=0.45, bright_tau=0.3,
		glide=0.045, glide_slur=0.11, nhan_depth=2.0, nhan_time=0.20, dip=1.6,
		vib=0.16, vib_deep=0.42, vib_rate=4.6, vib_delay=0.22, attack=0.006, release=0.14,
		decay_tau=0.35, sustain=0.62, slow_tau=4.5, grace=2.0),
	"sao": dict(harm=[1.0, 0.24, 0.085, 0.05, 0.02], bright_floor=1.0, bright_tau=0.3,
		glide=0.028, glide_slur=0.06, nhan_depth=1.0, nhan_time=0.12, dip=0.9,
		vib=0.11, vib_deep=0.24, vib_rate=5.4, vib_delay=0.28, attack=0.045, release=0.09,
		decay_tau=0.25, sustain=0.88, slow_tau=8.0, grace=2.0),
	# sáo trúc cho nhạc quê hương: hơi thở rõ, vuốt nhẹ vào nốt, rung muộn 5–6 Hz, dịu ở 2–4 kHz
	"sao_tr": dict(harm=[1.0, 0.16, 0.05, 0.025, 0.01], bright_floor=1.0, bright_tau=0.3,
		glide=0.035, glide_slur=0.075, nhan_depth=1.0, nhan_time=0.14, dip=0.8,
		vib=0.12, vib_deep=0.26, vib_rate=5.3, vib_delay=0.42, attack=0.055, release=0.11,
		decay_tau=0.3, sustain=0.86, slow_tau=7.0, grace=2.0, scoop=0.4, scoop_time=0.075,
		breath=0.3, hiss=0.05, chiff=0.3, lp=5200.0, tame_db=-3.5),
}

BREATHY = ("sao", "sao_tr")


def lead_phrase(sr: int, notes: list[dict], kind: str = "bau", seed: int = 0) -> np.ndarray:
	"""Một câu nhạc liền hơi: portamento giữa nốt, rung (vibrato), nhấn (^), luyến (_),
	láy hoa mỹ (g), luyến xuống cuối nốt (v), rung sâu (~). notes: t, d (giây), m (midi), v, orn, slur."""
	c = LEAD[kind]
	g = rng(seed)
	end = max(nt["t"] + nt["d"] for nt in notes) + c["release"] + 0.45
	n = int(end * sr)
	t = np.arange(n) / sr
	pitch = np.full(n, notes[0]["m"], dtype=float)
	vib = np.zeros(n)
	starts = [int(nt["t"] * sr) for nt in notes]
	for i, nt in enumerate(notes):
		s = starts[i]
		e_next = starts[i + 1] if i + 1 < len(notes) else n
		e_note = min(n, int((nt["t"] + nt["d"]) * sr))
		pitch[s:e_next] = nt["m"]
		orn = nt.get("orn", "")
		if i > 0:
			prev = notes[i - 1]
			gap = nt["t"] - (prev["t"] + prev["d"])
			if gap < 0.06:
				gl = c["glide_slur"] if prev.get("slur") else c["glide"]
				gn = min(int(gl * sr), e_next - s)
				if gn > 1:
					pitch[s:s + gn] = prev["m"] + (nt["m"] - prev["m"]) * rcos(gn)
		if "^" in orn:
			bn = min(int(c["nhan_time"] * sr), e_next - s)
			u = np.arange(bn) / max(bn, 1)
			pitch[s:s + bn] = nt["m"] - c["nhan_depth"] * (1.0 - u) ** 2
		if c.get("scoop") and "^" not in orn and "g" not in orn and "o" not in orn:
			# sáo: vuốt nhẹ từ dưới vào nốt khi bắt đầu hơi mới (không áp cho nốt luyến liền)
			fresh = i == 0 or nt["t"] - (notes[i - 1]["t"] + notes[i - 1]["d"]) >= 0.06
			if fresh:
				sn = min(int(c["scoop_time"] * sr), e_next - s)
				u = np.arange(sn) / max(sn, 1)
				pitch[s:s + sn] -= c["scoop"] * (1.0 - u) ** 2
		if "o" in orn:
			# láy quãng tám: chạm nhanh nốt cao hơn một quãng tám rồi rơi về nốt chính
			on = min(int(0.05 * sr), e_next - s)
			fn = min(int(0.03 * sr), e_next - s - on)
			pitch[s:s + on] = nt["m"] + 12.0
			if fn > 1:
				pitch[s + on:s + on + fn] = nt["m"] + 12.0 * (1.0 - rcos(fn))
		if "g" in orn:
			gn = min(int(0.075 * sr), e_next - s)
			fn = min(int(0.04 * sr), e_next - s - gn)
			pitch[s:s + gn] = nt["m"] + c["grace"]
			if fn > 1:
				pitch[s + gn:s + gn + fn] = nt["m"] + c["grace"] * (1.0 - rcos(fn))
		if "v" in orn:
			dl = min(0.42, nt["d"] * 0.45)
			ds = max(s, int((nt["t"] + nt["d"] - dl) * sr))
			de = e_next
			u = np.clip((np.arange(de - ds) / sr) / (dl + c["release"]), 0, 1)
			pitch[ds:de] -= c["dip"] * u ** 2
		if nt["d"] > 0.32:
			depth = c["vib_deep"] if "~" in orn else c["vib"]
			ve = min(n, e_note + int(c["release"] * sr))
			tt = (np.arange(ve - s) / sr)
			ramp = np.clip((tt - c["vib_delay"]) / 0.35, 0, 1)
			rate = c["vib_rate"] * (0.9 if "~" in orn else 1.0) * g.uniform(0.95, 1.05)
			vib[s:ve] = depth * ramp * np.sin(TAU * rate * tt)
	# đường bao biên độ theo cụm luyến
	amp = np.zeros(n)
	tsa = np.full(n, 10.0)
	groups: list[list[int]] = []
	cur: list[int] = []
	for i, nt in enumerate(notes):
		cur.append(i)
		if not nt.get("slur") or i == len(notes) - 1:
			groups.append(cur)
			cur = []
	attacks = []
	for gi, grp in enumerate(groups):
		s = starts[grp[0]]
		last = notes[grp[-1]]
		e = int((last["t"] + last["d"]) * sr)
		nxt = starts[groups[gi + 1][0]] if gi + 1 < len(groups) else n
		rel = int(c["release"] * sr)
		rel = max(int(0.008 * sr), min(rel, nxt - e + int(0.012 * sr)))
		stop = min(n, e + rel)
		tt = np.arange(stop - s) / sr
		vel = notes[grp[0]]["v"]
		env = c["sustain"] + (1.0 - c["sustain"]) * np.exp(-tt / c["decay_tau"])
		env *= np.exp(-tt / c["slow_tau"])
		na = max(2, int(c["attack"] * sr))
		env[:na] *= rcos(na)[:env.shape[0]] if env.shape[0] >= na else rcos(na)[:env.shape[0]]
		k = e - s
		if k < env.shape[0]:
			r = env.shape[0] - k
			env[k:] *= rcos(r)[::-1]
		# nhấn nhẹ trọng âm các nốt luyến bên trong cụm
		for j in grp[1:]:
			sj = starts[j] - s
			if 0 < sj < env.shape[0]:
				bump = np.exp(-np.arange(env.shape[0] - sj) / sr / 0.12)
				env[sj:] *= 1.0 + 0.12 * (notes[j]["v"] / max(vel, 1e-3)) * bump
		amp[s:stop] = np.maximum(amp[s:stop], env * vel)
		tsa[s:stop] = np.minimum(tsa[s:stop], tt)
		attacks.append(s)
	f = hz(pitch + vib)
	ph = TAU * np.cumsum(f) / sr
	fmax = float(np.max(f))
	sig = np.zeros(n)
	bright = c["bright_floor"] + (1.0 - c["bright_floor"]) * np.exp(-tsa / c["bright_tau"])
	for k, a in enumerate(c["harm"], start=1):
		if k * fmax > 0.44 * sr:
			break
		w = a if k == 1 else a * bright
		sig += w * np.sin(k * ph + g.uniform(0, TAU))
	if kind in BREATHY:
		nb = lp(g.standard_normal(n), 160.0, sr, 2)
		nb /= np.std(nb) + 1e-9
		breath = np.sin(ph) * nb * c.get("breath", 0.22)
		hiss = bp(g.standard_normal(n), 1800.0 if kind == "sao" else 1100.0, 7000.0 if kind == "sao" else 4500.0,
			sr, 2) * c.get("hiss", 0.035)
		chiff = np.zeros(n)
		for s in attacks:
			m = min(n - s, int(0.06 * sr))
			chiff[s:s + m] += np.exp(-np.arange(m) / sr / 0.018)
		ch_noise = bp(g.standard_normal(n), 1200.0, 5000.0, sr, 2) * chiff * c.get("chiff", 0.25)
		sig = sig + breath + hiss + ch_noise
	else:
		pick = np.zeros(n)
		for s in attacks:
			m = min(n - s, int(0.012 * sr))
			pick[s:s + m] += np.exp(-np.arange(m) / sr / 0.003)
		sig = sig + bp(g.standard_normal(n), 2000.0, 6000.0, sr, 2) * pick * 0.18
	out = sig * amp
	out = lp(out, c.get("lp", 6500.0 if kind == "bau" else 9000.0), sr, 2)
	if c.get("tame_db"):
		out = peq(out, sr, 3000.0, c["tame_db"], 0.9)
	return fades(out / 1.15, sr, 0.005, 0.02)


# ------------------------------------------------------------------ bass, pad

def bass(sr: int, freq: float, dur: float, vel: float = 0.8, seed: int = 0) -> np.ndarray:
	"""Bass tròn (giống đàn kìm trầm/ guitar bass mềm)."""
	g = rng(seed)
	rel = 0.09
	n = int((dur + rel) * sr)
	t = np.arange(n) / sr
	f = freq * 2.0 ** ((0.12 * np.exp(-t / 0.03)) / 12.0)
	ph = TAU * np.cumsum(f) / sr
	sig = np.sin(ph) + 0.32 * np.sin(2 * ph + 0.3) * np.exp(-t / 0.5) + 0.10 * np.sin(3 * ph + 1.1) * np.exp(-t / 0.25)
	env = 0.5 + 0.5 * np.exp(-t / 0.22)
	env *= np.exp(-t / 2.2)
	na = int(0.008 * sr)
	env[:na] *= rcos(na)
	k = int(dur * sr)
	env[k:] *= rcos(n - k)[::-1]
	out = sig * env * vel
	out += lp(g.standard_normal(n), 900.0, sr) * np.exp(-t / 0.01) * 0.05 * vel
	return fades(lp(out, 1100.0, sr, 2), sr, 0.005, 0.01)


def pad(sr: int, midis, dur: float, attack: float = 1.0, release: float = 1.4, cutoff: float = 1300.0,
		seed: int = 0, detune: float = 7.0, level: float = 1.0) -> np.ndarray:
	"""Pad ấm: chồng saw cộng tính (đã lọc trong miền phổ) + sine, 3 giọng lệch nhau, stereo."""
	g = rng(seed)
	n = int((dur + release) * sr)
	t = np.arange(n) / sr
	out = np.zeros((2, n))
	pans = [(-0.7, -detune), (0.0, 0.0), (0.7, detune)]
	for m in midis:
		f0 = float(hz(m))
		for pan, dc in pans:
			f = f0 * 2.0 ** ((dc + g.uniform(-1.5, 1.5)) / 1200.0)
			drift = 1.0 + 0.0009 * np.sin(TAU * g.uniform(0.07, 0.15) * t + g.uniform(0, TAU))
			ph = TAU * np.cumsum(f * drift) / sr
			v = 0.6 * np.sin(ph)
			k = 1
			while k * f < min(0.42 * sr, cutoff * 4.0) and k <= 30:
				a = (1.0 / k) / (1.0 + (k * f / cutoff) ** 4)
				v += 0.5 * a * np.sin(k * ph + g.uniform(0, TAU))
				k += 1
			a_ = (pan + 1.0) * np.pi / 4.0
			out[0] += v * np.cos(a_)
			out[1] += v * np.sin(a_)
	env = np.ones(n)
	na = int(attack * sr)
	env[:na] = rcos(na)
	k = int(dur * sr)
	env[k:] = rcos(n - k)[::-1]
	out *= env * level / (len(midis) * 1.6)
	return out


# ------------------------------------------------------------------ bộ gõ

def song_lang(sr: int, vel: float = 0.8, seed: int = 0, pitch: float = 1.0) -> np.ndarray:
	"""Song lang: phách gỗ gõ 'cắc' — mode gỗ tắt rất nhanh + tiếng click."""
	g = rng(seed)
	j = g.uniform(0.985, 1.015) * pitch
	body = modal(sr, 0.12, np.array([1180.0, 1830.0, 2950.0, 4100.0]) * j, [0.026, 0.017, 0.010, 0.006],
		[1.0, 0.55, 0.32, 0.18], g, attack=0.0015)
	m = int(0.01 * sr)
	click = np.zeros_like(body)
	click[:m] = bp(g.standard_normal(m), 2500.0, 7000.0, sr) * np.exp(-np.arange(m) / sr / 0.0015) * 0.8
	return fades((body + click) * vel * 0.8, sr, 0.0015, 0.01)


def shaker(sr: int, vel: float = 0.5, seed: int = 0, length: float = 0.11) -> np.ndarray:
	g = rng(seed)
	n = int(length * sr)
	t = np.arange(n) / sr
	env = np.minimum(1.0, t / 0.012) * np.exp(-np.maximum(0, t - 0.012) / 0.03)
	x = hp(g.standard_normal(n), 4200.0, sr, 2) * env
	return fades(lp(x, 10000.0, sr) * vel * 0.5, sr, 0.003, 0.01)


def trong(sr: int, f0: float = 64.0, vel: float = 0.8, seed: int = 0, tau: float = 0.32, dur: float = 0.9,
		slap: float = 0.25) -> np.ndarray:
	"""Trống da (trầm) — cao độ tụt nhanh sau cú đánh, các mode màng tắt nhanh hơn."""
	g = rng(seed)
	n = int(dur * sr)
	t = np.arange(n) / sr
	f = f0 * (1.0 + 0.55 * np.exp(-t / 0.028))
	ph = TAU * np.cumsum(f) / sr
	body = np.sin(ph) * np.exp(-t / tau) + 0.28 * np.sin(1.59 * ph + 0.4) * np.exp(-t / (tau * 0.38))
	body += 0.13 * np.sin(2.14 * ph + 1.2) * np.exp(-t / (tau * 0.25))
	beat = lp(g.standard_normal(n), 1400.0, sr) * np.exp(-t / 0.007) * 0.45
	sl = bp(g.standard_normal(n), 900.0, 4000.0, sr) * np.exp(-t / 0.006) * slap
	return fades((body + beat + sl) * vel, sr, 0.002, 0.02)


def gong(sr: int, f0: float = 98.0, vel: float = 0.8, seed: int = 0, dur: float = 4.5) -> np.ndarray:
	"""Chiêng: mode bất hoà âm, tắt chậm, cao độ 'nở' nhẹ."""
	g = rng(seed)
	n = int(dur * sr)
	t = np.arange(n) / sr
	ratios = [1.0, 1.49, 2.01, 2.43, 2.98, 3.57, 4.26, 5.1]
	taus = [4.0, 2.6, 2.2, 1.5, 1.2, 0.9, 0.6, 0.4]
	amps = [1.0, 0.5, 0.6, 0.3, 0.25, 0.15, 0.1, 0.06]
	bloom = 1.0 + 0.012 * (1.0 - np.exp(-t / 0.5))
	out = np.zeros(n)
	for r, ta, a in zip(ratios, taus, amps):
		f = f0 * r * bloom
		if f0 * r > 0.45 * sr:
			continue
		ph = TAU * np.cumsum(f) / sr
		beat = 1.0 + 0.15 * np.sin(TAU * g.uniform(0.5, 2.0) * t)
		out += a * np.exp(-t / ta) * np.sin(ph + g.uniform(0, TAU)) * beat
	out += lp(g.standard_normal(n), 600.0, sr) * np.exp(-t / 0.02) * 0.4
	na = int(0.012 * sr)
	out[:na] *= rcos(na)
	return fades(out * vel * 0.5, sr, 0.005, 0.3)


def chap_choa(sr: int, vel: float = 0.7, seed: int = 0, open_: bool = True) -> np.ndarray:
	"""Chập chõa (não bạt nhỏ): nhiều mode kim loại bất hoà âm + nhiễu cao."""
	g = rng(seed)
	dur = 0.9 if open_ else 0.14
	n = int(dur * sr)
	t = np.arange(n) / sr
	out = np.zeros(n)
	for _ in range(26):
		f = g.uniform(2400.0, min(10500.0, 0.45 * sr))
		ta = g.uniform(0.12, 0.5) if open_ else g.uniform(0.02, 0.05)
		out += g.uniform(0.3, 1.0) * np.exp(-t / ta) * np.sin(TAU * f * t + g.uniform(0, TAU))
	out /= 8.0
	out += hp(g.standard_normal(n), 5000.0, sr) * np.exp(-t / (0.18 if open_ else 0.03)) * 0.6
	return fades(out * vel * 0.6, sr, 0.002, 0.03)


def bowl(sr: int, f0: float = 330.0, vel: float = 0.8, seed: int = 0, dur: float = 4.0, bright: float = 1.0) -> np.ndarray:
	"""Chuông/ chén chuông: mode bất hoà âm với cặp lệch nhau tạo 'ngân' (beating)."""
	g = rng(seed)
	n = int(dur * sr)
	t = np.arange(n) / sr
	ratios = [1.0, 2.71, 5.12, 8.0]
	taus = [6.0, 3.4, 1.7, 0.8]
	amps = [1.0, 0.42 * bright, 0.18 * bright, 0.07 * bright]
	out = np.zeros(n)
	for r, ta, a in zip(ratios, taus, amps):
		f = f0 * r
		if f > 0.45 * sr:
			continue
		d = g.uniform(0.4, 1.4)
		out += a * np.exp(-t / ta) * (np.sin(TAU * (f - d / 2) * t + g.uniform(0, TAU)) + np.sin(TAU * (f + d / 2) * t + g.uniform(0, TAU))) * 0.5
	out += lp(g.standard_normal(n), 900.0, sr) * np.exp(-t / 0.006) * 0.15
	na = int(0.008 * sr)
	out[:na] *= rcos(na)
	return fades(out * vel, sr, 0.005, min(0.4, dur * 0.2))

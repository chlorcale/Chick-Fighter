"""DSP cơ bản cho bộ sinh âm thanh Chick Fighter (chỉ numpy + scipy, không dùng sample).

Quy ước: tín hiệu mono là mảng 1 chiều, stereo là mảng (2, n). Mọi vòng lặp (loop)
được dựng theo kiểu "vòng tròn": nốt/ sự kiện vượt quá cuối file được cộng vòng về đầu,
reverb/delay/lọc đều xử lý vòng tròn → điểm nối liền mạch về mặt toán học.
"""
from __future__ import annotations

import struct
import numpy as np
from scipy import signal
from scipy.ndimage import minimum_filter1d, uniform_filter1d

TAU = 2.0 * np.pi


def rng(seed: int) -> np.random.Generator:
	return np.random.default_rng(seed)


def hz(midi):
	return 440.0 * 2.0 ** ((np.asarray(midi, dtype=float) - 69.0) / 12.0)


def db_to_lin(d: float) -> float:
	return 10.0 ** (d / 20.0)


def rms_db(x) -> float:
	return 20.0 * np.log10(np.sqrt(np.mean(np.square(x))) + 1e-12)


def peak_db(x) -> float:
	return 20.0 * np.log10(np.max(np.abs(x)) + 1e-12)


# ------------------------------------------------------------------ đường bao

def rcos(n: int) -> np.ndarray:
	"""Nửa chu kỳ cosine tăng 0 → 1 dài n mẫu (phần tử đầu = 0)."""
	if n <= 0:
		return np.ones(0)
	return 0.5 - 0.5 * np.cos(np.pi * np.arange(n) / n)


def fades(x, sr: int, fin: float = 0.005, fout: float = 0.005):
	x = np.array(x, dtype=float, copy=True)
	n = x.shape[-1]
	a = min(n, max(1, int(fin * sr)))
	b = min(n, max(1, int(fout * sr)))
	x[..., :a] *= rcos(a)
	x[..., n - b:] *= rcos(b)[::-1]
	return x


def adsr(n: int, sr: int, a: float, d: float, s: float, r: float, hold: float | None = None) -> np.ndarray:
	"""ADSR với cạnh cosine; hold = thời điểm nhả (giây), mặc định n - r."""
	env = np.zeros(n)
	na = max(1, int(a * sr))
	nd = max(1, int(d * sr))
	nr = max(1, int(r * sr))
	off = n - nr if hold is None else min(n - nr, int(hold * sr))
	off = max(off, 1)
	t = np.arange(n)
	env[:] = s
	env[:min(na, n)] = rcos(na)[:min(na, n)]
	dec = (t >= na) & (t < na + nd)
	env[dec] = s + (1.0 - s) * (0.5 + 0.5 * np.cos(np.pi * (t[dec] - na) / nd))
	level = env[off - 1] if off - 1 < n else s
	tail = t >= off
	k = t[tail] - off
	env[tail] = level * (1.0 - rcos(nr)[np.minimum(k, nr - 1)])
	env[t >= off + nr] = 0.0
	return env


def smooth_curve(times, values, n: int, sr: int) -> np.ndarray:
	"""Nội suy tuyến tính các điểm (giây, giá trị) thành mảng n mẫu."""
	t = np.arange(n) / sr
	return np.interp(t, np.asarray(times, float), np.asarray(values, float))


# ------------------------------------------------------------------ lọc

def _sos(kind: str, f, sr: int, order: int):
	nyq = sr / 2.0
	if kind in ("low", "high"):
		f = float(min(max(f, 5.0), nyq * 0.95))
		return signal.butter(order, f, btype=kind, fs=sr, output="sos")
	lo, hi = f
	lo = max(float(lo), 5.0)
	hi = min(float(hi), nyq * 0.95)
	if hi <= lo * 1.05:
		hi = lo * 1.05
	return signal.butter(order, [lo, hi], btype="band", fs=sr, output="sos")


def _run(sos, x, circular: bool, sr: int):
	if not circular:
		return signal.sosfilt(sos, x, axis=-1)
	n = x.shape[-1]
	pad = min(n, int(sr * 1.0))
	reps = []
	# tiền tố = đuôi tín hiệu (lặp lại nếu tín hiệu ngắn) để bộ lọc vào trạng thái ổn định
	need = int(sr * 1.0)
	while sum(r.shape[-1] for r in reps) < need:
		reps.append(x)
	pre = np.concatenate(reps, axis=-1)[..., -need:] if reps else x[..., -pad:]
	xp = np.concatenate([pre, x], axis=-1)
	y = signal.sosfilt(sos, xp, axis=-1)
	return y[..., pre.shape[-1]:]


def lp(x, f, sr, order=2, circular=False):
	return _run(_sos("low", f, sr, order), np.asarray(x, float), circular, sr)


def hp(x, f, sr, order=2, circular=False):
	return _run(_sos("high", f, sr, order), np.asarray(x, float), circular, sr)


def bp(x, lo, hi, sr, order=2, circular=False):
	return _run(_sos("band", (lo, hi), sr, order), np.asarray(x, float), circular, sr)


def peq(x, sr, f0, gain_db, q, circular=False):
	"""Peaking EQ (RBJ)."""
	a_ = 10.0 ** (gain_db / 40.0)
	w0 = TAU * min(f0, sr * 0.45) / sr
	alpha = np.sin(w0) / (2.0 * q)
	b = [1 + alpha * a_, -2 * np.cos(w0), 1 - alpha * a_]
	a = [1 + alpha / a_, -2 * np.cos(w0), 1 - alpha / a_]
	return _run(signal.tf2sos(b, a), np.asarray(x, float), circular, sr)


def reson(x, sr, f0, q, circular=False):
	"""Bộ cộng hưởng band-pass đỉnh 0 dB (RBJ)."""
	w0 = TAU * min(f0, sr * 0.45) / sr
	alpha = np.sin(w0) / (2.0 * q)
	b = [alpha, 0.0, -alpha]
	a = [1 + alpha, -2 * np.cos(w0), 1 - alpha]
	return _run(signal.tf2sos(b, a), np.asarray(x, float), circular, sr)


# ------------------------------------------------------------------ nhiễu tuần hoàn

def periodic_noise(n: int, sr: int, g: np.random.Generator, shape=None) -> np.ndarray:
	"""Nhiễu định hình phổ trong miền FFT → tuần hoàn tuyệt đối với chu kỳ n."""
	spec = np.fft.rfft(g.standard_normal(n))
	if shape is not None:
		f = np.fft.rfftfreq(n, 1.0 / sr)
		spec *= shape(f)
	y = np.fft.irfft(spec, n)
	return y / (np.std(y) + 1e-12)


def band_shape(lo, hi, slope=2.0):
	"""Hàm phổ dạng band-pass mềm (Butterworth-like) dùng cho periodic_noise."""
	def s(f):
		f = np.maximum(f, 1e-3)
		hpg = 1.0 / np.sqrt(1.0 + (lo / f) ** (2 * slope)) if lo else 1.0
		lpg = 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * slope)) if hi else 1.0
		return hpg * lpg
	return s


def pink_band(lo, hi, slope=2.0, tilt=0.5):
	b = band_shape(lo, hi, slope)
	return lambda f: b(f) / np.maximum(f, 20.0) ** tilt


def periodic_lfo(n: int, sr: int, g: np.random.Generator, max_hz: float, min_hz: float = 0.0) -> np.ndarray:
	"""Đường cong ngẫu nhiên mượt, tuần hoàn chu kỳ n, chuẩn hoá về [-1, 1]."""
	spec = np.zeros(n // 2 + 1, dtype=complex)
	f = np.fft.rfftfreq(n, 1.0 / sr)
	sel = (f <= max_hz) & (f > max(min_hz, 1e-9))
	k = int(np.count_nonzero(sel))
	if k == 0:
		sel[1] = True
		k = 1
	spec[sel] = (g.standard_normal(k) + 1j * g.standard_normal(k)) / np.sqrt(np.maximum(f[sel], 0.01))
	y = np.fft.irfft(spec, n)
	return y / (np.max(np.abs(y)) + 1e-12)


# ------------------------------------------------------------------ dao động / tổng hợp

def phase_of(freq) -> np.ndarray:
	"""Pha tích luỹ (radian) từ đường tần số tức thời (Hz/ mẫu được chia sr ở ngoài)."""
	return np.cumsum(freq)


def modal(sr: int, dur: float, freqs, taus, amps, g: np.random.Generator | None = None, attack: float = 0.002) -> np.ndarray:
	n = int(dur * sr)
	t = np.arange(n) / sr
	out = np.zeros(n)
	for f, tau, a in zip(freqs, taus, amps):
		if f >= sr * 0.47:
			continue
		ph = g.uniform(0, TAU) if g is not None else 0.0
		out += a * np.exp(-t / tau) * np.sin(TAU * f * t + ph)
	return fades(out, sr, attack, 0.005)


def pan_mono(x, pan: float) -> np.ndarray:
	"""Pan công suất đều; pan ∈ [-1, 1], giữa = biên độ 1 mỗi kênh."""
	a = (np.clip(pan, -1.0, 1.0) + 1.0) * np.pi / 4.0
	return np.vstack([x * np.cos(a), x * np.sin(a)]) * np.sqrt(2.0)


# ------------------------------------------------------------------ bàn trộn

class Mix:
	def __init__(self, sr: int, n: int, loop: bool):
		self.sr = sr
		self.n = n
		self.loop = loop
		self.buses: dict[str, np.ndarray] = {}

	def bus(self, name: str) -> np.ndarray:
		if name not in self.buses:
			self.buses[name] = np.zeros((2, self.n))
		return self.buses[name]

	def place(self, name: str, sig, t0: float, pan: float = 0.0, gain: float = 1.0) -> None:
		b = self.bus(name)
		sig = np.asarray(sig, dtype=float)
		st = pan_mono(sig, pan) * gain if sig.ndim == 1 else sig * gain
		s = int(round(t0 * self.sr))
		length = st.shape[1]
		if self.loop:
			s %= self.n
			pos = 0
			while pos < length:
				start = (s + pos) % self.n
				chunk = min(length - pos, self.n - start)
				b[:, start:start + chunk] += st[:, pos:pos + chunk]
				pos += chunk
		else:
			if s < 0:
				st = st[:, -s:]
				s = 0
			if s >= self.n:
				return
			chunk = min(st.shape[1], self.n - s)
			b[:, s:s + chunk] += st[:, :chunk]


def fold(y: np.ndarray, n: int) -> np.ndarray:
	"""Gập tín hiệu dài hơn n về chu kỳ n (cộng đuôi vào đầu)."""
	out = np.array(y[..., :n], copy=True)
	pos = n
	while pos < y.shape[-1]:
		chunk = y[..., pos:pos + n]
		out[..., :chunk.shape[-1]] += chunk
		pos += n
	return out


# ------------------------------------------------------------------ hiệu ứng

def make_ir(sr: int, seconds: float = 2.4, rt=(2.0, 1.6, 0.9, 0.45), predelay: float = 0.018,
		seed: int = 11, early: int = 10, er_gain: float = 2.5) -> np.ndarray:
	"""Đáp ứng xung reverb stereo tổng hợp: nhiễu tắt dần theo dải + phản xạ sớm."""
	g = rng(seed)
	n = int(seconds * sr)
	t = np.arange(n) / sr
	nyq = sr / 2.0
	edges = [(None, 350.0), (350.0, 1800.0), (1800.0, 5000.0), (5000.0, None)]
	ir = np.zeros((2, n))
	for ch in range(2):
		noise = g.standard_normal(n)
		for (lo, hi), r in zip(edges, rt):
			if lo is None:
				band = lp(noise, hi, sr, 4)
			elif hi is None:
				if lo >= nyq * 0.9:
					continue
				band = hp(noise, lo, sr, 4)
			else:
				band = bp(noise, lo, min(hi, nyq * 0.9), sr, 2)
			ir[ch] += band * np.exp(-6.91 * t / r)
	build = int(0.015 * sr)
	ir[:, :build] *= rcos(build)
	for k in range(early):
		d = g.uniform(0.004, 0.065)
		idx = int(d * sr)
		ir[k % 2, idx] += g.choice([-1.0, 1.0]) * g.uniform(0.4, 1.0) * er_gain * (1.0 - d / 0.075)
	tail = int(0.15 * n)
	ir[:, n - tail:] *= rcos(tail)[::-1]
	pre = int(predelay * sr)
	ir = np.concatenate([np.zeros((2, pre)), ir], axis=1)
	for ch in range(2):
		ir[ch] /= np.sqrt(np.sum(ir[ch] ** 2)) + 1e-12
	return ir


def reverb(x: np.ndarray, ir: np.ndarray, loop: bool) -> np.ndarray:
	n = x.shape[1]
	src = [0.62 * x[0] + 0.38 * x[1], 0.38 * x[0] + 0.62 * x[1]]
	out = np.zeros((2, n))
	for ch in range(2):
		y = signal.fftconvolve(src[ch], ir[ch])
		out[ch] = fold(y, n) if loop else y[:n]
	return out


def shift(x: np.ndarray, d: int, loop: bool) -> np.ndarray:
	if loop:
		return np.roll(x, d, axis=-1)
	y = np.zeros_like(x)
	if d < x.shape[-1]:
		y[..., d:] = x[..., :x.shape[-1] - d]
	return y


def pingpong(x: np.ndarray, sr: int, delay_s: float, fb: float = 0.38, taps: int = 6,
		lp_hz: float = 3200.0, hp_hz: float = 300.0, loop: bool = True) -> np.ndarray:
	d = int(round(delay_s * sr))
	src = hp(x.mean(axis=0), hp_hz, sr, 2, circular=loop)
	out = np.zeros_like(x)
	tap = src
	for k in range(taps):
		tap = lp(shift(tap, d, loop), lp_hz, sr, 1, circular=loop) * (1.0 if k == 0 else fb)
		out[(k + 1) % 2] += tap
	return out


def wow(x: np.ndarray, sr: int, depth_ms: float = 0.45, rate: float = 0.55, flutter_ms: float = 0.04,
		flutter_rate: float = 6.3, loop: bool = True) -> np.ndarray:
	"""Băng từ lắc nhẹ (wow/flutter) bằng trễ biến thiên; tần số làm tròn để tuần hoàn trong loop."""
	n = x.shape[1]
	T = n / sr
	if loop:
		rate = max(1, round(rate * T)) / T
		flutter_rate = max(1, round(flutter_rate * T)) / T
	t = np.arange(n) / sr
	d = (depth_ms * (1 + np.sin(TAU * rate * t)) / 2 + flutter_ms * (1 + np.sin(TAU * flutter_rate * t)) / 2) * sr / 1000.0
	pad = int(np.ceil(np.max(d))) + 4
	out = np.zeros_like(x)
	for ch in range(x.shape[0]):
		if loop:
			xp = np.concatenate([x[ch, -pad:], x[ch], x[ch, :pad]])
		else:
			xp = np.concatenate([np.zeros(pad), x[ch], np.zeros(pad)])
		idx = np.arange(n) + pad - d
		out[ch] = np.interp(idx, np.arange(xp.shape[0]), xp)
	return out


def saturate(x, drive: float = 1.5):
	return np.tanh(x * drive) / drive


def limiter(x, sr: int, ceiling_db: float = -1.0, window: float = 0.03, loop: bool = False):
	ceil = db_to_lin(ceiling_db)
	pk = np.max(np.abs(x), axis=0) if x.ndim == 2 else np.abs(x)
	need = np.minimum(1.0, ceil / np.maximum(pk, 1e-12))
	w = max(3, int(window * sr)) | 1
	mode = "wrap" if loop else "nearest"
	gn = minimum_filter1d(need, size=w, mode=mode)
	gn = uniform_filter1d(gn, size=max(1, w // 2), mode=mode)
	return np.clip(x * gn, -ceil, ceil)


def master(x, sr: int, target_rms_db: float, ceiling_db: float = -1.0, drive: float = 1.4,
		loop: bool = True, hp_hz: float = 22.0):
	"""Bus tổng: lọc DC, bão hoà mềm, chuẩn hoá RMS, limiter đỉnh ≤ ceiling."""
	x = hp(x, hp_hz, sr, 2, circular=loop)
	x = x - np.mean(x, axis=-1, keepdims=True)
	gain = db_to_lin(target_rms_db - rms_db(x))
	y = x
	for _ in range(6):
		y = limiter(saturate(x * gain, drive), sr, ceiling_db - 0.15, loop=loop)
		err = target_rms_db - rms_db(y)
		if abs(err) < 0.05:
			break
		gain *= db_to_lin(err)
	return y


def peak_normalize(x, peak_dbfs: float):
	x = np.asarray(x, float)
	x = x - np.mean(x, axis=-1, keepdims=True) if x.shape[-1] > 0 else x
	return x * db_to_lin(peak_dbfs) / (np.max(np.abs(x)) + 1e-12)


# ------------------------------------------------------------------ WAV

def write_wav(path: str, x, sr: int, loop: bool = False, seed: int = 0) -> None:
	"""Ghi PCM 16-bit (dither TPDF). loop=True thêm chunk 'smpl' (forward, 0 → số khung)
	để Godot "Detect From WAV" tự bật loop khi import."""
	x = np.atleast_2d(np.asarray(x, float))
	ch, n = x.shape
	g = rng(seed + 9001)
	dither = g.uniform(-0.5, 0.5, (ch, n)) + g.uniform(-0.5, 0.5, (ch, n))
	q = np.clip(np.round(x * 32767.0 + dither), -32768, 32767).astype("<i2")
	data = q.T.tobytes()
	fmt = struct.pack("<HHIIHH", 1, ch, sr, sr * ch * 2, ch * 2, 16)
	body = b"WAVE" + b"fmt " + struct.pack("<I", 16) + fmt
	body += b"data" + struct.pack("<I", len(data)) + data
	if len(data) % 2:
		body += b"\x00"
	if loop:
		smpl = struct.pack("<9I", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
		smpl += struct.pack("<6I", 0, 0, 0, n, 0, 0)
		body += b"smpl" + struct.pack("<I", len(smpl)) + smpl
	with open(path, "wb") as f:
		f.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def read_wav(path: str):
	"""Đọc WAV PCM16 do write_wav ghi → (sr, mảng (ch, n) float, info dict)."""
	with open(path, "rb") as f:
		raw = f.read()
	assert raw[:4] == b"RIFF" and raw[8:12] == b"WAVE", path
	pos = 12
	info = {"smpl": None}
	sr = ch = 0
	data = None
	while pos + 8 <= len(raw):
		cid = raw[pos:pos + 4]
		size = struct.unpack("<I", raw[pos + 4:pos + 8])[0]
		chunk = raw[pos + 8:pos + 8 + size]
		if cid == b"fmt ":
			_, ch, sr, _, _, bits = struct.unpack("<HHIIHH", chunk[:16])
			assert bits == 16
		elif cid == b"data":
			data = np.frombuffer(chunk, dtype="<i2")
		elif cid == b"smpl":
			vals = struct.unpack("<15I", chunk[:60])
			info["smpl"] = (vals[10], vals[11], vals[12])
		pos += 8 + size + (size % 2)
	x = data.reshape(-1, ch).T.astype(float) / 32768.0
	return sr, x, info

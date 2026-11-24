"""Nhạc nền ngũ cung Nam Bộ (sáng tác gốc) — village, title, memory, battle, final + jingle.

Ký hiệu câu nhạc: "A4:1.5 C5:0.5^ r:1 | ..." = tên nốt:số phách + ký hiệu láy
  ^ nhấn (vuốt lên từ dưới)   v luyến/ rớt xuống cuối nốt   ~ rung sâu   g láy hoa mỹ (nốt trên)
  _ luyến sang nốt kế (không gảy lại)   * nhấn mạnh   % nhẹ        r = nghỉ;  | = vạch nhịp (được kiểm tra)
"""
from __future__ import annotations

import re
import numpy as np

import dsp
from dsp import hz, rng
import instruments as ins

NOTE_RE = re.compile(r"^([A-G])([#b]?)(-?\d)$")
PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi_of(name: str, cents: dict | None = None) -> float:
	m = NOTE_RE.match(name)
	if not m:
		raise ValueError(name)
	v = 12 * (int(m.group(3)) + 1) + PC[m.group(1)] + {"": 0, "#": 1, "b": -1}[m.group(2)]
	if cents:
		v += cents.get(v % 12, 0.0) / 100.0
	return float(v)


def parse(line: str, bpb: int = 4, cents: dict | None = None, transpose: float = 0.0) -> tuple[list[dict], float]:
	notes = []
	beat = 0.0
	bar_sum = 0.0
	for tok in line.split():
		if tok == "|":
			if abs(bar_sum - bpb) > 1e-6:
				raise ValueError(f"ô nhịp sai ({bar_sum} phách) trong: {line}")
			bar_sum = 0.0
			continue
		name, rest = tok.split(":")
		m = re.match(r"^([0-9.]+)(.*)$", rest)
		d = float(m.group(1))
		mods = m.group(2)
		bar_sum += d
		if name != "r":
			notes.append({"b": beat, "db": d, "m": midi_of(name, cents) + transpose, "orn": mods,
				"slur": "_" in mods, "acc": 1.2 if "*" in mods else (0.7 if "%" in mods else 1.0)})
		beat += d
	if abs(bar_sum - bpb) > 1e-6 and bar_sum > 0:
		raise ValueError(f"ô nhịp cuối sai ({bar_sum} phách) trong: {line}")
	return notes, beat


class Song:
	def __init__(self, name: str, sr: int, bpm: float, bars: int, bpb: int = 4, swing8: float = 0.0,
			swing16: float = 0.0, loop: bool = True, tail: float = 0.0, seed: int = 1,
			cents: dict | None = None, human: float = 0.005, transpose: float = 0.0):
		self.name = name
		self.sr = sr
		self.bpm = bpm
		self.bpb = bpb
		self.bars = bars
		self.spb = 60.0 / bpm
		self.swing8 = swing8
		self.swing16 = swing16
		self.loop = loop
		self.g = rng(seed)
		self.seed = seed
		self.cents = cents or {}
		self.human = human
		self.transpose = transpose
		self.loop_n = int(round(bars * bpb * self.spb * sr))
		self.mix = dsp.Mix(sr, self.loop_n + (0 if loop else int(tail * sr)), loop)
		self._seed_counter = seed * 1000

	def nseed(self) -> int:
		self._seed_counter += 1
		return self._seed_counter

	def sec(self, bar: float, beat: float, human: bool = True) -> float:
		b = bar * self.bpb + beat
		frac = b % 1.0
		if abs(frac - 0.5) < 1e-6:
			b += self.swing8
		elif abs(frac - 0.25) < 1e-6 or abs(frac - 0.75) < 1e-6:
			b += self.swing16
		s = b * self.spb
		if human and self.human > 0:
			s += float(np.clip(self.g.normal(0.0, self.human), -2.5 * self.human, 2.5 * self.human))
		return s

	def m(self, name: str) -> float:
		return midi_of(name, self.cents) + self.transpose

	# ---------------------------------------------------------------- nhạc cụ giai điệu
	def lead(self, bus: str, kind: str, bar: int, line: str, vel: float = 0.8, pan: float = 0.0,
			oct_: int = 0, legato: float = 0.96) -> None:
		notes, _ = parse(line, self.bpb, self.cents, self.transpose + 12 * oct_)
		if not notes:
			return
		t0 = self.sec(bar, 0, human=False)
		ev = []
		for i, nt in enumerate(notes):
			ts = self.sec(bar, nt["b"]) - t0
			te_b = nt["b"] + nt["db"]
			adjacent = i + 1 < len(notes) and abs(notes[i + 1]["b"] - te_b) < 1e-6
			te = self.sec(bar, te_b, human=False) - t0
			d = (te - ts) if adjacent else (te - ts) * legato
			ev.append({"t": max(0.0, ts), "d": max(0.06, d), "m": nt["m"],
				"v": vel * nt["acc"] * self.g.uniform(0.92, 1.05), "orn": nt["orn"], "slur": nt["slur"]})
		for i in range(len(ev) - 1):
			if ev[i]["t"] + ev[i]["d"] > ev[i + 1]["t"]:
				ev[i]["d"] = max(0.05, ev[i + 1]["t"] - ev[i]["t"])
		sig = ins.lead_phrase(self.sr, ev, kind, seed=self.nseed())
		self.mix.place(bus, sig, t0, pan)

	def pluck_line(self, bus: str, bar: int, line: str, vel: float = 0.7, pan: float = 0.0, oct_: int = 0,
			inst: str = "tranh", ring: float = 2.6) -> None:
		notes, _ = parse(line, self.bpb, self.cents, self.transpose + 12 * oct_)
		for nt in notes:
			bend = None
			dur_s = nt["db"] * self.spb
			if "^" in nt["orn"]:
				bend = [(0.0, 0.0), (0.09, 0.0), (0.26, 2.0), (dur_s + 1.0, 2.0)]
				nt["m"] -= 2.0
			elif "v" in nt["orn"]:
				bend = [(0.0, 0.0), (max(0.1, dur_s * 0.5), 0.0), (dur_s + 0.3, -1.0)]
			elif "~" in nt["orn"]:
				tt = np.linspace(0, 3.0, 120)
				bend = list(zip(tt, 0.25 * np.clip((tt - 0.25) / 0.4, 0, 1) * np.sin(dsp.TAU * 4.8 * tt)))
			self.pluck(bus, self.sec(bar, nt["b"]), nt["m"], vel * nt["acc"], pan, inst=inst, bend=bend, ring=ring)

	def pluck(self, bus: str, t: float, midi: float, vel: float, pan: float = 0.0, inst: str = "tranh",
			bend=None, ring: float = 2.6) -> None:
		f = float(hz(midi))
		v = vel * self.g.uniform(0.9, 1.06)
		if inst == "kim":
			sig = ins.kim(self.sr, f, v, seed=self.nseed(), bend=bend, ring=min(ring, 1.2))
		elif inst == "guitar":
			# guitar phím lõm gảy ngón: mềm, tối hơn tranh, ngân vừa
			sig = ins.pluck(self.sr, f, v, ring=ring, bend=bend, seed=self.nseed(), pos=0.23, tau_scale=0.7,
				bright=0.7, partials=14, detune_cents=1.5, noise=0.03)
		else:
			sig = ins.pluck(self.sr, f, v, ring=ring, bend=bend, seed=self.nseed())
		self.mix.place(bus, sig, t, pan + self.g.uniform(-0.05, 0.05))

	def arp(self, bus: str, bar: int, tones: list[str], pattern: list, step: float = 0.5, vel: float = 0.55,
			pan: float = 0.25, accent: float = 1.25, ring: float = 2.2, start: float = 0.0) -> None:
		for i, idx in enumerate(pattern):
			if idx is None:
				continue
			beat = start + i * step
			v = vel * (accent if abs(beat % 2.0) < 1e-6 else 1.0) * self.g.uniform(0.85, 1.05)
			self.pluck(bus, self.sec(bar, beat), self.m(tones[idx % len(tones)]) + 12 * (idx // len(tones)), v, pan, ring=ring)

	def gliss(self, bus: str, bar: int, beat: float, names: list[str], spacing: float = 0.045, vel: float = 0.5,
			pan: float = 0.25, down: bool = False, oct_: int = 0, ring: float = 1.8) -> None:
		"""Vuốt đàn tranh (glissando) qua các dây ngũ cung."""
		seq = list(reversed(names)) if down else names
		t = self.sec(bar, beat)
		for i, nm in enumerate(seq):
			v = vel * (0.55 + 0.45 * (i + 1) / len(seq)) if not down else vel * (1.0 - 0.4 * i / len(seq))
			self.pluck(bus, t + i * spacing * self.g.uniform(0.85, 1.15), self.m(nm) + 12 * oct_, v,
				pan + (i / len(seq) - 0.5) * 0.4, ring=ring)

	def tremolo(self, bus: str, bar: int, beat: float, name: str, beats: float, rate: float = 13.0,
			vel: float = 0.45, pan: float = 0.25) -> None:
		"""Vê (tremolo) đàn tranh: gảy lặp nhanh một dây."""
		t0 = self.sec(bar, beat, human=False)
		total = beats * self.spb
		k = int(total * rate)
		for i in range(k):
			sw = 1.0 - 0.3 * abs(np.sin(np.pi * i / max(k, 1)) - 0.5)
			self.pluck(bus, t0 + i / rate + self.g.normal(0, 0.003), self.m(name), vel * sw * (1.0 if i % 2 == 0 else 0.8),
				pan, ring=0.5)

	def bass_line(self, bus: str, bar: int, items: list[tuple], vel: float = 0.75) -> None:
		for beat, dur, name, v in items:
			sig = ins.bass(self.sr, float(hz(self.m(name))), dur * self.spb * 0.95, vel * v, seed=self.nseed())
			self.mix.place(bus, sig, self.sec(bar, beat), 0.0)

	def pad_chord(self, bus: str, bar: int, names: list[str], bars: float, level: float = 1.0,
			cutoff: float = 1300.0, attack: float = 0.9, release: float = 1.5) -> None:
		sig = ins.pad(self.sr, [self.m(n) for n in names], bars * self.bpb * self.spb, attack=attack,
			release=release, cutoff=cutoff, seed=self.nseed(), level=level)
		self.mix.place(bus, sig, self.sec(bar, 0, human=False) - 0.15)

	def hit(self, bus: str, bar: int, beat: float, kind: str, vel: float = 0.7, pan: float = 0.0, **kw) -> None:
		s = self.nseed()
		if kind == "songlang":
			sig = ins.song_lang(self.sr, vel, s, **kw)
		elif kind == "shaker":
			sig = ins.shaker(self.sr, vel, s, **kw)
		elif kind == "trong":
			sig = ins.trong(self.sr, vel=vel, seed=s, **kw)
		elif kind == "trong_mid":
			sig = ins.trong(self.sr, f0=kw.pop("f0", 185.0), vel=vel, seed=s, tau=0.16, dur=0.5, slap=0.5, **kw)
		elif kind == "gong":
			sig = ins.gong(self.sr, vel=vel, seed=s, **kw)
		elif kind == "chap":
			sig = ins.chap_choa(self.sr, vel, s, **kw)
		elif kind == "bowl":
			sig = ins.bowl(self.sr, vel=vel, seed=s, **kw)
		else:
			raise ValueError(kind)
		self.mix.place(bus, sig, self.sec(bar, beat), pan)

	# ---------------------------------------------------------------- trộn
	def render(self, buses: dict, ir_params: dict, delay_beats: float, target_rms: float, tape_lp: float,
			wow_ms: float = 0.4, drive: float = 1.4, ceiling: float = -1.0, report: bool = True) -> np.ndarray:
		mix = self.mix
		n = mix.n
		dry = np.zeros((2, n))
		rsend = np.zeros((2, n))
		dsend = np.zeros((2, n))
		levels = {}
		for name, (gain, rv, dl) in buses.items():
			if name not in mix.buses:
				continue
			b = mix.buses[name] * gain
			levels[name] = dsp.rms_db(b)
			dry += b
			rsend += b * rv
			dsend += b * dl
		ir = dsp.make_ir(self.sr, **ir_params)
		wet = dsp.reverb(rsend, ir, self.loop)
		dly = dsp.pingpong(dsend, self.sr, delay_beats * self.spb, loop=self.loop)
		out = dry + wet + dly * 0.8
		if wow_ms > 0:
			out = dsp.wow(out, self.sr, wow_ms, loop=self.loop)
		out = dsp.lp(out, tape_lp, self.sr, 2, circular=self.loop)
		out = dsp.peq(out, self.sr, 180.0, 1.2, 0.8, circular=self.loop)
		if not self.loop:
			out = dsp.fades(out, self.sr, 0.003, 0.25)
		out = dsp.master(out, self.sr, target_rms, ceiling, drive=drive, loop=self.loop)
		if not self.loop:
			out = dsp.fades(out, self.sr, 0.003, 0.2)
		if report:
			mixdb = dsp.rms_db(dry)
			print(f"    [{self.name}] bus RMS vs dry mix (dB): " + ", ".join(f"{k} {v - mixdb:+.1f}" for k, v in levels.items()))
		return out


# ===================================================================== nhạc quê hương: village / title / memory
#
# Hò = G (G A C D E). Bè đệm guitar phím lõm/ tranh được dùng nốt ba của hợp âm (B, F#) như nhạc
# quê hương; giai điệu sáo giữ ngũ cung, thêm luyến láy (vuốt vào nốt, láy, rung cuối câu) và màu
# hơi Nam (nhấn lên Cống/ Xự, B ở đoạn Em). Giai điệu là sáng tác mới hoàn toàn.

GTR = {
	"G": dict(tones=["G2", "D3", "G3", "B3", "D4", "G4"], root="G2", fifth="D3", pad=["G3", "B3", "D4", "A4"]),
	"Em": dict(tones=["E2", "B2", "E3", "G3", "B3", "E4"], root="E2", fifth="B2", pad=["E3", "G3", "B3", "D4"]),
	"C": dict(tones=["C3", "G3", "C4", "E4", "G4", "C5"], root="C3", fifth="G2", pad=["G3", "C4", "E4", "D5"]),
	"D": dict(tones=["D3", "A3", "D4", "F#4", "A4", "D5"], root="D2", fifth="A2", pad=["D4", "F#4", "A4"]),
	"Am": dict(tones=["A2", "E3", "A3", "C4", "E4", "A4"], root="A2", fifth="E2", pad=["A3", "C4", "E4", "G4"]),
}
GTR_STYLE = {  # (phách, chỉ số dây | "S" = gảy quạt nhẹ)
	"arp": [(0, 0), (0.5, 2), (1, 3), (1.5, 4), (2, 5), (2.5, 4), (3, 3), (3.5, 2)],
	"strum": [(0, 0), (0.5, 2), (1, "S"), (2, 1), (2.5, 2), (3, "S"), (3.5, 3)],
	"sparse": [(0, 0), (1, 2), (2, 3), (3, 4)],
}
SCALE_G = ["G4", "A4", "C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6", "G6"]


def _gtr_bar(S: "Song", bar: int, spec: str, style: str, vel: float = 0.5, pan: float = -0.22) -> None:
	"""Một ô đệm guitar: 'G' hoặc 'Am/D' (đổi hợp âm ở phách 3)."""
	parts = spec.split("/")
	span = 4.0 / len(parts)
	for h, name in enumerate(parts):
		c = GTR[name]
		for beat, idx in GTR_STYLE[style]:
			if beat >= span:
				continue
			b = h * span + beat
			if idx == "S":
				t = S.sec(bar, b)
				for j, k in enumerate([2, 3, 4, 5]):
					S.pluck("guitar", t + j * 0.016, S.m(c["tones"][k]), vel * (0.42 - 0.03 * j), pan + 0.05 * j,
						inst="guitar", ring=1.1)
			else:
				v = vel * (1.15 if beat == 0 else (0.82 if beat % 1 else 0.95))
				S.pluck("guitar", S.sec(bar, b), S.m(c["tones"][idx]), v, pan, inst="guitar", ring=1.8)


def _pads(S: "Song", prog: list[str], level: float = 1.0, cutoff: float = 1200.0) -> None:
	i = 0
	n = len(prog)
	while i < n:
		j = i
		while j + 1 < n and prog[j + 1] == prog[i]:
			j += 1
		parts = prog[i].split("/")
		if len(parts) == 1:
			S.pad_chord("pad", i, GTR[parts[0]]["pad"], j - i + 1, level=level, cutoff=cutoff)
		else:
			S.pad_chord("pad", i, GTR[parts[0]]["pad"], 0.5, level=level, cutoff=cutoff, release=0.8)
			sig = ins.pad(S.sr, [S.m(x) for x in GTR[parts[1]]["pad"]], 0.5 * S.bpb * S.spb, attack=0.5,
				release=1.2, cutoff=cutoff, seed=S.nseed(), level=level)
			S.mix.place("pad", sig, S.sec(i, 2, human=False) - 0.1)
		i = j + 1


def _bass_bar(S: "Song", bar: int, spec: str, style: str) -> None:
	parts = spec.split("/")
	if len(parts) == 2:
		S.bass_line("bass", bar, [(0, 1.8, GTR[parts[0]]["root"], 0.7), (2, 1.8, GTR[parts[1]]["root"], 0.7)])
		return
	c = GTR[spec]
	if style == "long":
		S.bass_line("bass", bar, [(0, 3.8, c["root"], 0.55)])
	else:
		S.bass_line("bass", bar, [(0, 1.8, c["root"], 0.75), (2, 1.4, c["fifth"], 0.6), (3.5, 0.45, c["root"], 0.42)])


def village(sr: int = 32000) -> np.ndarray:
	"""Chủ đề làng — nhạc quê hương Nam Bộ, sáo trúc dẫn. Hò=G (G A C D E), 90 BPM, 36 ô:
	Intro sáo (4) – A (8) – B điệp khúc (8) – gian tấu đàn bầu/sáo (4) – A rút gọn (4) – B (8)."""
	S = Song("village", sr, 90, 36, swing8=0.04, seed=111, human=0.006)
	I, A, B, IT, A2, B2 = 0, 4, 12, 20, 24, 28
	prog = (["C", "G", "Am", "D"] + ["G", "Em", "C", "D", "G", "Em", "Am/D", "G"]
		+ ["C", "D", "G", "Em", "C", "D", "G", "G"] + ["Em", "C", "Am", "D"] + ["G", "Em", "C", "D"]
		+ ["C", "D", "G", "Em", "C", "D", "G", "G"])
	assert len(prog) == 36
	_pads(S, prog)
	for bar, spec in enumerate(prog):
		if bar < A or IT <= bar < A2:
			style = "sparse"
		elif B <= bar < IT or bar >= B2:
			style = "strum"
		else:
			style = "arp"
		_gtr_bar(S, bar, spec, style, vel=0.45 if style == "sparse" else 0.5)
		_bass_bar(S, bar, spec, "long" if bar < A or IT <= bar < IT + 2 else "walk")
	# đàn tranh tô màu: vuốt dây ở đầu đoạn, vê ở gian tấu
	S.gliss("tranh", I, 0, SCALE_G[:8], spacing=0.06, vel=0.35, pan=0.3)
	S.gliss("tranh", B, 0, SCALE_G[2:9], spacing=0.045, vel=0.3, pan=0.32)
	S.gliss("tranh", IT, 0, SCALE_G[1:9], spacing=0.05, vel=0.32, pan=0.3, down=True)
	S.tremolo("tranh", IT + 1, 0, "G5", 3.0, rate=12.0, vel=0.22, pan=0.3)
	S.gliss("tranh", B2, 0, SCALE_G[2:10], spacing=0.045, vel=0.3, pan=0.32)
	S.gliss("tranh", 35, 3, SCALE_G[:7], spacing=0.05, vel=0.25, pan=0.3)
	# sáo dẫn giai điệu
	intro = "E6:1.5g D6:0.5 C6:1 A5:1 | G5:3~ r:1 | A5:1o C6:0.5 A5:0.5 G5:1 E5:1 | D5:2~ r:2"
	verse = ("G5:1.5 A5:0.5 G5:1 E5:1 | D5:1 E5:0.5 G5:0.5 E5:2~ | C5:1 D5:0.5 E5:0.5 G5:1 E5:0.5 D5:0.5 | D5:3~v r:1 | "
		"G5:1 A5:1 C6:1.5^ A5:0.5 | G5:1 E5:0.5 G5:0.5 A5:2~ | C6:1 A5:0.5 G5:0.5 E5:1 D5:1 | G5:3~ r:1")
	chorus = ("E5:0.5 G5:0.5 C6:2^ A5:0.5 C6:0.5 | D6:2~ C6:0.5 A5:0.5 G5:1 | A5:1.5 G5:0.5 E5:1 G5:1 | E5:3^~ r:1 | "
		"E5:0.5 G5:0.5 C6:1.5 D6:0.5 E6:1 | D6:1 C6:0.5 A5:0.5 D6:2~ | C6:1 A5:0.5 G5:0.5 A5:1 E5:1 | G5:3~v r:1")
	chorus2 = ("E5:0.5 G5:0.5 C6:2g A5:0.5 C6:0.5 | D6:2~ C6:0.5 A5:0.5 G5:1 | A5:1.5 G5:0.5 E5:1 G5:1 | E5:3^~ r:1 | "
		"E5:0.5 G5:0.5 C6:1.5 D6:0.5 E6:1o | D6:1 C6:0.5 A5:0.5 D6:2~ | C6:1 A5:0.5 G5:0.5 A5:1 E5:1 | G5:3~v r:1")
	S.lead("sao", "sao_tr", I, intro, vel=0.78, pan=0.05)
	S.lead("sao", "sao_tr", A, verse, vel=0.82, pan=0.05)
	S.lead("sao", "sao_tr", B, chorus, vel=0.85, pan=0.05)
	S.lead("sao", "sao_tr", IT + 2, "A5:1o C6:0.5 B5:0.5 A5:1 E5:1 | D5:2~ r:2", vel=0.78, pan=0.05)
	S.lead("sao", "sao_tr", A2, "G5:1.5g A5:0.5 G5:1 E5:1 | D5:1 E5:0.5 G5:0.5 E5:2~ | "
		"C5:1 D5:0.5 E5:0.5 G5:1 A5:0.5 G5:0.5 | A5:3~ r:1", vel=0.8, pan=0.05)
	S.lead("sao", "sao_tr", B2, chorus2, vel=0.86, pan=0.05)
	# đàn bầu: đáp lời thưa thớt + gian tấu
	S.lead("bau", "bau", A + 3, "r:3 D5:0.5 E5:0.5", vel=0.55, pan=-0.2)
	S.lead("bau", "bau", A + 7, "r:2.5 B4:0.5 D5:0.5 E5:0.5", vel=0.55, pan=-0.2)
	S.lead("bau", "bau", IT, "E5:1.5^ D5:0.5 B4:1 A4:1 | G4:3~v r:1", vel=0.75, pan=-0.15)
	S.lead("bau", "bau", A2 + 3, "r:3 E4:0.5 G4:0.5", vel=0.5, pan=-0.2)
	S.lead("bau", "bau", B2 + 4, "E4:0.5 G4:0.5 C5:1.5 D5:0.5 E5:1 | D5:1 C5:0.5 A4:0.5 D5:2~ | "
		"C5:1 A4:0.5 G4:0.5 A4:1 E4:1 | G4:3~v r:1", vel=0.42, pan=-0.25)
	# bộ gõ nhẹ: song lang + shaker, trống trầm đánh khẽ ở điệp khúc
	for bar in range(36):
		chorus_bar = B <= bar < IT or bar >= B2
		if A <= bar < IT or bar >= A2 or bar == IT + 3:
			for k in range(8):
				S.hit("shaker", bar, k * 0.5, "shaker", 0.42 if k % 2 else 0.24, pan=0.35)
		if bar >= A and not (IT <= bar < IT + 2):
			S.hit("songlang", bar, 0, "songlang", 0.5, pan=-0.3)
			if chorus_bar:
				S.hit("songlang", bar, 2, "songlang", 0.42, pan=-0.3)
				S.hit("songlang", bar, 3.5, "songlang", 0.22, pan=-0.3)
		if chorus_bar and bar % 2 == 0:
			S.hit("trong", bar, 0, "trong", 0.5, f0=62.0)
	buses = {  # tên: (gain, reverb send, delay send)
		"sao": (0.6, 0.3, 0.14), "bau": (0.7, 0.32, 0.12), "guitar": (0.66, 0.2, 0.03), "tranh": (0.55, 0.35, 0.08),
		"bass": (0.78, 0.04, 0.0), "pad": (0.26, 0.5, 0.0), "trong": (0.5, 0.1, 0.0),
		"songlang": (0.62, 0.15, 0.04), "shaker": (0.3, 0.1, 0.0),
	}
	return S.render(buses, dict(seconds=2.4, rt=(1.9, 1.6, 0.9, 0.45), seed=21), 0.75, -18.0, 9500.0, wow_ms=0.25)


def title(sr: int = 24000) -> np.ndarray:
	"""Màn hình tựa — sáo trúc tự do, chậm (66 BPM, 15 ô), dùng lại motif điệp khúc/ intro của village."""
	S = Song("title", sr, 66, 15, seed=212, human=0.012)
	prog = ["C", "G", "C", "D", "G", "Em", "C", "D", "C", "G", "Am", "D", "C", "G", "G"]
	_pads(S, prog, level=1.0, cutoff=1000.0)
	for bar, spec in enumerate(prog):
		if bar >= 1:
			_gtr_bar(S, bar, spec, "sparse", vel=0.4)
		_bass_bar(S, bar, spec, "long")
	S.hit("trong", 0, 0, "trong", 0.7, f0=52.0, tau=0.6, dur=2.0)
	S.hit("gong", 0, 0, "gong", 0.3, f0=98.0)
	S.gliss("tranh", 0, 0.5, SCALE_G, spacing=0.07, vel=0.35, pan=0.25)
	S.gliss("tranh", 8, 0, SCALE_G[1:9], spacing=0.06, vel=0.3, pan=0.3, down=True)
	S.gliss("tranh", 14, 0, SCALE_G[:8], spacing=0.07, vel=0.3, pan=0.25)
	S.lead("sao", "sao_tr", 2, "E5:0.5 G5:0.5 C6:2^ A5:0.5 C6:0.5 | D6:2~ C6:0.5 A5:0.5 G5:1 | "
		"A5:1.5 G5:0.5 E5:1 G5:1 | E5:3^~ r:1", vel=0.8, pan=0.05)
	S.lead("bau", "bau", 6, "C5:1.5^ A4:0.5 G4:1 E4:1 | D4:3~v r:1", vel=0.75, pan=-0.12)
	S.lead("sao", "sao_tr", 8, "E6:1.5g D6:0.5 C6:1 A5:1 | G5:3~ r:1 | A5:1o C6:0.5 A5:0.5 G5:1 E5:1 | D5:3~ r:1",
		vel=0.78, pan=0.05)
	S.lead("sao", "sao_tr", 12, "A5:2^ G5:1 E5:1 | G5:3~v r:1", vel=0.75, pan=0.05)
	buses = {"sao": (0.62, 0.45, 0.2), "bau": (0.72, 0.45, 0.15), "guitar": (0.6, 0.35, 0.05), "tranh": (0.6, 0.45, 0.1),
		"pad": (0.3, 0.6, 0.0), "bass": (0.5, 0.1, 0.0), "trong": (0.4, 0.3, 0.0), "gong": (0.3, 0.4, 0.0)}
	return S.render(buses, dict(seconds=3.0, rt=(2.8, 2.3, 1.3, 0.6), seed=22, predelay=0.03), 1.0, -19.0, 8500.0)


# ===================================================================== memory (hơi Oán)

OAN_C = {3: -25.0, 5: 18.0, 8: 28.0}  # Xự (Eb) hơi thấp, Xang (F) hơi cao, Cống (Ab) nâng ~ giữa Ab–A
OAN_G = {10: -25.0, 0: 18.0, 3: 28.0}  # Hò=G: Xự (Bb) hơi thấp, Xang (C) hơi cao, Cống (Eb) nâng


def memory(sr: int = 24000) -> np.ndarray:
	"""Hồi ức với ông — sáo độc tấu chậm, câu verse của village chuyển sang hơi Oán (Hò=G), 60 BPM, 10 ô."""
	S = Song("memory", sr, 60, 10, seed=313, cents=OAN_G, human=0.01)
	S.pad_chord("pad", 0, ["G2", "D3", "G3"], 10, level=1.0, cutoff=800.0, attack=2.0, release=2.0)
	S.pluck_line("tranh", 0, "G4:1 D5:1 G5:2v", vel=0.42, pan=0.2, ring=3.5)
	S.pluck_line("tranh", 3, "C5:1 D5:1 G4:2v", vel=0.38, pan=0.2, ring=3.5)
	S.pluck_line("tranh", 9, "G4:2 D4:2v", vel=0.38, pan=0.2, ring=3.5)
	S.lead("sao", "sao_tr", 1, "G5:1.5 Bb5:0.5 G5:1 Eb5:1 | D5:1 Eb5:0.5 G5:0.5 Eb5:2~", vel=0.72, pan=0.05)
	S.lead("sao", "sao_tr", 4, "C5:1 D5:0.5 Eb5:0.5 G5:1 Eb5:0.5 D5:0.5 | D5:3~v r:1", vel=0.7, pan=0.05)
	S.lead("bau", "bau", 6, "Bb4:1.5^ G4:0.5 D4:2~", vel=0.6, pan=-0.12)
	S.lead("sao", "sao_tr", 7, "G5:1 Bb5:1 C6:1.5^ Bb5:0.5 | G5:4~v", vel=0.72, pan=0.05)
	S.hit("bowl", 0, 0, "bowl", 0.18, f0=392.0 * 2, dur=5.0, bright=0.5)
	buses = {"sao": (0.7, 0.5, 0.2), "bau": (0.65, 0.45, 0.15), "tranh": (0.72, 0.45, 0.1), "pad": (0.22, 0.55, 0.0),
		"bowl": (0.3, 0.5, 0.0)}
	return S.render(buses, dict(seconds=3.2, rt=(3.0, 2.6, 1.5, 0.6), seed=23, predelay=0.03), 1.0, -19.0, 7500.0)


# ===================================================================== battle / final

def _battle(name: str, sr: int, bpm: float, transpose: float, final: bool, seed: int) -> np.ndarray:
	"""Trận đá gà: trống chiến + song lang, riff ngũ cung đàn kìm/ tranh. Hò=D (D E G A B)."""
	sections = ([("intro", 2), ("A", 8), ("B", 8), ("B2", 8), ("A2", 8)] if final
		else [("intro", 4), ("A", 8), ("B", 8), ("break", 4), ("A2", 8)])
	bars = sum(n for _, n in sections)
	S = Song(name, sr, bpm, bars, swing16=0.0, seed=seed, transpose=transpose, human=0.003)
	start = {}
	acc = 0
	for sec, n in sections:
		start[sec] = acc
		acc += n
	RIFF = {
		"D": "D3:0.5 D3:0.25 D3:0.25 A3:0.5 D4:0.5 E4:0.5 D4:0.25 B3:0.25 A3:0.5 G3:0.5",
		"D2": "A3:0.75 B3:0.25 D4:0.5 E4:0.5 G4:0.5 E4:0.25 D4:0.25 B3:0.5 A3:0.5",
		"G": "G3:0.5 G3:0.25 G3:0.25 D4:0.5 G4:0.5 A4:0.5 G4:0.25 E4:0.25 D4:0.5 B3:0.5",
		"A": "A3:0.75 B3:0.25 D4:0.5 E4:0.5 A4:0.5 G4:0.25 E4:0.25 D4:0.5 E4:0.5",
	}
	ROOT = {"D": ("D2", "A2"), "G": ("G2", "D3"), "A": ("A2", "E3"), "Bm": ("B1", "B2")}
	PAD = {"D": ["D3", "A3", "E4"], "G": ["G3", "D4", "A4"], "A": ["A3", "E4", "B4"], "Bm": ["B2", "D3", "A3", "E4"]}
	BM_ARP = ["B3", "D4", "E4", "A4"]
	prog_a = ["D", "D", "G", "A"] * 2
	prog_b = ["Bm", "G", "D", "A"] * 2
	SCALE = ["D4", "E4", "G4", "A4", "B4", "D5", "E5", "G5", "A5", "B5", "D6"]

	def drums(bar: int, level: int) -> None:
		# level 0: chỉ trống trầm, 1: + song lang, 2: + trống cơm, 3: đầy đủ
		S.hit("trong", bar, 0, "trong", 0.9, f0=58.0, tau=0.28)
		S.hit("trong", bar, 2, "trong", 0.75, f0=58.0, tau=0.28)
		if level >= 3 or final and level >= 2:
			S.hit("trong", bar, 0.75, "trong", 0.6, f0=60.0, tau=0.25)
			S.hit("trong", bar, 2.5, "trong", 0.65, f0=60.0, tau=0.25)
		if level >= 1:
			for k in range(4):
				S.hit("songlang", bar, k + 0.5, "songlang", 0.62 if k % 2 else 0.5, pan=-0.35)
		if level >= 2:
			S.hit("trong_mid", bar, 1, "trong_mid", 0.8, pan=0.1)
			S.hit("trong_mid", bar, 3, "trong_mid", 0.85, pan=0.1)
			if bar % 2:
				S.hit("trong_mid", bar, 3.5, "trong_mid", 0.5, pan=0.15, f0=210.0)
		if level >= 3:
			for k in range(16):
				S.hit("shaker", bar, k * 0.25, "shaker", 0.5 if k % 2 else 0.28, pan=0.4, length=0.07)
			if final:
				S.hit("chap", bar, 1, "chap", 0.32, pan=0.3, open_=False)
				S.hit("chap", bar, 3, "chap", 0.36, pan=0.3, open_=False)

	def roll(bar: int) -> None:
		for k in range(16):
			S.hit("trong_mid", bar, k * 0.25, "trong_mid", 0.3 + 0.6 * k / 15, pan=0.1, f0=185.0 + 2.0 * k)

	def riff_bar(bar: int, chord: str, second: bool, octave_tranh: bool = True) -> None:
		key = "D2" if chord == "D" and second else chord
		S.pluck_line("kim", bar, RIFF[key], vel=0.72, pan=-0.25, inst="kim")
		if octave_tranh:
			S.pluck_line("tranh", bar, RIFF[key], vel=0.42, pan=0.3, oct_=1, ring=0.9)
		r, f = ROOT[chord]
		S.bass_line("bass", bar, [(0, 0.7, r, 0.9), (0.75, 0.5, r, 0.6), (1.5, 0.45, f, 0.65), (2, 0.7, r, 0.85),
			(2.75, 0.5, r, 0.6), (3.5, 0.45, f, 0.7)])

	# intro
	b0 = start["intro"]
	n_intro = 4 if not final else 2
	S.hit("gong", b0, 0, "gong", 0.6, f0=98.0 * 2 ** (transpose / 12))
	S.hit("chap", b0, 0, "chap", 0.6, pan=0.3)
	for k in range(n_intro):
		bar = b0 + k
		lvl = min(k, 2) if not final else 2
		drums(bar, lvl)
		S.pad_chord("pad", bar, PAD["D"], 1, level=0.8, cutoff=900.0, attack=0.4, release=0.8)
		S.bass_line("bass", bar, [(0, 0.5, "D2", 0.8), (2, 0.5, "D2", 0.7)])
	roll(b0 + n_intro - 1)
	S.tremolo("tranh", b0 + n_intro - 1, 0, "A4", 4, rate=14.0, vel=0.35, pan=0.3)

	def section_a(b: int, lead_sao: bool) -> None:
		S.hit("chap", b, 0, "chap", 0.7, pan=0.3)
		S.hit("gong", b, 0, "gong", 0.45, f0=98.0 * 2 ** (transpose / 12))
		S.gliss("tranh", b, -0.5, SCALE[:9], spacing=0.025, vel=0.35, pan=0.3)
		for k in range(8):
			chord = prog_a[k]
			riff_bar(b + k, chord, k % 2 == 1, octave_tranh=not lead_sao or k % 2 == 0)
			drums(b + k, 3)
			S.pad_chord("pad", b + k, PAD[chord], 1, level=0.7, cutoff=1000.0, attack=0.3, release=0.6)
		if not lead_sao:
			S.lead("sao", "sao", b + 3, "r:2 A5:0.5* B5:0.5 D6:1~", vel=0.7, pan=0.2)
			S.lead("sao", "sao", b + 7, "r:2 E6:0.5* D6:0.5 B5:0.5 D6:0.5", vel=0.7, pan=0.2)
		else:
			S.lead("sao", "sao", b, "D6:1 E6:0.5 D6:0.5 B5:1 A5:1 | B5:0.5 D6:0.5 E6:1 D6:2~ | "
				"G5:1 A5:0.5 B5:0.5 D6:1 B5:0.5 A5:0.5 | A5:3~ r:1", vel=0.78, pan=0.15)
			S.lead("sao", "sao", b + 4, "D6:1 E6:0.5 D6:0.5 B5:1 A5:1 | B5:0.5 D6:0.5 E6:1 G6:2^~ | "
				"E6:1 D6:0.5 B5:0.5 A5:1 G5:1 | A5:2~v r:2", vel=0.78, pan=0.15)
			if final:
				S.lead("bau", "bau", b, "D5:1 E5:0.5 D5:0.5 B4:1 A4:1 | B4:0.5 D5:0.5 E5:1 D5:2~ | "
					"G4:1 A4:0.5 B4:0.5 D5:1 B4:0.5 A4:0.5 | A4:3~ r:1", vel=0.6, pan=-0.15)

	def section_b(b: int, harmony: bool) -> None:
		S.hit("chap", b, 0, "chap", 0.6, pan=0.3)
		for k in range(8):
			chord = prog_b[k]
			r, f = ROOT[chord]
			tones = BM_ARP if chord == "Bm" else [x.replace("3", "4") for x in PAD[chord]]
			S.arp("tranh", b + k, tones, [0, 1, 2, 3, 2, 1, 0, 2], step=0.5, vel=0.4, pan=0.3, ring=1.0)
			S.pluck("kim", S.sec(b + k, 0), S.m(r) + 12, 0.7, -0.25, inst="kim")
			S.pluck("kim", S.sec(b + k, 1.5), S.m(f) + 12, 0.55, -0.25, inst="kim")
			S.pluck("kim", S.sec(b + k, 2.5), S.m(r) + 12, 0.6, -0.25, inst="kim")
			S.bass_line("bass", b + k, [(0, 0.7, r, 0.9), (0.75, 0.5, r, 0.6), (1.5, 0.45, f, 0.65), (2, 0.7, r, 0.85),
				(2.75, 0.5, r, 0.6), (3.5, 0.45, f, 0.7)])
			drums(b + k, 3 if (k >= 2 or final) else 2)
			S.pad_chord("pad", b + k, PAD[chord], 1, level=0.8, cutoff=1100.0, attack=0.3, release=0.6)
		mel = ("B4:1.5 D5:0.5 E5:1 D5:0.5 B4:0.5 | D5:1.5^ E5:0.5 G5:2~ | A5:1 G5:0.5 E5:0.5 D5:1 E5:0.5 G5:0.5 | "
			"E5:3~v r:1 | B5:1 A5:0.5 G5:0.5 E5:1 D5:1 | E5:1.5^ D5:0.5 B4:2~ | A4:0.5 B4:0.5 D5:0.5 E5:0.5 G5:1 A5:1 | A5:3~v r:1")
		S.lead("bau", "bau", b, mel, vel=0.85, pan=-0.05)
		if harmony:
			harm = ("E5:1.5 G5:0.5 A5:1 G5:0.5 E5:0.5 | G5:1.5^ A5:0.5 B5:2~ | D6:1 B5:0.5 A5:0.5 G5:1 A5:0.5 B5:0.5 | "
				"A5:3~v r:1 | E6:1 D6:0.5 B5:0.5 A5:1 G5:1 | A5:1.5^ G5:0.5 E5:2~ | D5:0.5 E5:0.5 G5:0.5 A5:0.5 B5:1 D6:1 | D6:3~v r:1")
			S.lead("sao", "sao", b, harm, vel=0.62, pan=0.22)

	section_a(start["A"], lead_sao=False)
	section_b(start["B"], harmony=False)
	if final:
		section_b(start["B2"], harmony=True)
	else:
		bb = start["break"]
		for k in range(4):
			drums(bb + k, 1 if k < 3 else 2)
			S.pad_chord("pad", bb + k, PAD["D"], 1, level=0.9, cutoff=800.0, attack=0.5, release=0.8)
			S.bass_line("bass", bb + k, [(0, 1.5, "D2", 0.7)])
		S.tremolo("tranh", bb, 0, "D5", 4, rate=13.0, vel=0.32, pan=0.3)
		S.tremolo("tranh", bb + 1, 0, "E5", 4, rate=13.0, vel=0.32, pan=0.3)
		S.tremolo("tranh", bb + 2, 0, "A5", 4, rate=13.0, vel=0.34, pan=0.3)
		S.gliss("tranh", bb + 3, 0, SCALE, spacing=0.03, vel=0.4, pan=0.3)
		S.lead("bau", "bau", bb, "A4:4~ | G4:2^ A4:2~ | B4:3~ A4:1 | A4:2~v r:2", vel=0.7, pan=-0.05)
		roll(bb + 3)
	section_a(start["A2"], lead_sao=True)
	buses = {"kim": (0.6, 0.12, 0.04), "tranh": (0.36, 0.18, 0.06), "bau": (0.62, 0.25, 0.1),
		"sao": (0.48, 0.25, 0.12), "bass": (0.6, 0.03, 0.0), "pad": (0.2, 0.3, 0.0),
		"trong": (0.5, 0.08, 0.0), "trong_mid": (0.4, 0.12, 0.0), "songlang": (0.38, 0.1, 0.0),
		"shaker": (0.17, 0.08, 0.0), "chap": (0.22, 0.2, 0.0), "gong": (0.4, 0.3, 0.0)}
	return S.render(buses, dict(seconds=1.8, rt=(1.5, 1.2, 0.7, 0.35), seed=24), 0.75, -16.5, 9500.0,
		wow_ms=0.15, drive=1.6)


def battle(sr: int = 24000) -> np.ndarray:
	return _battle("battle", sr, 128.0, 0.0, False, 404)


def final(sr: int = 24000) -> np.ndarray:
	return _battle("final", sr, 136.0, 2.0, True, 505)


# ===================================================================== jingles

def jingle_victory(sr: int = 24000) -> np.ndarray:
	S = Song("jingle_victory", sr, 120, 2, loop=False, tail=0.4, seed=606, human=0.002, transpose=2.0)
	SC = ["C4", "D4", "F4", "G4", "A4", "C5", "D5", "F5", "G5", "A5", "C6"]
	S.gliss("tranh", 0, 0, SC, spacing=0.032, vel=0.55, pan=0.2)
	S.hit("trong", 0, 0, "trong", 0.8, f0=60.0)
	S.lead("sao", "sao", 0, "r:1 G5:0.5* A5:0.5 C6:0.5* D6:0.5 F6:0.5 D6:0.5 | C6:3~ r:1", vel=0.8, pan=0.15)
	S.lead("bau", "bau", 0, "r:1 G4:0.5 A4:0.5 C5:0.5 D5:0.5 F5:0.5 D5:0.5 | C5:3~ r:1", vel=0.65, pan=-0.15)
	for b in (1.0, 1.5, 2.0, 2.5):
		S.hit("trong_mid", 0, b, "trong_mid", 0.7, pan=0.1)
	S.hit("trong", 1, 0, "trong", 0.95, f0=58.0)
	S.hit("gong", 1, 0, "gong", 0.6, f0=98.0 * 2 ** (2 / 12), dur=3.0)
	S.hit("chap", 1, 0, "chap", 0.7, pan=0.3)
	S.pad_chord("pad", 1, ["C3", "G3", "D4", "A4"], 0.75, level=0.9, attack=0.05, release=0.9)
	S.bass_line("bass", 1, [(0, 2.5, "C2", 0.9)])
	S.pluck("tranh", S.sec(1, 0), S.m("C5"), 0.5, 0.3)
	S.pluck("tranh", S.sec(1, 0) + 0.02, S.m("G5"), 0.45, 0.35)
	buses = {"tranh": (0.45, 0.3, 0.05), "sao": (0.55, 0.3, 0.1), "bau": (0.55, 0.3, 0.1), "trong": (0.6, 0.1, 0.0),
		"trong_mid": (0.4, 0.1, 0.0), "gong": (0.4, 0.3, 0.0), "chap": (0.22, 0.2, 0.0), "pad": (0.3, 0.4, 0.0),
		"bass": (0.5, 0.0, 0.0)}
	return S.render(buses, dict(seconds=2.0, rt=(1.8, 1.4, 0.8, 0.4), seed=25), 0.75, -15.0, 10000.0, wow_ms=0.0)


def jingle_defeat(sr: int = 24000) -> np.ndarray:
	S = Song("jingle_defeat", sr, 80, 2, bpb=2, loop=False, tail=0.35, seed=707, cents=OAN_C, human=0.003)
	S.pluck("tranh", S.sec(0, 0), S.m("C3"), 0.6, 0.15, ring=3.0)
	S.pluck("tranh", S.sec(0, 0) + 0.03, S.m("G3"), 0.5, 0.25, ring=3.0)
	S.hit("trong", 0, 0, "trong", 0.6, f0=52.0, tau=0.5, dur=1.5)
	S.lead("bau", "bau", 0, "G4:0.75^ F4:0.75~ Eb4:0.5 | C4:2~v", vel=0.85, pan=-0.05, oct_=0)
	S.pad_chord("pad", 0, ["C3", "G3", "C4"], 1.3, level=0.9, attack=0.4, release=1.0, cutoff=800.0)
	S.hit("trong", 1, 0, "trong", 0.4, f0=48.0, tau=0.6, dur=1.5)
	buses = {"tranh": (0.45, 0.35, 0.0), "bau": (0.65, 0.4, 0.12), "trong": (0.5, 0.2, 0.0), "pad": (0.35, 0.5, 0.0)}
	return S.render(buses, dict(seconds=2.0, rt=(2.0, 1.6, 0.9, 0.4), seed=26), 0.75, -17.0, 8000.0, wow_ms=0.0)


def jingle_reward(sr: int = 24000) -> np.ndarray:
	S = Song("jingle_reward", sr, 120, 1, bpb=3, loop=False, tail=0.0, seed=808, human=0.0)
	for i, nm in enumerate(["C5", "D5", "F5", "G5", "A5", "C6"]):
		S.pluck("tranh", 0.06 * i, S.m(nm), 0.45 + 0.05 * i, -0.2 + 0.08 * i, ring=1.2)
	S.hit("bowl", 0, 0.75, "bowl", 0.35, f0=1046.5, dur=1.1, bright=0.6)
	S.hit("songlang", 0, 0, "songlang", 0.4, pan=-0.3)
	S.hit("songlang", 0, 0.75, "songlang", 0.5, pan=-0.3, pitch=1.15)
	buses = {"tranh": (0.5, 0.25, 0.0), "bowl": (0.35, 0.3, 0.0), "songlang": (0.25, 0.1, 0.0)}
	return S.render(buses, dict(seconds=1.0, rt=(1.0, 0.8, 0.5, 0.3), seed=27), 0.5, -16.0, 10000.0, wow_ms=0.0)

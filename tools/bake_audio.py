#!/usr/bin/env python3
"""
Bakes the procedural WebAudio sounds of Fstreli Biciklina (v4) into WAV files.

The web game synthesises everything at runtime (noise through filters, oscillators with
pitch ramps, formant "voices", a convolution reverb). This script re-implements those
same recipes offline with numpy/scipy, so Godot only has to play ready-made samples.

    python3 tools/bake_audio.py        ->  writes DRY audio/*.wav   (v5 default)
    python3 tools/bake_audio.py --wet  ->  old behaviour: reverb baked into every file

Needs: numpy, scipy.   Panning is NOT baked in: Godot positions sounds in 3D instead.

v5: the samples are written dry. The old baked reverb (a mono noise impulse response) sounded metallic
and, being part of the file, moved with the sound's 3D position. Godot now adds one shared reverb on
the "SFX" bus instead (see scripts/sfx.gd). The wet send amounts in the recipes below are kept so
--wet still works, but are ignored in the default dry mode.
"""
import os, sys, wave
import numpy as np
from scipy.signal import lfilter, fftconvolve

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1234)

def rand(a, b):
    return float(rng.uniform(a, b))

# ---------------------------------------------------------------- reverb impulse (as in initAudio)
IR_LEN = int(SR * 1.6)
IR = (rng.uniform(-1, 1, IR_LEN) * (1 - np.arange(IR_LEN) / IR_LEN) ** 3).astype(np.float64)
BAKE_REVERB = "--wet" in sys.argv
REVERB_GAIN = 0.3
MASTER = 0.9

# ---------------------------------------------------------------- filters
def biquad(ftype, f, q):
    f = min(max(f, 10.0), SR * 0.45)
    w0 = 2 * np.pi * f / SR
    c, s = np.cos(w0), np.sin(w0)
    if ftype == "bandpass":
        alpha = s / (2 * max(q, 0.01))
        b0, b1, b2 = alpha, 0.0, -alpha
    else:
        qlin = 10 ** (q / 20.0)            # WebAudio: Q of lowpass/highpass is in dB
        alpha = s / (2 * qlin)
        if ftype == "lowpass":
            b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
        else:
            b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    a0, a1, a2 = 1 + alpha, -2 * c, 1 - alpha
    return np.array([b0, b1, b2]) / a0, np.array([1.0, a1 / a0, a2 / a0])

def filt(x, ftype, fcurve, q, block=64):
    """time-varying biquad: fcurve(t_seconds) -> Hz"""
    y = np.zeros_like(x)
    zi = np.zeros(2)
    for i in range(0, len(x), block):
        seg = x[i:i + block]
        b, a = biquad(ftype, fcurve((i + len(seg) / 2) / SR), q)
        out, zi = lfilter(b, a, seg, zi=zi)
        y[i:i + block] = out
    return y

def expramp(n, v0, v1, dur):
    t = np.arange(n) / SR
    k = np.clip(t / dur, 0, 1)
    return v0 * (v1 / v0) ** k

def freq_ramp(n, f0, f1, dur):
    return expramp(n, f0, max(20.0, f1), dur)

# ---------------------------------------------------------------- mixer
class Mix:
    def __init__(self):
        self.dry = np.zeros(int(SR * 6))
        self.wet = np.zeros(int(SR * 6))
        self.end = 0
        self.has_wet = False

    def add(self, sig, t, wet=0.0):
        i = int(round(t * SR))
        n = len(sig)
        self.dry[i:i + n] += sig
        if wet:
            self.wet[i:i + n] += sig * wet
            self.has_wet = True
        self.end = max(self.end, i + n)

    def render(self, peak_limit=0.98):
        n = self.end
        out = self.dry[:n].copy()
        if BAKE_REVERB and self.has_wet:
            conv = fftconvolve(self.wet[:n], IR)
            out = np.concatenate([out, np.zeros(len(conv) - n)])
            out += REVERB_GAIN * conv
        out *= MASTER
        pk = np.max(np.abs(out)) if len(out) else 0
        if pk > peak_limit:
            out *= peak_limit / pk
        # trim near-silent tail
        thr = 0.0005
        idx = np.where(np.abs(out) > thr)[0]
        if len(idx):
            out = out[:min(len(out), idx[-1] + int(0.05 * SR))]
        return out

# ---------------------------------------------------------------- sources (WebAudio recipes)
def noise(n):
    return rng.uniform(-1, 1, n)

def osc_wave(kind, phase):
    if kind == "sine":
        return np.sin(phase)
    if kind == "square":
        return np.sign(np.sin(phase))
    if kind == "triangle":
        return 2 / np.pi * np.arcsin(np.sin(phase))
    return 2 * ((phase / (2 * np.pi)) % 1.0) - 1.0       # sawtooth

def nz(M, t, dur, ftype, f0, f1, q, vol, wet=0.0):
    n = int((dur + 0.05) * SR)
    x = noise(n)
    y = filt(x, ftype, lambda tt: f0 * (max(20.0, f1) / f0) ** min(1.0, tt / dur), q)
    y *= expramp(n, vol, 0.0008, dur)
    M.add(y, t, wet)

def sine(M, t, f0, f1, dur, vol, wet=0.0, kind="sine"):
    n = int((dur + 0.05) * SR)
    f = freq_ramp(n, f0, f1, dur)
    phase = 2 * np.pi * np.cumsum(f) / SR
    y = osc_wave(kind, phase) * expramp(n, vol, 0.0008, dur)
    M.add(y, t, wet)

def ring(M, t, f, vol, dur, wet):
    parts = [1, 2.76, 5.4, 8.93]
    amps = [1, 0.5, 0.25, 0.12]
    for i, (p, a) in enumerate(zip(parts, amps)):
        d = dur / (1 + i * 0.6)
        n = int((dur + 0.05) * SR)
        tt = np.arange(n) / SR
        env = vol * a * (0.0008 / (vol * a)) ** np.clip(tt / d, 0, 1)
        M.add(np.sin(2 * np.pi * f * p * tt) * env, t, wet)

def clank(M, t, vol):
    f = rand(2200, 4800)
    nz(M, t, 0.18, "bandpass", f, f * 0.9, 14, vol * 1.6, 0.35)
    sine(M, t, f * 0.5, f * 0.48, 0.16, vol * 0.25, 0.3, "triangle")

# ---------------------------------------------------------------- formant voices
VOW = {"a": [800, 1150, 2900], "o": [500, 900, 2800], "u": [330, 800, 2800], "e": [530, 1850, 2480],
       "i": [280, 2250, 2900], "ae": [690, 1700, 2450], "ah": [730, 1090, 2440]}

def voice(M, o, t0=0.0):
    t = t0 + o.get("delay", 0.0)
    dur = o["dur"]
    n = int((dur + 0.05) * SR)
    tt = np.arange(n) / SR
    f0 = o["f0"]
    xs = np.linspace(0, dur, len(f0))
    f = np.interp(tt, xs, f0)
    vib = np.sin(2 * np.pi * o.get("vib", 5.5) * tt) * f0[0] * 0.02
    phase = 2 * np.pi * np.cumsum(f + vib) / SR
    src = osc_wave("sawtooth", phase)
    vol = o["vol"]
    amp = np.where(tt < 0.04, 0.0001 * (vol / 0.0001) ** np.clip(tt / 0.04, 0, 1), vol)
    late = tt > dur * 0.6
    amp = np.where(late, vol * (0.0001 / vol) ** np.clip((tt - dur * 0.6) / (dur * 0.4), 0, 1), amp)
    mix = np.zeros(n)
    gains, qs = [7, 5, 3.2], [7, 9, 11]
    seq = o["seq"]
    for i in range(3):
        times = [s[0] * dur for s in seq]
        freqs = [VOW[s[1]][i] for s in seq]
        fc = lambda x, times=times, freqs=freqs: float(np.interp(x, times, freqs))
        mix += filt(src, "bandpass", fc, qs[i]) * gains[i]
    M.add(mix * amp, t, 0.2)
    if o.get("breath"):
        nz(M, t, min(0.12, dur), "bandpass", 2200, 2600, 1.2, o["breath"], 0.1)

def v_yelp(M, t=0.0):
    voice(M, {"seq": [[0, "o"], [0.3, "ah"], [1, "ah"]], "f0": [170, 215, 90], "dur": 0.62, "vol": 0.4, "breath": 0.05}, t)
def v_hey(M, k, t=0.0):
    voice(M, {"seq": [[0, "e"], [0.45, "ae"], [1, "e"]], "f0": [200 * k, 255 * k, 190 * k], "dur": 0.46, "vol": 0.38, "breath": 0.14}, t)
def v_gasp(M):
    nz(M, 0, 0.26, "bandpass", 1200, 2400, 1.5, 0.3, 0.15)
def v_cheer(M, t=0.0):
    for i in range(4):
        voice(M, {"delay": i * 0.07, "seq": [[0, "u"], [0.5, "a"], [1, "a"]],
                  "f0": [170 + i * 45, 260 + i * 50, 240 + i * 45], "dur": 0.8, "vol": 0.18}, t)
def v_groan(M):
    for i in range(3):
        voice(M, {"delay": i * 0.1, "seq": [[0, "o"], [1, "u"]], "f0": [150 + i * 25, 105 + i * 18], "dur": 1.0, "vol": 0.18})

# ---------------------------------------------------------------- output
written = []

# The old baked reverb (mono noise impulse, gain 0.3) was LOUD and made up most of the level of some sounds
# (the siren peaked at 0.94 with reverb, 0.04 without). In dry mode these get make-up gain so the game keeps
# roughly its old loudness. Values are matched against the previous wet files; tweak to taste.
DRY_GAIN = {"siren": 6.0, "pickup": 2.4, "boss_intro": 1.6, "clear": 1.9, "clank2": 1.8, "shell_drop": 2.0,
            "bird": 2.0, "ring": 1.5, "boss_hit_mower": 1.3, "land_l": 1.2}

def dry_gain(name):
    if BAKE_REVERB:
        return 1.0
    for key, g in DRY_GAIN.items():
        if name == key or name.startswith(key + "_"):
            return g
    return 1.0

def save(name, sig, stereo=False, loop_fade=0.0):
    sig = np.asarray(sig) * dry_gain(name)
    if stereo:
        data = np.clip(sig, -1, 1)
        arr = (data * 32767).astype("<i2").reshape(-1)       # interleaved L R
        ch = 2
    else:
        arr = (np.clip(sig, -1, 1) * 32767).astype("<i2")
        ch = 1
    if name.startswith("v_") or name == "boss_down_minister":
        arr = (arr.astype(np.float64) * 0.55).astype("<i2")      # the formant voices come out hot, tame them
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(ch); w.setsampwidth(2); w.setframerate(SR); w.writeframes(arr.tobytes())
    written.append(name)

def one(name, fn):
    M = Mix(); fn(M); save(name, M.render())

def variants(name, count, fn):
    for i in range(count):
        one("%s_%d" % (name, i), fn)

# ================================================================= the sound effects
def sfx_shot(M):
    sine(M, 0, 220, 70, 0.09, 0.55, 0.05, "triangle")
    nz(M, 0, 0.07, "lowpass", 900, 250, 0.7, 0.5, 0.05)
    nz(M, 0.005, 0.06, "bandpass", 1400, 700, 2.5, 0.7, 0.1)
    nz(M, 0.03, 0.14, "bandpass", 2600, 4800, 1.2, 0.12, 0.1)
one("shot", sfx_shot)

def sfx_click(M):
    nz(M, 0, 0.02, "highpass", 2500, 2500, 0.7, 0.25, 0.05)
    nz(M, 0, 0.03, "bandpass", 1100, 900, 3, 0.2, 0.05)
one("click", sfx_click)

def sfx_pump(M):
    for i in range(5):
        nz(M, i * 0.022, 0.018, "bandpass", 2600, 2200, 7, 0.28, 0.05)
    nz(M, 0.13, 0.05, "bandpass", 1800, 1000, 5, 0.5, 0.08)
    sine(M, 0.13, 360, 160, 0.06, 0.2, 0.05, "square")
one("pump", sfx_pump)

def sfx_shell_tick(M):
    nz(M, 0, 0.035, "bandpass", 2800, 2000, 8, 0.35, 0.1)
    sine(M, 0, 900, 500, 0.05, 0.14, 0, "square")
one("shell_tick", sfx_shell_tick)

def sfx_shell_drop(M):
    sine(M, 0, 3300, 3100, 0.16, 0.08, 0.3)
    sine(M, 0.09, 3100, 2900, 0.12, 0.05, 0.3)
one("shell_drop", sfx_shell_drop)

def sfx_hit(M):
    sine(M, 0, 150, 50, 0.18, 0.6, 0.1)
    nz(M, 0, 0.14, "lowpass", 900, 200, 0.7, 0.6, 0.15)
    clank(M, 0.03, 0.3); clank(M, 0.11, 0.22); clank(M, 0.2, 0.16)
variants("hit", 3, sfx_hit)

def make_land(k):
    def f(M):
        sine(M, 0, 120, 45, 0.15, 0.45 * k, 0.15)
        nz(M, 0, 0.12, "lowpass", 800, 150, 0.7, 0.55 * k, 0.2)
        if k > 0.3:
            clank(M, 0.02, 0.25 * k)
    return f
one("land_s", make_land(0.25)); one("land_m", make_land(0.6)); one("land_l", make_land(1.0))

def sfx_thud(M):
    sine(M, 0, 520, 160, 0.12, 0.35, 0.1, "triangle")
    nz(M, 0, 0.06, "lowpass", 1200, 300, 0.7, 0.3, 0.1)
one("thud", sfx_thud)

def sfx_whoosh(M):
    n = int(1.0 * SR)
    x = noise(n)
    y = filt(x, "bandpass", lambda t: 350 * (1500 / 350) ** min(1, t / 0.9), 1.1)
    t = np.arange(n) / SR
    env = np.where(t < 0.35, 0.0001 * (0.22 / 0.0001) ** (t / 0.35), 0.22 * (0.0001 / 0.22) ** np.clip((t - 0.35) / 0.55, 0, 1))
    M.add(y * env, 0, 0.15)
one("whoosh", sfx_whoosh)

def sfx_clear(M):
    ring(M, 0, 2350, 0.12, 1.1, 0.25); ring(M, 0.22, 2350, 0.12, 1.3, 0.25)
one("clear", sfx_clear)

def sfx_over(M):
    ring(M, 0, 130, 0.3, 2.2, 0.4)
    sine(M, 0, 70, 40, 0.5, 0.35, 0.2)
one("over", sfx_over)

def stereo_pan(mono, p0, p1):
    n = len(mono)
    pan = np.linspace(p0, p1, n)
    ang = (pan + 1) * np.pi / 4
    return np.stack([mono * np.cos(ang), mono * np.sin(ang)], axis=1) * MASTER

def sfx_car(direction):
    d = 3.0
    n = int(d * SR)
    t = np.arange(n) / SR
    f = 100 + (88 - 100) * t / d
    saw = osc_wave("sawtooth", 2 * np.pi * np.cumsum(f) / SR)
    saw = filt(saw, "lowpass", lambda x: 420, 1.0)
    env = np.interp(t, [0, d * 0.5, d], [0.0001, 0.07, 0.0001])
    nz_ = filt(noise(n), "bandpass", lambda x: 650, 0.9)
    env2 = np.interp(t, [0, d * 0.5, d], [0.0001, 0.05, 0.0001])
    mono = saw * env + nz_ * env2
    return stereo_pan(mono, -direction * 0.9, direction * 0.9)
save("car_0", sfx_car(1), stereo=True); save("car_1", sfx_car(-1), stereo=True)

def sfx_bird(M):
    n_ = 2 + int(rng.integers(0, 3))
    for i in range(n_):
        sine(M, i * 0.11, 3200 + rand(0, 900), 4300 + rand(0, 900), 0.07, 0.05, 0.3)
variants("bird", 3, sfx_bird)

def sfx_siren(M):
    n = int(3.3 * SR)
    t = np.arange(n) / SR
    pts_t = [0] + [0.5 * (i + 1) for i in range(6)]
    pts_f = [700] + [700 if i % 2 else 1000 for i in range(6)]
    f = np.interp(t, pts_t, pts_f)
    y = osc_wave("triangle", 2 * np.pi * np.cumsum(f) / SR)
    y = filt(y, "lowpass", lambda x: 2000, 1.0)
    env = np.interp(t, [0, 0.5, 2.4, 3.2], [0.0001, 0.05, 0.05, 0.0001])
    M.add(y * env, 0, 0.5)
one("siren", sfx_siren)

def sfx_pickup(M):
    sine(M, 0, 660, 660, 0.08, 0.16, 0.2, "square")
    sine(M, 0.08, 880, 880, 0.08, 0.16, 0.2, "square")
    sine(M, 0.16, 1320, 1320, 0.18, 0.16, 0.3, "square")
one("pickup", sfx_pickup)

def sfx_clank2(M):
    clank(M, 0, 0.4); clank(M, 0.05, 0.25)
variants("clank2", 2, sfx_clank2)

def sfx_swing(M):
    nz(M, 0, 0.16, "bandpass", 500, 1800, 1.2, 0.3, 0.1)
one("swing", sfx_swing)

def sfx_rubber(M):
    sine(M, 0, 320, 110, 0.14, 0.5, 0.1)
    nz(M, 0, 0.05, "lowpass", 900, 300, 0.7, 0.35, 0.1)
one("rubber", sfx_rubber)

def sfx_boss_intro(M):
    sine(M, 0, 110, 100, 0.5, 0.35, 0.3, "sawtooth")
    sine(M, 0.6, 110, 95, 0.6, 0.35, 0.3, "sawtooth")
one("boss_intro", sfx_boss_intro)

def hit_mower(M):
    clank(M, 0, 0.38); nz(M, 0, 0.1, "bandpass", 2000, 900, 3, 0.3, 0.1)
variants("boss_hit_mower", 2, hit_mower)
def hit_wifi(M):
    nz(M, 0, 0.12, "highpass", 3000, 6000, 2, 0.35, 0.1)
    sine(M, 0, 1800, 400, 0.1, 0.18, 0.1, "square")
one("boss_hit_wifi", hit_wifi)
def hit_min(M):
    sine(M, 0, 520, 180, 0.12, 0.35, 0.1, "triangle")
    nz(M, 0, 0.06, "lowpass", 1200, 300, 0.7, 0.3, 0.1)
one("boss_hit_minister", hit_min)

def down_metal(M):
    nz(M, 0, 0.7, "lowpass", 2400, 90, 0.7, 0.8, 0.5)
    sine(M, 0, 100, 30, 0.6, 0.7, 0.3)
    clank(M, 0.05, 0.3); clank(M, 0.2, 0.25)
one("boss_down", down_metal)
def down_minister(M):
    nz(M, 0, 0.7, "lowpass", 2400, 90, 0.7, 0.8, 0.5)
    sine(M, 0, 100, 30, 0.6, 0.7, 0.3)
    v_cheer(M)
one("boss_down_minister", down_minister)

def sfx_crash(M):
    nz(M, 0, 0.45, "lowpass", 1800, 120, 0.7, 0.9, 0.3)
    sine(M, 0, 110, 32, 0.45, 0.8, 0.2)
    clank(M, 0.02, 0.3)
one("crash", sfx_crash)

def sfx_step(M):
    sine(M, 0, 110, 50, 0.08, 0.35, 0.05)
    nz(M, 0, 0.05, "lowpass", 500, 150, 0.7, 0.28, 0.05)
one("step", sfx_step)

def sfx_throw(M):
    nz(M, 0, 0.2, "bandpass", 900, 2200, 1.5, 0.18, 0.1)
one("throw", sfx_throw)

def sfx_ring(M):
    for i in range(2):
        for k in range(8):
            sine(M, i * 0.55 + k * 0.04, 1500, 1450, 0.03, 0.12, 0.1, "square")
one("ring", sfx_ring)

def sfx_phone_smash(M):
    nz(M, 0, 0.12, "bandpass", 3000, 1500, 4, 0.4, 0.2)
    sine(M, 0, 200, 70, 0.1, 0.35, 0.1)
    clank(M, 0.04, 0.2)
variants("phone_smash", 2, sfx_phone_smash)

# voices
one("v_yelp", v_yelp)
for i, k in enumerate([0.7, 0.8, 1.2, 1.3]):
    one("v_hey_%d" % i, lambda M, k=k: v_hey(M, k))
one("v_gasp", v_gasp)
one("v_cheer", v_cheer)
one("v_groan", v_groan)

# ================================================================= seamless loops
def make_loop(name, sig, fade=0.12):
    f = int(fade * SR)
    head, tail = sig[:f].copy(), sig[-f:].copy()
    w = np.linspace(0, 1, f)
    body = sig[:-f].copy()
    body[:f] = head * w + tail * (1 - w)
    save(name, body * MASTER)

n2 = int(2.0 * SR)
rider = filt(noise(n2 + int(0.12 * SR)), "bandpass", lambda t: 700, 1.4)
rider /= np.max(np.abs(rider)); make_loop("loop_rider", rider * 0.8)

amb = filt(noise(n2 + int(0.12 * SR)), "lowpass", lambda t: 450, 1.0)
amb /= np.max(np.abs(amb)); make_loop("loop_ambient", amb * 0.8)

# mower: 80 Hz saw through a 700 Hz lowpass (exactly 80 cycles per 1 s loop)
n1 = SR
t = np.arange(n1) / SR
mower = osc_wave("sawtooth", 2 * np.pi * 80 * t)
mower = filt(np.tile(mower, 3), "lowpass", lambda x: 700, 1.0)[n1:2 * n1]
save("loop_mower", mower / np.max(np.abs(mower)) * 0.8 * MASTER)

# wifi node: 880 Hz square with 9 Hz FM (depth 200 Hz), 1 s loop
phase = 2 * np.pi * 880 * t + (200 / 9.0) * (1 - np.cos(2 * np.pi * 9 * t))   # FM: 880 Hz +- 200 Hz at 9 Hz
wifi = np.sign(np.sin(phase))
wifi = filt(np.tile(wifi, 3), "lowpass", lambda x: 2200, 1.0)[n1:2 * n1]
save("loop_wifi", wifi / np.max(np.abs(wifi)) * 0.8 * MASTER)

print("baked %d files into %s" % (len(written), os.path.abspath(OUT)))

"""Synthesises every sound in the game (no samples, nothing borrowed): effects, ambient loops and the
Sable Radio music. Writes OGG Vorbis files to assets/audio.

    python3 tools/audio/make_audio.py            # everything
    python3 tools/audio/make_audio.py gun_pistol  # just some
"""
import os
import subprocess
import sys
import numpy as np
from scipy.io import wavfile
from scipy import signal

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
rng = np.random.default_rng(7)


def t_(d):
    return np.arange(int(d * SR)) / SR


def env(n, a=0.002, d=0.1, s=0.0, r=0.05, hold=0.0):
    """ADSR envelope of n samples."""
    a_, d_, h_, r_ = int(a * SR), int(d * SR), int(hold * SR), int(r * SR)
    e = np.concatenate([np.linspace(0, 1, max(1, a_)), np.linspace(1, s, max(1, d_)), np.full(max(0, h_), s), np.linspace(s, 0, max(1, r_))])
    if len(e) < n:
        e = np.concatenate([e, np.zeros(n - len(e))])
    return e[:n]


def expdec(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def noise(d):
    return rng.uniform(-1, 1, int(d * SR))


def lp(x, f, order=2):
    b, a = signal.butter(order, min(f / (SR / 2), 0.99), "low")
    return signal.lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = signal.butter(order, min(f / (SR / 2), 0.99), "high")
    return signal.lfilter(b, a, x)


def bp(x, f1, f2, order=2):
    b, a = signal.butter(order, [f1 / (SR / 2), min(f2 / (SR / 2), 0.99)], "band")
    return signal.lfilter(b, a, x)


def brown(d):
    x = np.cumsum(noise(d))
    x = hp(x, 20)
    return x / (np.abs(x).max() + 1e-9)


def norm(x, peak=0.9):
    m = np.abs(x).max()
    return x * (peak / m) if m > 0 else x


def save(name, x, peak=0.9, loop=False):
    os.makedirs(OUT, exist_ok=True)
    x = norm(np.asarray(x, dtype=np.float64), peak)
    if loop:  # crossfade the tail into the head so it loops cleanly
        n = int(0.25 * SR)
        x[:n] = x[:n] * np.linspace(0, 1, n) + x[-n:] * np.linspace(1, 0, n)
        x = x[:-n]
    wav = "/tmp/_a_%s.wav" % name
    wavfile.write(wav, SR, (x * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(wav)
    print("audio", name, "%.2fs" % (len(x) / SR))


# ------------------------------------------------------------------ effects
def gun(body_f=180, crack=0.35, tail=0.35, d=0.6):
    n = int(d * SR)
    x = noise(d)
    crack_ = hp(x, 1800) * expdec(n, 0.012) * crack * 3
    boom = lp(x, 900) * expdec(n, 0.06) * 2.0
    thump = np.sin(2 * np.pi * body_f * t_(d) * np.exp(-t_(d) * 6)) * expdec(n, 0.05)
    room = lp(x, 500) * expdec(n, tail) * 0.35
    return np.tanh((crack_ + boom + thump + room) * 1.6)


def fx():
    S = {}
    S["gun_pistol"] = gun(190, 0.4, 0.25, 0.5)
    S["gun_heavy"] = gun(120, 0.5, 0.5, 0.8)
    S["gun_shotgun"] = gun(90, 0.7, 0.6, 0.9) + lp(noise(0.9), 300) * expdec(int(0.9 * SR), 0.2) * 0.5
    S["gun_rifle"] = gun(150, 0.8, 0.45, 0.8)
    S["gun_empty"] = hp(noise(0.05), 2500) * expdec(int(0.05 * SR), 0.006)
    S["enemy_gun"] = lp(gun(170, 0.3, 0.3, 0.6), 2200) * 0.7
    # melee
    d = 0.22
    S["swing"] = bp(noise(d), 400, 2400) * np.sin(np.linspace(0, np.pi, int(d * SR))) ** 2
    d = 0.25
    S["hit_flesh"] = (lp(noise(d), 700) * expdec(int(d * SR), 0.05) * 1.5 + np.sin(2 * np.pi * 90 * t_(d)) * expdec(int(d * SR), 0.06))
    S["hit_metal"] = sum(np.sin(2 * np.pi * f * t_(0.5)) * expdec(int(0.5 * SR), 0.12 / k) for k, f in enumerate([520, 1310, 2190, 3140], 1)) + hp(noise(0.5), 3000) * expdec(int(0.5 * SR), 0.01)
    # creatures
    d = 0.9
    tt = t_(d)
    f0 = 95 + 25 * np.sin(2 * np.pi * 2.2 * tt) + 15 * rng.standard_normal(len(tt)).cumsum() / 200
    ph = 2 * np.pi * np.cumsum(f0) / SR
    growl = signal.sawtooth(ph) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * tt))
    S["ghoul_groan"] = bp(growl + noise(d) * 0.4, 150, 1400) * env(len(tt), 0.08, 0.3, 0.7, 0.35, 0.2)
    S["ghoul_die"] = bp(signal.sawtooth(2 * np.pi * np.cumsum(np.linspace(140, 50, len(tt))) / SR) + noise(d) * 0.5, 100, 1200) * env(len(tt), 0.01, 0.2, 0.5, 0.5, 0.2)
    d = 0.45
    tt = t_(d)
    S["raider_shout"] = bp(signal.square(2 * np.pi * np.cumsum(200 + 60 * np.sin(2 * np.pi * 7 * tt)) / SR) * 0.6 + noise(d) * 0.3, 300, 2500) * env(len(tt), 0.02, 0.1, 0.8, 0.15, 0.2)
    S["rat_squeak"] = np.sin(2 * np.pi * np.cumsum(2400 + 900 * np.sin(2 * np.pi * 18 * t_(0.25))) / SR) * env(int(0.25 * SR), 0.01, 0.1, 0.4, 0.1, 0.05)
    S["dog_bark"] = bp(signal.sawtooth(2 * np.pi * np.cumsum(np.linspace(520, 300, int(0.18 * SR))) / SR) + noise(0.18) * 0.6, 250, 3000) * env(int(0.18 * SR), 0.005, 0.05, 0.6, 0.08, 0.04)
    S["hurt"] = bp(noise(0.3), 200, 1500) * expdec(int(0.3 * SR), 0.06) + np.sin(2 * np.pi * np.cumsum(np.linspace(240, 120, int(0.3 * SR))) / SR) * expdec(int(0.3 * SR), 0.09)
    # steps
    for k in range(3):
        d = 0.12
        S["step_dirt%d" % k] = lp(noise(d), 900 + k * 200) * expdec(int(d * SR), 0.025) + hp(noise(d), 3000) * expdec(int(d * SR), 0.006) * 0.12
        S["step_hard%d" % k] = bp(noise(d), 600, 4000) * expdec(int(d * SR), 0.012) + np.sin(2 * np.pi * (140 + k * 20) * t_(d)) * expdec(int(d * SR), 0.015) * 0.6
    # interaction
    d = 0.5
    tt = t_(d)
    creak = signal.sawtooth(2 * np.pi * np.cumsum(180 + 120 * np.sin(2 * np.pi * 3 * tt) + 40 * rng.standard_normal(len(tt))) / SR)
    S["door"] = bp(creak, 300, 1800) * env(len(tt), 0.03, 0.2, 0.6, 0.15, 0.1) + lp(noise(d), 300) * np.exp(-((tt - 0.45) ** 2) / 0.0005) * 2
    S["crate"] = bp(creak, 250, 1500) * env(len(tt), 0.02, 0.15, 0.4, 0.1, 0.05) * 0.6 + bp(noise(d), 800, 5000) * expdec(len(tt), 0.08) * 0.4
    S["pickup"] = np.concatenate([np.sin(2 * np.pi * f * t_(0.06)) * env(int(0.06 * SR), 0.002, 0.05, 0.0, 0.01) for f in (660, 990)])
    S["coins"] = sum(np.sin(2 * np.pi * f * t_(0.35)) * expdec(int(0.35 * SR), 0.06) * np.roll(np.ones(int(0.35 * SR)), 0) * (np.arange(int(0.35 * SR)) > int(o * SR))
                     for f, o in ((2600, 0), (3100, 0.05), (2800, 0.11), (3500, 0.16)))
    S["click"] = hp(noise(0.03), 2000) * expdec(int(0.03 * SR), 0.004) + np.sin(2 * np.pi * 1800 * t_(0.03)) * expdec(int(0.03 * SR), 0.005)
    pb = np.concatenate([signal.square(2 * np.pi * f * t_(0.05)) * 0.3 * env(int(0.05 * SR), 0.002, 0.04, 0.2, 0.01) for f in (880, 1320, 1760)])
    S["pipboy"] = pb + hp(noise(len(pb) / SR + 0.01), 4000)[: len(pb)] * 0.05
    S["discover"] = sum(np.sin(2 * np.pi * f * t_(2.2)) * env(int(2.2 * SR), 0.01 + i * 0.12, 1.6, 0.0, 0.4, 0.0) * (0.5 if i else 0.7) for i, f in enumerate((220, 277.2, 329.6, 440)))
    S["levelup"] = np.concatenate([np.sin(2 * np.pi * f * t_(0.13)) * env(int(0.13 * SR), 0.005, 0.1, 0.3, 0.02) + np.sin(4 * np.pi * f * t_(0.13)) * 0.2 * env(int(0.13 * SR), 0.005, 0.1, 0.0, 0.02) for f in (392, 494, 587, 784)])
    S["chop"] = lp(noise(0.25), 1200) * expdec(int(0.25 * SR), 0.03) * 1.4 + np.sin(2 * np.pi * 220 * t_(0.25)) * expdec(int(0.25 * SR), 0.04)
    S["build"] = S["hit_metal"][: int(0.3 * SR)] * 0.5 + lp(noise(0.3), 500) * expdec(int(0.3 * SR), 0.05)
    S["thunder"] = lp(brown(4.0), 180) * env(int(4 * SR), 0.05, 0.6, 0.5, 2.5, 0.6) + lp(noise(4.0), 1200) * expdec(int(4 * SR), 0.15) * 0.4
    S["geiger"] = hp(noise(0.012), 3000) * expdec(int(0.012 * SR), 0.002)
    S["eat"] = sum(bp(noise(0.08), 500, 3000) * expdec(int(0.08 * SR), 0.02) for _ in range(1))
    S["heal"] = np.sin(2 * np.pi * np.cumsum(np.linspace(500, 900, int(0.4 * SR))) / SR) * env(int(0.4 * SR), 0.05, 0.3, 0.0, 0.05) * 0.6 + hp(noise(0.4), 5000) * env(int(0.4 * SR), 0.05, 0.3, 0.0, 0.05) * 0.1
    S["radio_tune"] = bp(noise(0.4), 500, 4000) * (0.5 + 0.5 * np.sin(2 * np.pi * 11 * t_(0.4))) + np.sin(2 * np.pi * np.cumsum(np.linspace(300, 1500, int(0.4 * SR))) / SR) * 0.3
    return S


# ------------------------------------------------------------------ ambient loops
def ambient():
    S = {}
    d = 24.0
    tt = t_(d)
    gust = 0.5 + 0.5 * np.sin(2 * np.pi * tt / 7.0) * np.sin(2 * np.pi * tt / 11.3 + 1.0)
    w = bp(noise(d), 180, 900) * (0.3 + 0.7 * gust) + lp(brown(d), 200) * 0.6
    whistle = bp(noise(d), 1200, 1500) * gust ** 3 * 0.25
    S["amb_wind"] = (w + whistle, True)
    # night: crickets
    c = np.zeros(int(d * SR))
    for k in range(5):
        f = rng.uniform(3800, 5200)
        rate = rng.uniform(14, 22)
        chirp = (np.sin(2 * np.pi * rate * tt + k) > 0.6).astype(float)
        groups = (np.sin(2 * np.pi * tt / rng.uniform(1.2, 2.5) + k * 2) > 0.1).astype(float)
        c += np.sin(2 * np.pi * f * tt) * lp(chirp * groups, 120) * rng.uniform(0.2, 0.5)
    S["amb_night"] = (c + lp(brown(d), 150) * 0.25, True)
    # fire crackle
    d = 8.0
    fire = lp(brown(d), 400) * 0.4
    pops = np.zeros(int(d * SR))
    for k in range(70):
        i = rng.integers(0, len(pops) - 400)
        pops[i:i + 300] += hp(rng.uniform(-1, 1, 300), 1500) * expdec(300, 0.002) * rng.uniform(0.3, 1.0)
    S["amb_fire"] = (fire + pops, True)
    # rain
    d = 16.0
    tt = t_(d)
    S["amb_rain"] = (bp(noise(d), 600, 7000) * 0.6 + lp(brown(d), 300) * 0.3 + bp(noise(d), 2000, 4000) * (0.5 + 0.5 * np.sin(2 * np.pi * tt / 5)) * 0.2, True)
    # town murmur: many soft voice-like formant blobs
    d = 16.0
    tt = t_(d)
    m = np.zeros(len(tt))
    for k in range(14):
        f0 = rng.uniform(110, 220)
        syll = (np.sin(2 * np.pi * rng.uniform(2.5, 4.5) * tt + rng.uniform(0, 6)) > 0.2).astype(float)
        talk = (np.sin(2 * np.pi * tt / rng.uniform(3, 7) + rng.uniform(0, 6)) > 0.0).astype(float)
        v = signal.sawtooth(2 * np.pi * f0 * tt * (1 + 0.05 * np.sin(2 * np.pi * 3 * tt)))
        m += bp(v, 300, 1400) * lp(syll * talk, 30) * rng.uniform(0.3, 1.0)
    S["amb_town"] = (lp(m, 1600) + lp(brown(d), 200) * 0.3, True)
    # interiors: low room hum with drips
    d = 12.0
    hum = lp(brown(d), 120) * 0.6 + np.sin(2 * np.pi * 60 * t_(d)) * 0.05
    for k in range(10):
        i = rng.integers(0, len(hum) - 3000)
        hum[i:i + 2500] += np.sin(2 * np.pi * rng.uniform(900, 1500) * t_(2500 / SR)) * expdec(2500, 0.03) * 0.4
    S["amb_inside"] = (hum, True)
    return S


# ------------------------------------------------------------------ Sable Radio: original tunes
NOTE = {n: i for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def chord_notes(name, octave=4):
    root = name[:2] if len(name) > 1 and name[1] == "#" else name[:1]
    r = NOTE[root] + 12 * (octave + 1)
    q = name[len(root):]
    if q == "m7": iv = [0, 3, 7, 10]
    elif q == "7": iv = [0, 4, 7, 10]
    elif q == "maj7": iv = [0, 4, 7, 11]
    elif q == "6": iv = [0, 4, 7, 9]
    elif q == "m": iv = [0, 3, 7]
    elif q == "dim": iv = [0, 3, 6, 9]
    else: iv = [0, 4, 7]
    return [r + i for i in iv], r


def piano(f, d, vel=1.0):
    n = int(d * SR)
    tt = np.arange(n) / SR
    x = sum(np.sin(2 * np.pi * f * k * tt) / k ** 1.6 for k in range(1, 7))
    return x * expdec(n, 0.25 + 60 / f) * env(n, 0.004, 0.0, 1.0, 0.03, d) * vel


def epiano(f, d, vel=1.0):
    n = int(d * SR)
    tt = np.arange(n) / SR
    mod = np.sin(2 * np.pi * f * 2 * tt) * 1.2 * expdec(n, 0.3)
    return np.sin(2 * np.pi * f * tt + mod) * expdec(n, 0.9) * env(n, 0.003, 0.0, 1.0, 0.05, d) * vel


def bass(f, d, vel=1.0):
    n = int(d * SR)
    tt = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(4 * np.pi * f * tt) + 0.15 * np.sin(6 * np.pi * f * tt)
    return x * expdec(n, 0.35) * env(n, 0.01, 0.0, 1.0, 0.03, d) * vel


def brush(d, vel=1.0):
    n = int(d * SR)
    return bp(noise(d), 2500, 9000) * expdec(n, 0.05) * vel


def kick(d=0.3):
    n = int(d * SR)
    tt = np.arange(n) / SR
    return np.sin(2 * np.pi * np.cumsum(np.linspace(110, 45, n)) / SR) * expdec(n, 0.08)


def radio_fx(x):
    """AM radio: band limited, a touch of saturation, hiss and vinyl crackle."""
    x = bp(x, 110, 5000, 2)
    x = np.tanh(x * 1.4)
    n = len(x)
    crackle = np.zeros(n)
    for k in range(int(n / SR * 2.5)):
        i = rng.integers(0, n - 200)
        crackle[i:i + 120] += hp(rng.uniform(-1, 1, 120), 2500) * expdec(120, 0.001) * rng.uniform(0.03, 0.12)
    hiss = hp(rng.uniform(-1, 1, n), 3000) * 0.006
    return x + crackle + hiss


def song(prog, bpm, bars_per_chord=1, swing=0.62, lead_scale=None, voice="piano", seed=1, reps=3):
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    bar = beat * 4
    total = bar * len(prog) * bars_per_chord * reps + 2.0
    out = np.zeros(int(total * SR) + SR)

    def put(x, t, g=1.0):
        i = int(t * SR)
        j = min(len(out), i + len(x))
        out[i:j] += x[: j - i] * g

    inst = piano if voice == "piano" else epiano
    t = 0.0
    last_lead = None
    for rep in range(reps):
        for ci, ch in enumerate(prog):
            notes, root = chord_notes(ch, 3)
            for b in range(bars_per_chord):
                # comping: chord on beats 2 and 4, swung pickups
                for bt in range(4):
                    tb = t + bt * beat
                    if bt in (1, 3):
                        for nn in notes:
                            put(inst(mtof(nn + 12), beat * 0.9, 0.18), tb + r.uniform(0, 0.01))
                    if bt == 2 and r.random() < 0.4:
                        for nn in notes[1:]:
                            put(inst(mtof(nn + 12), beat * 0.4, 0.12), tb + beat * swing)
                    # walking bass
                    walk = [root, root + 7, root + 4 if "m" not in ch else root + 3, root + 5 + r.integers(-1, 2)][bt]
                    put(bass(mtof(walk - 12), beat * 0.95, 0.55), tb)
                    # brushes + soft kick
                    put(brush(beat * 0.5, 0.1 if bt % 2 else 0.05), tb)
                    put(brush(beat * 0.3, 0.04), tb + beat * swing)
                    if bt == 0: put(kick() * 0.35, tb)
                # lead melody in rep 2 (and part of 3): chord tones and passing notes, swung eighths
                if rep >= 1 and lead_scale is not None:
                    for e in range(8):
                        if r.random() < (0.55 if rep == 1 else 0.35):
                            tt_ = t + (e // 2) * beat + (beat * swing if e % 2 else 0.0)
                            cand = [n + 24 for n in notes] + [lead_scale[r.integers(0, len(lead_scale))] + 72]
                            if last_lead is not None:
                                cand.sort(key=lambda m: abs(m - last_lead) + r.uniform(0, 3))
                            m = cand[0]
                            last_lead = m
                            put(epiano(mtof(m), beat * (0.9 if e % 2 else 0.6), 0.32) if voice == "piano" else piano(mtof(m), beat * 0.8, 0.3), tt_)
                t += bar
    out = out[: int(t * SR) + int(1.5 * SR)]
    out = lp(out, 6000)
    # small room reverb
    ir = noise(1.2) * expdec(int(1.2 * SR), 0.25) * 0.04
    ir[0] = 1.0
    out = signal.fftconvolve(out, ir)[: len(out)]
    return radio_fx(norm(out, 0.8))


def radio():
    S = {}
    maj = [0, 2, 4, 7, 9]
    minp = [0, 3, 5, 7, 10]
    S["radio_1"] = song(["Cmaj7", "Am7", "Dm7", "G7", "Em7", "A7", "Dm7", "G7"], 92, 1, lead_scale=maj, seed=11)
    S["radio_2"] = song(["F6", "Dm7", "Gm7", "C7", "F6", "D7", "Gm7", "C7"], 78, 1, lead_scale=[5, 7, 9, 12, 14], voice="epiano", seed=23)
    S["radio_3"] = song(["Am", "Dm", "E7", "Am", "F", "Dm", "E7", "E7"], 70, 1, lead_scale=[9, 11, 12, 14, 16, 17], seed=37)
    S["radio_4"] = song(["A#maj7", "Gm7", "Cm7", "F7", "Dm7", "G7", "Cm7", "F7"], 104, 1, lead_scale=[10, 12, 14, 17, 19], voice="epiano", seed=41)
    return S


def main():
    want = set(sys.argv[1:])
    allfx = fx()
    for k, v in allfx.items():
        if not want or k in want:
            save(k, v, 0.8 if not k.startswith("gun") else 0.95)
    for k, (v, loop) in ambient().items():
        if not want or k in want:
            save(k, v, 0.7, loop)
    if not want or any(w.startswith("radio_") for w in want):
        for k, v in radio().items():
            if not want or k in want:
                save(k, v, 0.75)


if __name__ == "__main__":
    main()

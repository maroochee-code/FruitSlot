"""maroochee slot 효과음 합성기 (6-F1).

실행: python tools/gen_sounds.py      (표준 라이브러리만 사용, 시드 고정이라 항상 같은 파일이 나온다)
만드는 것: assets/sounds/*.wav (44.1kHz 16bit 모노, 8비트 칩튠 스타일)
  coin / bet / cancel / start / reel_spin(반복) / reel_stop / win_small / win_mid / win_big /
  fever_start / fever_end / pool_get / button / gameover
규칙: 직접 합성한 소리만 쓴다(외부 녹음·원작 소리 없음). 파일마다 GAIN으로 볼륨 균형을 맞춘다.
"""
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "sounds"
SR = 44100
SEED = 20261110
TWO_PI = 2.0 * math.pi

# 음 이름 -> 주파수(Hz). A4 = 440
NOTE_INDEX = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def hz(name):
    """'C5', 'F#4' 같은 음 이름을 주파수로"""
    pitch, octave = name[:-1], int(name[-1])
    midi = 12 * (octave + 1) + NOTE_INDEX[pitch]
    return 440.0 * 2 ** ((midi - 69) / 12)


# 파일별 최종 볼륨(최대값 1.0 기준). 반복음·자주 나는 소리는 작게, 큰 당첨·풀은 크게.
GAIN = {
    "coin": 0.60, "bet": 0.45, "cancel": 0.55, "start": 0.60, "reel_spin": 0.30, "reel_stop": 0.60,
    "win_small": 0.60, "win_mid": 0.70, "win_big": 0.80, "fever_start": 0.75, "fever_end": 0.65,
    "pool_get": 0.85, "button": 0.40, "gameover": 0.60,
}


def osc(kind, phase, duty=0.5, noise_value=0.0):
    """phase: 0~1 주기 안의 위치"""
    if kind == "pulse":
        return 1.0 if phase < duty else -1.0
    if kind == "tri":
        return 4.0 * abs(phase - 0.5) - 1.0
    if kind == "sine":
        return math.sin(TWO_PI * phase)
    if kind == "noise":
        return noise_value
    raise ValueError(kind)


def note(freq, dur, kind="pulse", duty=0.5, vol=1.0, attack=0.003, decay=4.0, freq_end=None, rng=None, noise_hz=8000.0):
    """음 하나. decay가 클수록 빨리 사라진다. freq_end가 있으면 freq에서 freq_end로 미끄러진다."""
    n = int(dur * SR)
    out = []
    phase = 0.0
    hold = 0
    held = 0.0
    fade = min(0.004, dur / 4.0)
    for i in range(n):
        t = i / SR
        frac = i / max(1, n - 1)
        f = freq if freq_end is None else freq + (freq_end - freq) * frac
        if kind == "noise":
            if hold <= 0:
                held = rng.uniform(-1.0, 1.0)
                hold = max(1, int(SR / noise_hz))
            hold -= 1
            s = osc(kind, 0.0, noise_value=held)
        else:
            s = osc(kind, phase, duty)
            phase = (phase + f / SR) % 1.0
        amp = min(1.0, t / attack) if attack > 0 else 1.0
        amp *= math.exp(-decay * frac)
        tail = dur - t
        if tail < fade:
            amp *= tail / fade
        out.append(s * amp * vol)
    return out


def mix(parts, total_dur=None):
    """(시작 시각 초, 샘플 목록) 목록을 겹쳐 더한다"""
    end = max(int(start * SR) + len(samples) for start, samples in parts)
    if total_dur is not None:
        end = max(end, int(total_dur * SR))
    out = [0.0] * end
    for start, samples in parts:
        base = int(start * SR)
        for i, s in enumerate(samples):
            out[base + i] += s
    return out


# ------------------------------------------------------------------ 효과음

def coin():
    a = note(hz("B5"), 0.07, "pulse", 0.25, 0.8, decay=1.5)
    b = note(hz("E6"), 0.22, "pulse", 0.25, 0.8, decay=4.0)
    return mix([(0.0, a), (0.07, b)])


def bet():
    return note(1200.0, 0.035, "pulse", 0.5, 0.8, attack=0.001, decay=5.0)


def cancel():
    return note(hz("A3"), 0.14, "pulse", 0.5, 0.8, decay=3.0, freq_end=hz("E3"))


def start():
    a = note(300.0, 0.18, "tri", vol=0.9, decay=1.0, freq_end=900.0)
    b = note(600.0, 0.18, "pulse", 0.25, 0.4, decay=2.0, freq_end=1500.0)
    return mix([(0.0, a), (0.0, b)])


def reel_spin():
    """이음새 없이 반복되는 낮은 윙윙 소리 (0.5초 한 주기). 정수 주기만 쓰고 노이즈는 양 끝을 크로스페이드한다."""
    dur = 0.5
    n = int(dur * SR)
    xfade = int(0.06 * SR)
    rng = random.Random(SEED + 1)
    raw = [rng.uniform(-1.0, 1.0) for _ in range(n + xfade)]
    low = []
    state = 0.0
    for v in raw:  # 한 극점 로우패스: 거친 소리를 낮은 웅웅으로
        state += 0.08 * (v - state)
        low.append(state)
    noise = low[:n]
    for i in range(xfade):
        w = i / xfade
        noise[i] = low[i] * math.sin(w * math.pi / 2) + low[n + i] * math.cos(w * math.pi / 2)
    peak_noise = max(abs(v) for v in noise) or 1.0
    out = []
    for i in range(n):
        t = i / SR
        lfo = 0.75 + 0.25 * math.sin(TWO_PI * 8.0 * t)  # 0.5초 안에 4번 = 정수 주기
        tone = 0.6 * osc("tri", (90.0 * t) % 1.0) + 0.3 * osc("tri", (136.0 * t) % 1.0)
        out.append((tone + 0.7 * noise[i] / peak_noise) * lfo)
    return out


def reel_stop():
    thump = note(150.0, 0.08, "tri", vol=1.0, attack=0.001, decay=6.0, freq_end=70.0)
    click = note(0.0, 0.04, "noise", vol=0.7, attack=0.0005, decay=7.0, rng=random.Random(SEED + 2), noise_hz=6000.0)
    return mix([(0.0, thump), (0.0, click)])


def arpeggio(names, step, last_hold, kind="pulse", duty=0.25, vol=0.8, decay=3.0, octave_layer=False):
    parts = []
    for i, name in enumerate(names):
        dur = step if i < len(names) - 1 else last_hold
        parts.append((i * step, note(hz(name), dur, kind, duty, vol, decay=decay)))
        if octave_layer:
            up = hz(name) * 2
            parts.append((i * step, note(up, dur, "pulse", 0.125, vol * 0.35, decay=decay)))
    return mix(parts)


def win_small():
    return arpeggio(["C6", "E6", "G6"], 0.06, 0.12)


def win_mid():
    return arpeggio(["C5", "E5", "G5", "C6", "E6"], 0.07, 0.25, octave_layer=True)


def win_big():
    return arpeggio(["C5", "E5", "G5", "C6", "E6", "G6", "C7", "E7"], 0.075, 0.45, octave_layer=True)


def fever_start():
    up = arpeggio(["C5", "E5", "G5", "C6", "E6", "G6", "C7"], 0.055, 0.28, octave_layer=True, decay=2.5)
    bass = note(hz("C3"), 0.55, "tri", vol=0.7, decay=1.5)
    return mix([(0.0, up), (0.0, bass)])


def fever_end():
    a = note(hz("G5"), 0.1, "pulse", 0.25, 0.8, decay=1.0)
    b = note(hz("C6"), 0.28, "pulse", 0.25, 0.8, decay=4.0)
    c = note(hz("C5"), 0.28, "tri", vol=0.6, decay=4.0)
    return mix([(0.0, a), (0.1, b), (0.1, c)])


def pool_get():
    rise1 = arpeggio(["C5", "E5", "G5", "C6", "E6", "G6"], 0.05, 0.1, octave_layer=True, decay=1.5)
    rise2 = arpeggio(["D5", "F#5", "A5", "D6", "F#6", "A6", "D7"], 0.05, 0.5, octave_layer=True, decay=2.5)
    rng = random.Random(SEED + 3)
    parts = [(0.0, rise1), (0.36, rise2)]
    for i in range(8):  # 반짝이는 높은 핑
        freq = rng.choice([hz("E7"), hz("G7"), hz("C8"), hz("A7")])
        parts.append((0.55 + i * 0.075, note(freq, 0.09, "sine", vol=0.35, decay=5.0)))
    bass = note(hz("C3"), 1.15, "tri", vol=0.6, decay=1.2)
    parts.append((0.0, bass))
    return mix(parts)


def button():
    return note(900.0, 0.022, "pulse", 0.5, 0.7, attack=0.001, decay=4.0)


def gameover():
    names = ["G4", "E4", "C4", "G3"]
    parts = []
    for i, name in enumerate(names):
        dur = 0.16 if i < 3 else 0.5
        parts.append((i * 0.16, note(hz(name), dur, "pulse", 0.5, 0.8, decay=2.5, freq_end=hz(name) * 0.97)))
    return mix(parts)


SOUNDS = {
    "coin": coin, "bet": bet, "cancel": cancel, "start": start, "reel_spin": reel_spin, "reel_stop": reel_stop,
    "win_small": win_small, "win_mid": win_mid, "win_big": win_big, "fever_start": fever_start,
    "fever_end": fever_end, "pool_get": pool_get, "button": button, "gameover": gameover,
}


def normalize(samples, gain):
    peak = max(abs(s) for s in samples) or 1.0
    return [s / peak * gain for s in samples]


def write_wav(path, samples):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
        w.writeframes(frames)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in SOUNDS.items():
        samples = normalize(fn(), GAIN[name])
        write_wav(OUT / f"{name}.wav", samples)
        print("%-12s %5.2fs  gain %.2f" % (name, len(samples) / SR, GAIN[name]))


if __name__ == "__main__":
    main()

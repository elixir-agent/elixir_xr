#!/usr/bin/env python3
"""Generate synthesized BGM and Ambient MP3 files for vrex_server."""

import numpy as np
import lameenc
import math

SAMPLE_RATE = 44100
BASE = "/home/piacere/claude/vrex_server/priv/static"

# ── MP3 書き出し ─────────────────────────────────────────────────────────
def write_mp3(path: str, samples_l: np.ndarray, samples_r: np.ndarray):
    enc = lameenc.Encoder()
    enc.set_bit_rate(128)
    enc.set_in_sample_rate(SAMPLE_RATE)
    enc.set_channels(2)
    enc.set_quality(5)

    pcm_l = (np.clip(samples_l, -1.0, 1.0) * 32767).astype(np.int16)
    pcm_r = (np.clip(samples_r, -1.0, 1.0) * 32767).astype(np.int16)
    interleaved = np.empty(len(pcm_l) * 2, dtype=np.int16)
    interleaved[0::2] = pcm_l
    interleaved[1::2] = pcm_r

    mp3 = enc.encode(interleaved.tobytes()) + enc.flush()
    with open(path, "wb") as f:
        f.write(mp3)
    size_kb = len(mp3) / 1024
    print(f"  {path.split('static/')[-1]}  ({size_kb:.0f} KB)")

# ── 基本ユーティリティ ──────────────────────────────────────────────────
def t(duration: float) -> np.ndarray:
    return np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)

def sine(freq: float, arr: np.ndarray, phase: float = 0) -> np.ndarray:
    return np.sin(2 * math.pi * freq * arr + phase)

def envelope(arr: np.ndarray, attack=0.01, decay=0.1, sustain=0.7, release=0.2) -> np.ndarray:
    n = len(arr)
    a = int(SAMPLE_RATE * attack)
    d = int(SAMPLE_RATE * decay)
    r = int(SAMPLE_RATE * release)
    s = n - a - d - r
    env = np.concatenate([
        np.linspace(0, 1, a),
        np.linspace(1, sustain, d),
        np.full(max(s, 0), sustain),
        np.linspace(sustain, 0, r),
    ])
    return env[:n]

def reverb(sig: np.ndarray, delay_ms=80, decay=0.4) -> np.ndarray:
    delay_samples = int(SAMPLE_RATE * delay_ms / 1000)
    out = sig.copy()
    out[delay_samples:] += sig[:-delay_samples] * decay
    out[delay_samples*2:] += sig[:-delay_samples*2] * (decay ** 2)
    return out

def chorus(sig: np.ndarray, depth=0.003, rate=0.5) -> np.ndarray:
    n = len(sig)
    tt = np.arange(n) / SAMPLE_RATE
    delay = (depth * np.sin(2 * math.pi * rate * tt) + depth) * SAMPLE_RATE
    idx = np.arange(n) - delay.astype(int)
    idx = np.clip(idx, 0, n - 1)
    return (sig + sig[idx] * 0.5) / 1.5

def low_pass(sig: np.ndarray, cutoff_ratio=0.3) -> np.ndarray:
    """Simple FIR low-pass using convolution."""
    N = 31
    h = np.sinc(2 * cutoff_ratio * (np.arange(N) - N // 2))
    h *= np.hanning(N)
    h /= h.sum()
    return np.convolve(sig, h, mode='same')

def noise(n: int, color='white') -> np.ndarray:
    w = np.random.randn(n)
    if color == 'pink':
        # Pink noise via 1/f filtering
        f = np.fft.rfftfreq(n)
        f[0] = 1e-10
        w = np.fft.irfft(np.fft.rfft(w) / np.sqrt(f))
    return w / (np.max(np.abs(w)) + 1e-9)

# ── 音符定義 ────────────────────────────────────────────────────────────
NOTE = {
    'C3':130.81,'D3':146.83,'E3':164.81,'F3':174.61,'G3':196.00,'A3':220.00,'B3':246.94,
    'C4':261.63,'D4':293.66,'E4':329.63,'F4':349.23,'G4':392.00,'A4':440.00,'B4':493.88,
    'C5':523.25,'D5':587.33,'E5':659.25,'F5':698.46,'G5':783.99,'A5':880.00,'B5':987.77,
    'Cs4':277.18,'Ds4':311.13,'Fs4':369.99,'Gs4':415.30,'As4':466.16,
    'Cs5':554.37,'Ds5':622.25,'Fs5':739.99,'Gs5':830.61,'As5':932.33,
}

def note_seq(melody: list, bpm: float, wave='sine') -> np.ndarray:
    """melody = [(note_name_or_None, beats), ...]"""
    beat = 60.0 / bpm
    out = []
    for (pitch, beats) in melody:
        dur = beat * beats
        tt = t(dur)
        if pitch is None:
            out.append(np.zeros(len(tt)))
        else:
            freq = NOTE[pitch]
            if wave == 'sine':
                sig = sine(freq, tt) * 0.6 + sine(freq * 2, tt) * 0.2
            elif wave == 'organ':
                sig = (sine(freq, tt) + sine(freq*2, tt)*0.5 + sine(freq*3, tt)*0.25) / 1.75
            elif wave == 'bell':
                sig = (sine(freq, tt) + sine(freq*4.07, tt)*0.3) / 1.3
            else:
                sig = sine(freq, tt)
            sig *= envelope(tt, attack=0.02, release=min(0.15, dur*0.3))
            out.append(sig)
    return np.concatenate(out)

# ══════════════════════════════════════════════════════════════════════
# BGM トラック
# ══════════════════════════════════════════════════════════════════════

def bgm_lobby(duration=30):
    """明るいポップ感のあるロビーBGM (C major)"""
    bpm = 120
    melody = [
        ('E4',1),('G4',1),('C5',2),('B4',1),('A4',1),('G4',2),
        ('E4',1),('F4',1),('G4',1),('A4',1),('G4',2),('E4',2),
        ('D4',1),('F4',1),('A4',2),('G4',1),('F4',1),('E4',2),
        ('C4',1),('E4',1),('G4',2),('E4',1),('D4',1),('C4',2),
    ]
    bass = [
        ('C3',2),('G3',2),('A3',2),('F3',2),
        ('C3',2),('G3',2),('F3',2),('G3',2),
    ]
    mel = note_seq(melody * 2, bpm, 'sine')
    bas = note_seq(bass * 4, bpm, 'organ') * 0.5
    n = int(SAMPLE_RATE * duration)
    def tile(a):
        return np.tile(a, math.ceil(n / len(a)))[:n]
    sig = tile(mel) * 0.6 + tile(bas) * 0.4
    sig = reverb(sig, 60, 0.3)
    return sig, chorus(sig, 0.002, 0.8)

def bgm_zen_koto(duration=30):
    """琴風の日本的なBGM (pentatonic D)"""
    bpm = 72
    melody = [
        ('D4',2),('F4',1),(None,1),('A4',2),('D5',1),(None,1),
        ('C5',1),('A4',1),(None,1),('F4',1),('D4',2),(None,2),
        ('A4',2),('C5',1),(None,1),('D5',3),(None,1),
        ('C5',1),('A4',1),('F4',1),(None,1),('D4',4),
    ]
    harmony = [
        ('D3',4),('A3',4),('D3',4),('A3',4),
        ('D3',4),('A3',4),('D3',4),('A3',4),
    ]
    mel = note_seq(melody * 2, bpm, 'bell')
    har = note_seq(harmony * 2, bpm, 'organ') * 0.3
    n = int(SAMPLE_RATE * duration)
    def tile(a): return np.tile(a, math.ceil(n / len(a)))[:n]
    mel_t = tile(mel)
    har_t = tile(har)
    sig = reverb(mel_t * 0.7 + har_t, 120, 0.5)
    tt = np.arange(n) / SAMPLE_RATE
    tremolo = 1.0 + 0.05 * np.sin(2 * math.pi * 5 * tt)
    return sig * tremolo, sig * tremolo * 0.95

def bgm_arena_battle(duration=30):
    """激しいアリーナバトルBGM (E minor)"""
    bpm = 160
    melody = [
        ('E4',1),('E4',0.5),('G4',0.5),('B4',1),('E5',1),
        ('D5',1),('B4',1),('G4',1),('A4',1),
        ('E4',1),('Fs4',0.5),('G4',0.5),('A4',1),('B4',2),
        ('G4',1),('Fs4',1),('E4',4),
    ]
    bass_riff = [
        ('E3',0.5),(None,0.5),('E3',0.5),(None,0.5),
        ('G3',0.5),(None,0.5),('A3',1),
        ('E3',0.5),(None,0.5),('E3',0.5),(None,0.5),
        ('D3',0.5),(None,0.5),('E3',1),
    ]
    mel = note_seq(melody * 3, bpm, 'organ')
    bas = note_seq(bass_riff * 6, bpm, 'organ')
    # ドラム風パーカッション（低音バンド・ノイズ）
    n = int(SAMPLE_RATE * duration)
    beat_samples = int(SAMPLE_RATE * 60 / bpm)
    kick = np.zeros(n)
    for i in range(0, n, beat_samples * 2):
        if i + beat_samples // 4 <= n:
            tt_k = t(0.1)
            k = sine(80, tt_k) * np.exp(-tt_k * 40) * 0.8
            kick[i:i+len(k)] += k[:n-i]
    def tile(a): return np.tile(a, math.ceil(n / len(a)))[:n]
    sig = tile(mel) * 0.5 + tile(bas) * 0.4 + kick * 0.3
    sig = reverb(sig, 40, 0.2)
    return sig, sig * 0.9

def bgm_space_ambient(duration=30):
    """宇宙の神秘的なアンビエントBGM"""
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    # ゆっくりしたパッド
    pad = (sine(130.81, tt) * 0.3 +
           sine(196.00, tt) * 0.2 +
           sine(261.63, tt) * 0.15 +
           sine(329.63, tt) * 0.1)
    # ゆったりしたLFO
    lfo = 0.5 + 0.5 * np.sin(2 * math.pi * 0.1 * tt)
    lfo2 = 0.5 + 0.5 * np.sin(2 * math.pi * 0.07 * tt + 1.2)
    # 高音のきらめき
    shimmer = sine(1046.50, tt) * 0.05 * np.sin(2 * math.pi * 0.3 * tt) ** 2
    sig_l = low_pass(pad * lfo + shimmer, 0.2) * 0.7
    sig_r = low_pass(pad * lfo2 + shimmer, 0.2) * 0.7
    # フェードイン/アウト
    fade = np.ones(n)
    fi = int(SAMPLE_RATE * 2)
    fade[:fi] = np.linspace(0, 1, fi)
    fade[-fi:] = np.linspace(1, 0, fi)
    return sig_l * fade, sig_r * fade

def bgm_underwater_mystery(duration=30):
    """海底遺跡の神秘的BGM (F minor)"""
    bpm = 60
    melody = [
        ('F4',3),(None,1),('C5',2),('As4',2),
        ('Gs4',3),(None,1),('F4',4),
        ('Ds4',2),('F4',2),('Gs4',3),(None,1),
        ('As4',2),('C5',2),('F4',4),
    ]
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    mel = note_seq(melody * 3, bpm, 'bell')
    # 水のゆらぎ
    wave_lfo = 0.85 + 0.15 * np.sin(2 * math.pi * 0.2 * tt)
    def tile(a): return np.tile(a, math.ceil(n / len(a)))[:n]
    mel_t = tile(mel)
    pad = low_pass(sine(174.61, tt) * 0.2 + sine(261.63, tt) * 0.15, 0.15)
    sig = reverb(mel_t * 0.7 + pad, 200, 0.6) * wave_lfo
    return sig, sig * 0.85

def bgm_ninja_drums(duration=30):
    """忍者の里の和太鼓風BGM (D minor pentatonic)"""
    bpm = 140
    melody = [
        ('D4',1),('F4',1),('G4',2),('A4',1),(None,1),('D5',2),
        ('C5',1),('A4',1),('G4',2),('F4',1),(None,1),('D4',2),
        ('A4',1),('G4',1),('F4',1),('D4',1),('A3',2),(None,2),
        ('D4',1),('F4',1),('G4',1),('A4',1),('D5',4),
    ]
    # 太鼓風キック
    n = int(SAMPLE_RATE * duration)
    beat = int(SAMPLE_RATE * 60 / bpm)
    drum = np.zeros(n)
    pattern = [1,0,1,1, 0,1,1,0, 1,0,1,1, 0,1,0,1]
    for i, hit in enumerate(pattern * 100):
        pos = i * beat // 2
        if pos >= n: break
        if hit:
            tt_d = np.linspace(0, 0.08, int(SAMPLE_RATE * 0.08))
            d = (sine(120, tt_d) + sine(80, tt_d) * 0.5) * np.exp(-tt_d * 50) * 0.7
            end = min(pos + len(d), n)
            drum[pos:end] += d[:end-pos]
    mel = note_seq(melody * 2, bpm, 'organ')
    def tile(a): return np.tile(a, math.ceil(n / len(a)))[:n]
    sig = reverb(tile(mel) * 0.55 + drum * 0.45, 50, 0.25)
    return sig, sig

def bgm_desert_wind(duration=30):
    """砂漠の神秘的なアラビアンBGM (D Hijaz scale)"""
    bpm = 80
    # ヒジャーズ音階: D E♭ F# G A B♭ C
    melody = [
        ('D4',2),('Ds4',1),('Fs4',1),('G4',2),('A4',2),
        ('G4',1),('Fs4',1),('Ds4',1),(None,1),('D4',2),
        ('A4',2),('As4',1),('A4',1),('G4',2),('Fs4',2),
        ('Ds4',1),('E4',1),('D4',4),(None,2),
    ]
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    mel = note_seq(melody * 2, bpm, 'sine')
    # 砂漠の風 (フィルタードノイズ)
    wind = low_pass(noise(n, 'pink') * 0.15, 0.05)
    def tile(a): return np.tile(a, math.ceil(n / len(a)))[:n]
    base_pad = sine(73.42, tt) * 0.15 + sine(110, tt) * 0.1
    sig = reverb(tile(mel) * 0.65 + wind + base_pad, 150, 0.45)
    return sig, chorus(sig, 0.003, 0.4)

def bgm_mountain_breeze(duration=30):
    """雪山の清々しいBGM (G major)"""
    bpm = 88
    melody = [
        ('G4',2),(None,1),('A4',1),('B4',2),('D5',2),
        ('C5',1),('B4',1),('A4',2),(None,2),
        ('B4',2),(None,1),('C5',1),('D5',3),(None,1),
        ('E5',1),('D5',1),('C5',1),('B4',1),('G4',4),
    ]
    harm = [
        ('G3',4),('D4',4),('G3',4),('D4',4),
        ('G3',4),('D4',4),('G3',4),('D4',4),
    ]
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    mel = note_seq(melody * 2, bpm, 'bell')
    har = note_seq(harm * 2, bpm, 'organ') * 0.3
    def tile(a): return np.tile(a, math.ceil(n / len(a)))[:n]
    # 風のさわやかさ
    breeze = low_pass(noise(n, 'pink') * 0.08, 0.1)
    sig = reverb(tile(mel) * 0.7 + tile(har) + breeze, 100, 0.4)
    return sig, chorus(sig, 0.002, 0.6)

def bgm_fantasy_epic(duration=30):
    """ファンタジー城の壮大なオーケストラ風BGM (A minor)"""
    bpm = 100
    melody = [
        ('A4',2),('C5',1),('E5',1),('A5',2),(None,2),
        ('G5',1),('E5',1),('C5',1),('A4',1),('B4',2),(None,2),
        ('E5',2),('Fs5',1),('G5',1),('A5',2),(None,2),
        ('E5',1),('D5',1),('C5',1),('B4',1),('A4',4),
    ]
    bass = [
        ('A3',2),('E3',2),('C3',2),('G3',2),
        ('A3',2),('E3',2),('D3',2),('E3',2),
    ]
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    mel = note_seq(melody * 2, bpm, 'organ')
    bas = note_seq(bass * 4, bpm, 'organ') * 0.5
    # ストリングス風パッド
    strings = (sine(220.00, tt) * 0.15 + sine(329.63, tt) * 0.1 +
               sine(440.00, tt) * 0.08) * (0.8 + 0.2 * np.sin(2*math.pi*5*tt))
    def tile(a): return np.tile(a, math.ceil(n / len(a)))[:n]
    sig = reverb(tile(mel)*0.5 + tile(bas)*0.3 + strings, 80, 0.35)
    return sig, chorus(sig, 0.003, 0.7)


# ══════════════════════════════════════════════════════════════════════
# Ambient トラック
# ══════════════════════════════════════════════════════════════════════

def ambient_crowd(duration=30):
    """ロビーの賑やかな人声環境音"""
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    base = noise(n, 'pink') * 0.4
    # 複数の「声」帯域をシミュレート
    voice_band = low_pass(base, 0.35)
    chatter = voice_band * (0.6 + 0.4 * noise(n, 'pink') * 0.5)
    # ランダムな盛り上がり
    swell = 0.7 + 0.3 * np.sin(2*math.pi*0.15*tt) * np.sin(2*math.pi*0.07*tt)
    sig = low_pass(chatter * swell, 0.4)
    sig /= np.max(np.abs(sig)) + 1e-9
    sig *= 0.5
    return sig, sig * 0.95

def ambient_birds_water(duration=30):
    """日本庭園の鳥と水の音"""
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    # 水のせせらぎ (フィルタードノイズ)
    water = low_pass(noise(n, 'pink') * 0.3, 0.25)
    water_l = low_pass(noise(n, 'pink') * 0.3, 0.3)
    # 鳥のさえずり（高周波サイン波バースト）
    birds = np.zeros(n)
    np.random.seed(7)
    for _ in range(15):
        pos = np.random.randint(0, n - SAMPLE_RATE)
        dur = np.random.uniform(0.05, 0.2)
        freq = np.random.choice([1200, 1600, 2000, 2400, 1800])
        tt_b = np.linspace(0, dur, int(SAMPLE_RATE * dur))
        chirp = sine(freq, tt_b) * np.exp(-tt_b * 10) * 0.25
        end = min(pos + len(chirp), n)
        birds[pos:end] += chirp[:end-pos]
    sig_l = water + birds * 0.7
    sig_r = water_l + birds * 0.8
    return sig_l * 0.7, sig_r * 0.7

def ambient_crowd_cheer(duration=30):
    """アリーナの歓声"""
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    base = noise(n, 'pink') * 0.5
    # 波のような盛り上がり
    wave1 = 0.5 + 0.5 * np.sin(2*math.pi*0.08*tt)
    wave2 = 0.3 + 0.7 * (np.sin(2*math.pi*0.13*tt) ** 2)
    cheer = low_pass(base * wave1 * wave2, 0.45) * 0.6
    # 低音ドラム
    drum_env = np.zeros(n)
    beat = int(SAMPLE_RATE * 60 / 120)
    for i in range(0, n - beat//4, beat):
        end = min(i + beat//4, n)
        drum_env[i:end] = np.linspace(0.4, 0, end-i)
    kick = sine(80, tt) * drum_env * 0.3
    sig = cheer + kick
    return sig, sig * 0.9

def ambient_space_hum(duration=30):
    """宇宙ステーションの機械音ハム"""
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    # 機械のハム音 (60Hz + 倍音)
    hum = (sine(60, tt) * 0.3 +
           sine(120, tt) * 0.15 +
           sine(180, tt) * 0.08 +
           sine(240, tt) * 0.04)
    # 高周波ホワイトノイズ成分
    hiss = low_pass(noise(n) * 0.06, 0.15)
    # ゆっくりしたうなり
    beat_freq = 0.5 + 0.5 * np.sin(2*math.pi*0.05*tt)
    sig_l = low_pass(hum * beat_freq + hiss, 0.3)
    sig_r = low_pass(hum * (1-beat_freq*0.1) + hiss, 0.3)
    return sig_l * 0.6, sig_r * 0.6

def ambient_ocean_bubbles(duration=30):
    """海底の泡と水流"""
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    # 深海の低音うねり
    deep = low_pass(noise(n, 'pink') * 0.3, 0.08)
    current = deep * (0.7 + 0.3 * np.sin(2*math.pi*0.1*tt))
    # 泡のぷくぷく
    bubbles = np.zeros(n)
    np.random.seed(3)
    for _ in range(40):
        pos = np.random.randint(0, n - 2000)
        f = np.random.uniform(300, 800)
        dur = np.random.uniform(0.02, 0.06)
        tt_b = np.linspace(0, dur, int(SAMPLE_RATE * dur))
        b = sine(f, tt_b) * np.exp(-tt_b * 30) * 0.15
        end = min(pos + len(b), n)
        bubbles[pos:end] += b[:end-pos]
    sig_l = current + bubbles
    sig_r = low_pass(noise(n, 'pink'), 0.08) * 0.25 + bubbles * 0.9
    return sig_l * 0.7, sig_r * 0.7

def ambient_forest_night(duration=30):
    """忍者の里・夜の森"""
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    # 葉のそよぎ
    rustle = low_pass(noise(n, 'pink') * 0.2, 0.2)
    wind_mod = 0.5 + 0.5 * np.sin(2*math.pi*0.06*tt)
    # 虫の声 (連続高音)
    crickets_bg = sine(2200, tt) * 0.04 * (0.8 + 0.2*np.sin(2*math.pi*8*tt))
    # フクロウ風の低音
    owl = np.zeros(n)
    for pos in [int(n*0.15), int(n*0.45), int(n*0.75)]:
        tt_o = np.linspace(0, 0.4, int(SAMPLE_RATE*0.4))
        o = (sine(300, tt_o) + sine(350, tt_o)*0.5) * np.exp(-tt_o*8) * 0.2
        end = min(pos+len(o), n)
        owl[pos:end] += o[:end-pos]
    sig_l = low_pass(rustle * wind_mod, 0.3) + crickets_bg + owl
    sig_r = low_pass(noise(n,'pink') * 0.18 * wind_mod, 0.25) + crickets_bg + owl
    return sig_l * 0.8, sig_r * 0.8

def ambient_crickets(duration=30):
    """砂漠のオアシス・虫の声と夜風"""
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    # コオロギの声（複数周波数）
    c1 = sine(3200, tt) * 0.08 * (0.5+0.5*np.sin(2*math.pi*7.3*tt))
    c2 = sine(2800, tt) * 0.07 * (0.5+0.5*np.sin(2*math.pi*6.8*tt+0.5))
    c3 = sine(3600, tt) * 0.05 * (0.5+0.5*np.sin(2*math.pi*8.1*tt+1.2))
    # 夜風
    wind = low_pass(noise(n,'pink') * 0.12, 0.1) * (0.6+0.4*np.sin(2*math.pi*0.04*tt))
    sig_l = c1 + c2 + wind
    sig_r = c2 + c3 + low_pass(noise(n,'pink')*0.1, 0.1)
    return sig_l * 0.85, sig_r * 0.85

def ambient_wind_howl(duration=30):
    """雪山の風の音"""
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    # 風の咆哮（フィルタードノイズ＋ピッチ変動）
    base = noise(n, 'pink')
    gust1 = 0.4 + 0.6 * (np.sin(2*math.pi*0.08*tt) ** 2)
    gust2 = 0.3 + 0.7 * (np.sin(2*math.pi*0.11*tt + 0.8) ** 2)
    howl_l = low_pass(base * gust1, 0.15) * 0.6
    howl_r = low_pass(noise(n,'pink') * gust2, 0.18) * 0.6
    # 高音の口笛風
    whistle = sine(800, tt) * 0.05 * gust1 * low_pass(noise(n),0.05)
    sig_l = howl_l + whistle
    sig_r = howl_r + whistle * 0.8
    return sig_l, sig_r

def ambient_castle_ambience(duration=30):
    """ファンタジー城の荘厳な雰囲気"""
    n = int(SAMPLE_RATE * duration)
    tt = np.arange(n) / SAMPLE_RATE
    # 石造りの反響 (深いリバーブ感)
    stone_hum = (sine(55, tt)*0.1 + sine(110, tt)*0.06 + sine(165, tt)*0.03)
    stone_hum *= (0.8 + 0.2 * np.sin(2*math.pi*0.05*tt))
    # 遠くの火のはぜる音
    crackle = low_pass(noise(n)*0.05, 0.1) * (0.5 + 0.5*noise(n,'pink')**2)
    # 鐘の余韻風
    bell_freq = [523.25, 659.25, 783.99]
    bells = np.zeros(n)
    for i, pos in enumerate([int(n*0.0), int(n*0.33), int(n*0.66)]):
        tt_b = np.linspace(0, 3.0, int(SAMPLE_RATE*3.0))
        b = sine(bell_freq[i % 3], tt_b) * np.exp(-tt_b * 1.5) * 0.15
        end = min(pos+len(b), n)
        bells[pos:end] += b[:end-pos]
    sig_l = reverb(stone_hum + crackle + bells, 300, 0.6)
    sig_r = reverb(stone_hum * 0.9 + crackle + bells, 280, 0.55)
    return sig_l * 0.7, sig_r * 0.7


# ══════════════════════════════════════════════════════════════════════
print("=== BGM (MP3) ===")
bgm_tracks = [
    ("lobby_bgm",           bgm_lobby),
    ("zen_koto",            bgm_zen_koto),
    ("arena_battle",        bgm_arena_battle),
    ("space_ambient",       bgm_space_ambient),
    ("underwater_mystery",  bgm_underwater_mystery),
    ("ninja_drums",         bgm_ninja_drums),
    ("desert_wind",         bgm_desert_wind),
    ("mountain_breeze",     bgm_mountain_breeze),
    ("fantasy_epic",        bgm_fantasy_epic),
]
for name, fn in bgm_tracks:
    l, r = fn(duration=30)
    write_mp3(f"{BASE}/music/{name}.mp3", l, r)

print("\n=== Ambient (MP3) ===")
ambient_tracks = [
    ("crowd",            ambient_crowd),
    ("birds_water",      ambient_birds_water),
    ("crowd_cheer",      ambient_crowd_cheer),
    ("space_hum",        ambient_space_hum),
    ("ocean_bubbles",    ambient_ocean_bubbles),
    ("forest_night",     ambient_forest_night),
    ("crickets",         ambient_crickets),
    ("wind_howl",        ambient_wind_howl),
    ("castle_ambience",  ambient_castle_ambience),
]
for name, fn in ambient_tracks:
    l, r = fn(duration=30)
    write_mp3(f"{BASE}/ambient/{name}.mp3", l, r)

print("\nDone!")

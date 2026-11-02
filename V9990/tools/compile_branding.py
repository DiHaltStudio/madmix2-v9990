"""DiHalt fanfare compiler, inherited from Spy vs Spy2's existing opening.
Keeps exactly its selected421 frames plus50 frames of silent logo hold.
"""
from pathlib import Path
FANFARE=Path(__file__).resolve().parents[1]/'assets/branding/dihalt_fanfare.vgm'
def fanfare_frames(path=FANFARE):
    """VGM (AY-3-8910, waits of 1/50 s) -> list of frames, each a list of (reg, value)."""
    import struct
    d = path.read_bytes()
    if d[:4] != b'Vgm ':
        raise ValueError(f'{path}: not a VGM file')
    i = 0x34 + struct.unpack_from('<I', d, 0x34)[0]
    frames, samples = [[]], 0
    while i < len(d):
        c = d[i]
        if c == 0xa0:                               # AY write
            if d[i + 1] > 13:
                raise ValueError(f'{path}: AY register {d[i + 1]}')
            frames[-1].append((d[i + 1], d[i + 2]))
            i += 3
            continue
        if c == 0x61:
            n = struct.unpack_from('<H', d, i + 1)[0]; i += 3
        elif c == 0x62:
            n = 735; i += 1
        elif c == 0x63:
            n = 882; i += 1
        elif 0x70 <= c <= 0x7f:
            n = c - 0x6f; i += 1
        elif c == 0x66:
            break
        else:
            raise ValueError(f'{path}: VGM command {c:02X}h at {i:X}h')
        before = samples // 882                     # 882 samples = one 50 Hz frame
        samples += n
        frames += [[] for _ in range(samples // 882 - before)]
    return frames


# Frames of the VGM that play, as [start, end) ranges. The user's VGM ends with
# the start of the next repetition (frame 486: the noise sweep again), and its
# final echo repeats the A-channel motif every 24 frames eight times: two of
# them (384..431) are left out (user, 2026-10-28). It ends with the silence of
# frame 468.
FANFARE_KEEP = ((0, 384), (432, 469))


def fanfare_stream(path=FANFARE, keep=FANFARE_KEEP):
    """The kept frames in the music stream format of the game (doc/SOUND.md):
    00-0D reg, value; 80h+n wait n frames; FFh end. At each cut the registers
    jump to the state the VGM had there, so no note hangs. Returns (stream, frames)."""
    frames = fanfare_frames(path)
    state, out, played = {}, bytearray(), 0
    pending = 0
    def flush():
        nonlocal pending
        while pending:
            n = min(pending, 127)
            out.append(0x80 + n)
            pending -= n
    for start, end in keep:
        full = {}
        for w in frames[:start]:
            full.update(dict(w))
        first = [(r, v) for r, v in sorted(full.items()) if state.get(r) != v and r != 13]
        for f in range(start, end):
            writes = (first if f == start else []) + frames[f]
            if writes:
                flush()
                for r, v in writes:
                    out += bytes((r, v))
                    state[r] = v
            pending += 1
            played += 1
    flush()
    out.append(0xff)
    return bytes(out), played

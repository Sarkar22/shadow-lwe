#!/usr/bin/env python3
"""
Shadow-LWE feasibility study (pure Python, no RTL).

Answers three go/no-go questions before any Verilog:
  Q1 COMPRESSION  - does seed-compression really shrink the ciphertext ~100x?
  Q2 FEASIBILITY  - can an on-chip PRF expand the N-word mask fast enough to hide
                    behind the inference window, and is the fit a REAL frontier
                    (needs parallelism at short shadows, trivial at long ones)?
                    A boring "always fits" or "never fits" would make the paper thin.
  Q3 HOMOMORPHISM - does summing K encrypted readings decrypt to the sum of the
                    plaintexts (the untrusted-aggregator story), and how deep (K)
                    before LWE noise breaks it?

Real params from the LATTICE RTL: N=630, W=32 (q=2^32), consume LANES words/cycle.
"""
import numpy as np

N, W = 630, 32                      # LWE dimension, torus word width (q = 2^W)
Q = 1 << W
MASK_BITS = N * W                   # 20160 bits of mask to generate per ciphertext
SEED_BITS = 128

# ---------- Q1: ciphertext compression ----------
def compression():
    uncompressed_B = (N + 1) * W / 8            # (a[0..N-1], b)
    compressed_B   = (SEED_BITS + W) / 8        # (seed, b)
    print("=== Q1 COMPRESSION ===")
    print(f"  uncompressed CT = {uncompressed_B:.0f} B  (630 a-words + b)")
    print(f"  seed-compressed = {compressed_B:.0f} B  (128-b seed + b)")
    print(f"  ratio = {uncompressed_B/compressed_B:.1f}x  (KNOWN crypto trick - cite, don't claim)")
    return uncompressed_B / compressed_B

# ---------- Q2: PRF expansion vs inference shadow ----------
# PRF models: bits produced per permutation/block, and rounds per call.
PRFS = {
    "Ascon-XOF  (r=64, 12 rnd)":  dict(bits=64,  rounds=12),
    "Ascon-XOFa (r=64,  8 rnd)":  dict(bits=64,  rounds=8),
    "SIMON128-CTR (128 b, 68 rnd)": dict(bits=128, rounds=68),
}
def t_gen(prf, cores, rounds_per_cycle):
    """cycles to generate the whole mask: parallel cores, u rounds/cycle each."""
    calls = -(-MASK_BITS // prf["bits"])            # ceil
    calls_per_core = -(-calls // cores)
    cyc_per_call = -(-prf["rounds"] // rounds_per_cycle)
    return calls_per_core * cyc_per_call + 2        # +2 init/absorb

def t_mac(lanes):
    return -(-N // lanes) + 4                        # ceil(N/LANES) + handshake

def feasibility():
    print("\n=== Q2 FEASIBILITY (mask gen must finish within the inference shadow) ===")
    print(f"  mask = {MASK_BITS} bits; MAC consumes N/LANES cyc "
          f"(LANES=8 -> {t_mac(8)} cyc, LANES=16 -> {t_mac(16)} cyc)")
    shadows = [111, 256, 512, 1024, 2048]      # tiny MLP ... small CNN layer
    # candidate hardware points: (cores, rounds/cycle) -> parallelism cost proxy = cores*u
    configs = [(1, 1), (1, 2), (1, 12), (2, 12), (4, 12), (8, 12)]
    for name, prf in PRFS.items():
        print(f"\n  {name}: gen cycles by (cores x rounds/cyc)")
        row = "    " + "  ".join(f"{c}x{u:<2}" for c, u in configs)
        print(row)
        print("    " + "  ".join(f"{t_gen(prf,c,u):<4}" for c, u in configs) + "   (cycles)")
        # smallest-cost config that hides, per shadow
        for T in shadows:
            best = None
            for c, u in configs:
                if t_gen(prf, c, u) <= T:
                    cost = c * u
                    if best is None or cost < best[0]:
                        best = (cost, c, u, t_gen(prf, c, u))
            verdict = (f"fits with {best[1]}core x{best[2]}rnd/cyc "
                       f"({best[3]} cyc, cost~{best[0]})" if best else "DOES NOT FIT (any cfg)")
            print(f"      shadow {T:>4} cyc -> {verdict}")

# ---------- Q3: additive homomorphism + noise-limited aggregation depth ----------
def homomorphism(P=16, sigma=1<<20, trials=2000):
    """P-symbol torus message; noise stddev sigma (torus32 units). K-way sum."""
    rng = np.random.default_rng(7)
    Delta = Q // P
    sk = rng.integers(0, 2, N, dtype=np.int64)
    def enc(m):
        a = rng.integers(0, Q, N, dtype=np.int64)
        e = int(round(rng.normal(0, sigma)))
        b = (Delta * m + e + int((a * sk).sum())) % Q
        return a, b
    def dec_sum(cts):
        a_s = np.zeros(N, dtype=np.int64); b_s = 0
        for a, b in cts:
            a_s = (a_s + a) % Q; b_s = (b_s + b) % Q
        phase = (b_s - int((a_s * sk).sum())) % Q
        return int(round(phase / Delta)) % P
    print("\n=== Q3 HOMOMORPHISM (aggregate K encrypted readings without a key) ===")
    print(f"  P={P} symbols, noise sigma=2^{int(np.log2(sigma))}, Delta=2^{int(np.log2(Delta))}")
    for K in (2, 4, 8, 16, 32, 64):
        ok = 0
        for _ in range(trials):
            ms = rng.integers(0, P, K)
            # only meaningful when the true sum stays in range (mod P models wraparound)
            cts = [enc(int(m)) for m in ms]
            if dec_sum(cts) == int(ms.sum()) % P:
                ok += 1
        tag = "OK" if ok == trials else ("noise-limited" if ok > trials*0.5 else "BROKEN")
        print(f"  K={K:>3}: {ok}/{trials} decrypt to the plaintext sum   [{tag}]")

if __name__ == "__main__":
    r = compression()
    feasibility()
    homomorphism()
    print("\n--- verdict inputs above; see interpretation in chat ---")

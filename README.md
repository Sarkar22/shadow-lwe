# Seed-Compressed LWE Encryptor with On-Chip Mask Expansion

Learning-with-errors encryption is post-quantum and additively homomorphic, but its ciphertext is dominated by a random mask vector. This encryptor expands that mask on chip from a public 128-bit seed using **Ascon-XOF128**, so only the seed and the body are transmitted: 2524 bytes become 20.

This is the artifact for a paper submitted to **IEEE CCECE 2027** (under review). Every
number below is reproduced by the scripts in this repository.

## Results

- **126×** smaller ciphertext for one encrypted bit (2524 B → 20 B)
- Ascon-XOF128 core matches the **official NIST known-answer tests**, at every one of the 12 rounds-per-cycle settings (48/48 squeezed words exact)
- Complete encryptor 6/6 bit-exact end-to-end across the whole knob grid
- Latency is generator-bound: quadrupling the accumulate lanes costs 12% more logic and changes latency by 0.3%, so lane parallelism is wasted area
- Throughput saturates then declines as the generator grows; recommended point is 3100 LUT, **0 DSP / 0 BRAM**, 292 MHz

## Reproducing

```bash
bash sim/run_sim.sh   # NIST KATs, then RTL at every rounds-per-cycle setting
```
```bash
python3 model/feasibility.py   # compression and rate-matching analysis
```
```bash
python3 model/analyze.py   # tables and figures from the sweep
```

```bash
OPENLANE_DIR=/path/to/OpenLane DESIGN=shadow_lwe_top bash asic/run_asic.sh   # sky130 RTL-to-GDSII
```

The `asic/` directory holds the OpenLane configuration for each
signed-off configuration; the flow itself is third-party (see Requirements).

## Requirements

Third-party tools, not included here. Any recent version should work; these are what the
reported numbers were produced with.

| tool | used | purpose |
|---|---|---|
| Icarus Verilog | 12.0 | simulation (`iverilog -g2012`) |
| Python 3 | 3.12 + numpy | golden models and analysis |
| AMD Vivado | 2024.2 | FPGA synthesis and place-and-route |

## Layout

```
model/    Python golden model: the executable specification, and the analysis scripts
rtl/      synthesizable SystemVerilog
tb/       self-checking testbenches
sim/      one-command verification
synth/    Vivado scripts (constraints, sweeps, reporting)
results/  measured CSVs and the figures generated from them
```

## Notes

`rtl/lwe_encrypt_par.sv` is the author's verified MAC core, reused unmodified from [LATTICE](https://github.com/Sarkar22/LATTICE).

The seed must be unpredictable and must never repeat under the same key, exactly as a counter-mode nonce must not repeat. LWE here provides confidentiality and additive homomorphism, **not** integrity.

## License

MIT, see [LICENSE](LICENSE).

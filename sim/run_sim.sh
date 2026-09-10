#!/usr/bin/env bash
# Verify the Ascon-XOF128 keystream core against NIST-derived known-answer vectors,
# at every rounds-per-cycle setting (the area/throughput knob must not change results).
set -e
cd "$(dirname "$0")"

echo "== regenerating golden model + vectors =="
python3 - <<'PY'
import sys; sys.path.insert(0, "../model")
import ascon
assert ascon._selftest(), "golden model failed the official NIST KATs"
ascon.emit_vectors()
PY

echo
echo "== RTL vs vectors, sweeping ROUNDS_PER_CYCLE =="
fail=0
for R in 1 2 3 4 5 6 7 8 9 10 11 12; do
    iverilog -g2012 -DRPC=$R -o /tmp/ascon_rpc$R.vvp ../rtl/ascon_xof.sv ../tb/tb_ascon.sv 2>/dev/null
    out=$(vvp /tmp/ascon_rpc$R.vvp 2>/dev/null | grep -E "RESULT|words exact")
    echo "  RPC=$R: $(echo "$out" | tr '\n' ' ')"
    echo "$out" | grep -q "RESULT: PASS" || fail=1
done
echo
[ $fail -eq 0 ] && echo "ALL CONFIGURATIONS PASS" || { echo "FAILURES PRESENT"; exit 1; }

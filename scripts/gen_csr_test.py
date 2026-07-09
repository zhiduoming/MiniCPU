# NOTE: gaps (NOPs) are inserted between each CSR write and its following read
# to reproduce the board's Test 16 pattern, where a CSR write is followed by
# 2-3 other instructions (LUI/ADDI/BNE) BEFORE the dependent CSR read. The
# non-adjacent RAW is exactly the case the csr_bubble fix must handle.
NOP = '00000013'
from pathlib import Path
import sys

lines = [
    '123450B7',  # LUI  x1, 0x12345
    '67808093',  # ADDI x1, x1, 0x678   -> x1 = 0x12345678
    '30509173',  # CSRRW x2, 0x305, x1  -> mtvec<=0x12345678, x2<=old(0x1000)
    '305021F3',  # CSRRS x3, 0x305, x0  -> x3<=0x12345678 (ADJACENT RAW after CSRRW)
    '30502273',  # CSRRS x4, 0x305, x0  -> x4<=0x12345678
    '00100293',  # ADDI  x5, x0, 0x1    -> x5 = 1
    '3052A373',  # CSRRS x6, 0x305, x5  -> mtvec<=0x12345679, x6<=0x12345678
    NOP,         # gap (non-adjacent RAW)
    NOP,         # gap
    '305023F3',  # CSRRS x7, 0x305, x0  -> x7<=0x12345679 (NON-ADJACENT RAW after CSRRS, gap=2)
]
lines += ['00000013'] * (2048 - len(lines))
default_out = Path(__file__).resolve().parents[1] / 'mem' / 'csr_test.hex'
out_path = Path(sys.argv[1]) if len(sys.argv) > 1 else default_out
out_path.parent.mkdir(parents=True, exist_ok=True)
with open(out_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')
print('wrote', len(lines), 'lines to', out_path)

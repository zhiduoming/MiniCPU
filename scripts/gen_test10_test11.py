#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEST_DIR = ROOT / "test_programs"
NOP = 0x00000013

OPC_LUI = 0x37
OPC_JAL = 0x6F
OPC_JALR = 0x67
OPC_B = 0x63
OPC_L = 0x03
OPC_S = 0x23
OPC_I = 0x13
OPC_R = 0x33


def reg(name):
    name = name.strip()
    if name.startswith("x"):
        return int(name[1:])
    aliases = {
        "zero": 0, "ra": 1, "sp": 2,
        "t0": 5, "t1": 6, "t2": 7,
        "s0": 8, "s1": 9,
        "a0": 10, "a1": 11, "a2": 12,
        "a3": 13, "a4": 14, "a5": 15,
        "a6": 16, "a7": 17,
        "s2": 18, "s3": 19, "s4": 20,
        "s5": 21, "s6": 22, "s7": 23,
        "s8": 24, "s9": 25, "s10": 26, "s11": 27,
        "t3": 28, "t4": 29, "t5": 30, "t6": 31,
    }
    return aliases[name]


def imm12(v):
    if not -2048 <= v <= 2047:
        raise ValueError(f"imm12 out of range: {v}")
    return v & 0xFFF


def enc_u(rd, imm20, opc=OPC_LUI):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opc


def enc_i(f3, rd, rs1, imm, opc=OPC_I):
    return (imm12(imm) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opc


def enc_r(f3, f7, rd, rs1, rs2):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | OPC_R


def enc_s(f3, rs1, rs2, imm):
    v = imm12(imm)
    return ((v >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((v & 0x1F) << 7) | OPC_S


def enc_b(f3, rs1, rs2, imm):
    if imm % 2:
        raise ValueError("branch offset must be 2-byte aligned")
    v = imm & 0x1FFF
    return ((v >> 12) & 1) << 31 | ((v >> 5) & 0x3F) << 25 | (rs2 << 20) | \
        (rs1 << 15) | (f3 << 12) | ((v >> 1) & 0xF) << 8 | ((v >> 11) & 1) << 7 | OPC_B


def enc_j(rd, imm):
    if imm % 2:
        raise ValueError("jump offset must be 2-byte aligned")
    v = imm & 0x1FFFFF
    return ((v >> 20) & 1) << 31 | ((v >> 1) & 0x3FF) << 21 | \
        ((v >> 11) & 1) << 20 | ((v >> 12) & 0xFF) << 12 | (rd << 7) | OPC_JAL


def parse_mem(s):
    off, rest = s.split("(")
    return int(off, 0), reg(rest.rstrip(")"))


def encode(op, args, labels, pc):
    op = op.upper()
    if op == "NOP":
        return NOP
    if op == "LUI":
        return enc_u(reg(args[0]), int(args[1], 0))
    if op == "ADDI":
        return enc_i(0, reg(args[0]), reg(args[1]), int(args[2], 0))
    if op == "ANDI":
        return enc_i(7, reg(args[0]), reg(args[1]), int(args[2], 0))
    if op == "SLLI":
        return enc_i(1, reg(args[0]), reg(args[1]), int(args[2], 0))
    if op == "ADD":
        return enc_r(0, 0, reg(args[0]), reg(args[1]), reg(args[2]))
    if op == "DIVU":
        return enc_r(5, 1, reg(args[0]), reg(args[1]), reg(args[2]))
    if op == "REMU":
        return enc_r(7, 1, reg(args[0]), reg(args[1]), reg(args[2]))
    if op == "LW":
        off, rs1 = parse_mem(args[1])
        return enc_i(2, reg(args[0]), rs1, off, OPC_L)
    if op == "SW":
        off, rs1 = parse_mem(args[1])
        return enc_s(2, rs1, reg(args[0]), off)
    if op == "BNE":
        return enc_b(1, reg(args[0]), reg(args[1]), labels[args[2]] - pc)
    if op == "BEQ":
        return enc_b(0, reg(args[0]), reg(args[1]), labels[args[2]] - pc)
    if op == "JAL":
        return enc_j(reg(args[0]), labels[args[1]] - pc)
    if op == "JALR":
        off, rs1 = parse_mem(args[1])
        return enc_i(0, reg(args[0]), rs1, off, OPC_JALR)
    raise ValueError(f"unknown op: {op}")


def clean(line):
    line = line.split("#", 1)[0].strip()
    if not line:
        return []
    return [p.strip().rstrip(",") for p in line.replace(",", " ").split()]


def assemble(asm):
    labels = {}
    items = []
    pc = 0
    for raw in asm.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.endswith(":"):
            labels[line[:-1]] = pc
            continue
        parts = clean(line)
        if not parts:
            continue
        if parts[0] == ".org":
            target = int(parts[1], 0)
            while pc < target:
                items.append((pc, "NOP", []))
                pc += 4
            continue
        if parts[0].startswith("."):
            continue
        items.append((pc, parts[0], parts[1:]))
        pc += 4
    code = [NOP] * 2048
    for pc, op, args in items:
        code[pc // 4] = encode(op, args, labels, pc)
    return code, labels


def write_hex(path, words):
    lines = [f"{w & 0xFFFFFFFF:08X}" for w in words[:2048]]
    while len(lines) < 2048:
        lines.append("00000013")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def write_test10():
    src_hex = ROOT / "mem" / "program.hex"
    words = [line.strip().upper() for line in src_hex.read_text(encoding="ascii").splitlines() if line.strip()]
    words = words[:2048] + ["00000013"] * max(0, 2048 - len(words))
    (TEST_DIR / "test10_perf_clean.hex").write_text("\n".join(words[:2048]) + "\n", encoding="ascii")


TEST11_ASM = r"""
# Test 11: I-cache conflict benchmark.
#
# Expected behavior:
# - DIRECT mode should show many more I-cache misses.
# - 4WAY mode should show mostly warm-up misses, then hits.
#
# Why it works:
# The hot blocks are placed at 0x080, 0x100, 0x180 and 0x200.
# These addresses differ by 0x80, so direct-mapped index bits [6:2]
# collide. In 4-way mode they can live in different ways of the same set.
#
# Continuous mode: SW0 = 1, SW8 = 0. Reset between DIRECT and 4WAY runs.

    LUI   x30, 0x10010        # UART/perf MMIO base
    SW    x0, 0x08(x30)       # clear PerfMon
    ADDI  x0, x0, 0
    ADDI  x0, x0, 0
    ADDI  x0, x0, 0
    ADDI  x5, x0, 200         # loop count
    ADDI  x6, x0, 0           # checksum/counter
    JAL   x0, block0

    .org 0x080
block0:
    ADDI  x6, x6, 1
    JAL   x0, block1

    .org 0x100
block1:
    ADDI  x6, x6, 1
    JAL   x0, block2

    .org 0x180
block2:
    ADDI  x6, x6, 1
    JAL   x0, block3

    .org 0x200
block3:
    ADDI  x6, x6, 1
    ADDI  x5, x5, -1
    BNE   x5, x0, block0
    JAL   x0, after_bench

after_bench:
    LW    x5, 0x20(x30)       # cycles
    LW    x6, 0x24(x30)       # retired instructions
    LW    x7, 0x28(x30)       # accesses
    LW    x8, 0x2C(x30)       # hits
    LW    x9, 0x30(x30)       # misses
    LW    x10, 0x34(x30)      # mode

    ADDI  x16, x0, 0
    LUI   x16, 0x10001
    ADDI  x16, x16, -4

    ADDI  x20, x0, 84         # T
    JAL   x1, put_ch
    ADDI  x20, x0, 49         # 1
    JAL   x1, put_ch
    ADDI  x20, x0, 49         # 1
    JAL   x1, put_ch
    ADDI  x20, x0, 32
    JAL   x1, put_ch
    ADDI  x20, x0, 77         # M
    JAL   x1, put_ch
    ADDI  x20, x0, 79         # O
    JAL   x1, put_ch
    ADDI  x20, x0, 68         # D
    JAL   x1, put_ch
    ADDI  x20, x0, 69         # E
    JAL   x1, put_ch
    ADDI  x20, x0, 61         # =
    JAL   x1, put_ch
    BNE   x10, x0, print_4way
    ADDI  x20, x0, 68         # D
    JAL   x1, put_ch
    ADDI  x20, x0, 73         # I
    JAL   x1, put_ch
    ADDI  x20, x0, 82         # R
    JAL   x1, put_ch
    JAL   x0, print_nl_1
print_4way:
    ADDI  x20, x0, 52         # 4
    JAL   x1, put_ch
    ADDI  x20, x0, 87         # W
    JAL   x1, put_ch
    ADDI  x20, x0, 65         # A
    JAL   x1, put_ch
    ADDI  x20, x0, 89         # Y
    JAL   x1, put_ch
print_nl_1:
    ADDI  x20, x0, 13
    JAL   x1, put_ch
    ADDI  x20, x0, 10
    JAL   x1, put_ch

    ADDI  x20, x0, 67         # C
    JAL   x1, put_ch
    ADDI  x20, x0, 89         # Y
    JAL   x1, put_ch
    ADDI  x20, x0, 67         # C
    JAL   x1, put_ch
    ADDI  x20, x0, 61         # =
    JAL   x1, put_ch
    ADDI  x10, x5, 0
    JAL   x1, put_dec
    ADDI  x20, x0, 32
    JAL   x1, put_ch
    ADDI  x20, x0, 73         # I
    JAL   x1, put_ch
    ADDI  x20, x0, 78         # N
    JAL   x1, put_ch
    ADDI  x20, x0, 83         # S
    JAL   x1, put_ch
    ADDI  x20, x0, 84         # T
    JAL   x1, put_ch
    ADDI  x20, x0, 61         # =
    JAL   x1, put_ch
    ADDI  x10, x6, 0
    JAL   x1, put_dec
    ADDI  x20, x0, 13
    JAL   x1, put_ch
    ADDI  x20, x0, 10
    JAL   x1, put_ch

    ADDI  x20, x0, 65         # A
    JAL   x1, put_ch
    ADDI  x20, x0, 67         # C
    JAL   x1, put_ch
    ADDI  x20, x0, 67         # C
    JAL   x1, put_ch
    ADDI  x20, x0, 61         # =
    JAL   x1, put_ch
    ADDI  x10, x7, 0
    JAL   x1, put_dec
    ADDI  x20, x0, 32
    JAL   x1, put_ch
    ADDI  x20, x0, 72         # H
    JAL   x1, put_ch
    ADDI  x20, x0, 73         # I
    JAL   x1, put_ch
    ADDI  x20, x0, 84         # T
    JAL   x1, put_ch
    ADDI  x20, x0, 61         # =
    JAL   x1, put_ch
    ADDI  x10, x8, 0
    JAL   x1, put_dec
    ADDI  x20, x0, 32
    JAL   x1, put_ch
    ADDI  x20, x0, 77         # M
    JAL   x1, put_ch
    ADDI  x20, x0, 73         # I
    JAL   x1, put_ch
    ADDI  x20, x0, 83         # S
    JAL   x1, put_ch
    ADDI  x20, x0, 83         # S
    JAL   x1, put_ch
    ADDI  x20, x0, 61         # =
    JAL   x1, put_ch
    ADDI  x10, x9, 0
    JAL   x1, put_dec
    ADDI  x20, x0, 13
    JAL   x1, put_ch
    ADDI  x20, x0, 10
    JAL   x1, put_ch

done:
    JAL   x0, done

put_ch:
    LW    x31, 4(x30)
    ANDI  x31, x31, 1
    BNE   x31, x0, put_ch
    SW    x20, 0(x30)
    JALR  x0, 0(x1)

put_dec:
    SW    x1, 0(x16)
    ADDI  x16, x16, -4
    BNE   x10, x0, pd_nz
    ADDI  x20, x0, 48
    JAL   x1, put_ch
    JAL   x0, pd_ret
pd_nz:
    ADDI  x17, x0, 0
pd_lp:
    ADDI  x11, x0, 10
    REMU  x12, x10, x11
    DIVU  x10, x10, x11
    SW    x12, 0(x16)
    ADDI  x16, x16, -4
    ADDI  x17, x17, 1
    BNE   x10, x0, pd_lp
pd_pr:
    ADDI  x16, x16, 4
    LW    x20, 0(x16)
    ADDI  x20, x20, 48
    JAL   x1, put_ch
    ADDI  x17, x17, -1
    BNE   x17, x0, pd_pr
pd_ret:
    LW    x1, 4(x16)
    ADDI  x16, x16, 4
    JALR  x0, 0(x1)
"""


def write_test11():
    code, labels = assemble(TEST11_ASM)
    write_hex(TEST_DIR / "test11_icache_conflict.hex", code)
    active = max(i for i, w in enumerate(code) if w != NOP) + 1
    print(f"test11 active words: {active}")
    for name in ["block0", "block1", "block2", "block3"]:
        print(f"{name}: 0x{labels[name]:03X}")


def main():
    TEST_DIR.mkdir(exist_ok=True)
    write_test10()
    write_test11()
    print("wrote test10_perf_clean.hex")
    print("wrote test11_icache_conflict.hex")


if __name__ == "__main__":
    main()

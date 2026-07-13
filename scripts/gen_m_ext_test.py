#!/usr/bin/env python3
# Generate a focused RV32M multiply/divide extension test program.
# The program writes "OK\r\n" to the MMIO UART on success. On failure it
# writes the test id, actual value, expected value, and "FAIL\r\n".
from pathlib import Path
import re
import sys

OPC_R = 0x33
OPC_I = 0x13
OPC_L = 0x03
OPC_S = 0x23
OPC_B = 0x63
OPC_LUI = 0x37
OPC_JAL = 0x6F
OPC_JALR = 0x67


def reg(name):
    name = name.lower().strip()
    if name in ("x0", "zero"):
        return 0
    if not name.startswith("x"):
        raise ValueError(f"bad register {name}")
    return int(name[1:])


def chk_imm12(imm):
    if imm < -2048 or imm > 2047:
        raise ValueError(f"immediate {imm} out of 12-bit signed range")


def asm_r(funct3, funct7, rd, rs1, rs2):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | OPC_R


def asm_i(opcode, funct3, rd, rs1, imm):
    chk_imm12(imm)
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def asm_s(funct3, rs1, rs2, imm):
    chk_imm12(imm)
    imm &= 0xFFF
    return ((imm & 0x1F) << 7) | (funct3 << 12) | (rs1 << 15) | (rs2 << 20) | (((imm >> 5) & 0x7F) << 25) | OPC_S


def asm_b(funct3, rs1, rs2, imm):
    if imm % 2:
        raise ValueError(f"branch immediate must be halfword aligned: {imm}")
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | OPC_B


def asm_u(rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | OPC_LUI


def asm_j(rd, imm):
    if imm % 2:
        raise ValueError(f"jump immediate must be halfword aligned: {imm}")
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | \
           (((imm >> 12) & 0xFF) << 12) | (rd << 7) | OPC_JAL


ASM = r"""
    LUI   x30, 0x10010        # UART TX base = 0x10010000

    # 01: MUL low 32 bits
    ADDI  x26, x0, 1
    ADDI  x1, x0, 7
    ADDI  x2, x0, 6
    MUL   x3, x1, x2
    ADDI  x9, x0, 42
    BNE   x3, x9, fail

    # 02: MULH signed x signed high 32 bits
    ADDI  x26, x0, 2
    ADDI  x1, x0, -2
    ADDI  x2, x0, 3
    MULH  x3, x1, x2
    ADDI  x9, x0, -1
    BNE   x3, x9, fail

    # 03: MULHSU signed x unsigned high 32 bits
    ADDI  x26, x0, 3
    MULHSU x3, x1, x2
    ADDI  x9, x0, -1
    BNE   x3, x9, fail

    # 04: MULHU unsigned x unsigned high 32 bits
    ADDI  x26, x0, 4
    ADDI  x1, x0, -1
    ADDI  x2, x0, 2
    MULHU x3, x1, x2
    ADDI  x9, x0, 1
    BNE   x3, x9, fail

    # 05: DIV signed, truncates toward zero
    ADDI  x26, x0, 5
    ADDI  x1, x0, -21
    ADDI  x2, x0, 4
    DIV   x3, x1, x2
    ADDI  x9, x0, -5
    BNE   x3, x9, fail

    # 06: REM signed
    ADDI  x26, x0, 6
    REM   x3, x1, x2
    ADDI  x9, x0, -1
    BNE   x3, x9, fail

    # 07: DIVU unsigned
    ADDI  x26, x0, 7
    ADDI  x1, x0, -1
    ADDI  x2, x0, 2
    DIVU  x3, x1, x2
    LUI   x9, 0x80000
    ADDI  x9, x9, -1
    BNE   x3, x9, fail

    # 08: REMU unsigned
    ADDI  x26, x0, 8
    REMU  x3, x1, x2
    ADDI  x9, x0, 1
    BNE   x3, x9, fail

    # 09: divide by zero quotient
    ADDI  x26, x0, 9
    ADDI  x1, x0, 123
    ADDI  x2, x0, 0
    DIV   x3, x1, x2
    ADDI  x9, x0, -1
    BNE   x3, x9, fail
    DIVU  x3, x1, x2
    BNE   x3, x9, fail

    # 10: divide by zero remainder returns dividend
    ADDI  x26, x0, 10
    REM   x3, x1, x2
    ADDI  x9, x0, 123
    BNE   x3, x9, fail
    REMU  x3, x1, x2
    BNE   x3, x9, fail

    # 11: signed overflow INT_MIN / -1
    ADDI  x26, x0, 11
    LUI   x1, 0x80000
    ADDI  x2, x0, -1
    DIV   x3, x1, x2
    LUI   x9, 0x80000
    BNE   x3, x9, fail
    REM   x3, x1, x2
    BNE   x3, x0, fail

    JAL   x0, print_ok

fail:
    PUTC 0x49
    PUTC 0x44
    PUTC 0x3D
    SRLI  x20, x26, 4
    ANDI  x20, x20, 0xF
    JAL   x1, put_hex
    ANDI  x20, x26, 0xF
    JAL   x1, put_hex
    PUTC 0x20
    PUTC 0x41
    PUTC 0x43
    PUTC 0x54
    PUTC 0x3D
    ADD   x21, x27, x0
    JAL   x1, put_hex32
    PUTC 0x20
    PUTC 0x45
    PUTC 0x58
    PUTC 0x50
    PUTC 0x3D
    ADD   x21, x28, x0
    JAL   x1, put_hex32
    PUTC 0x20
    JAL   x0, print_fail_msg

put_hex32:
    ADD   x29, x1, x0
    ADDI  x22, x0, 8
ph32_loop:
    SRLI  x20, x21, 28
    JAL   x1, put_hex
    SLLI  x21, x21, 4
    ADDI  x22, x22, -1
    BNE   x22, x0, ph32_loop
    JALR  x0, 0(x29)

put_hex:
    ADDI  x9, x0, 10
    BLT   x20, x9, ph_num
    ADDI  x20, x20, -10
    ADDI  x20, x20, 0x41
    JAL   x0, ph_emit
ph_num:
    ADDI  x20, x20, 0x30
ph_emit:
    LW    x31, 4(x30)
    ANDI  x31, x31, 1
    BNE   x31, x0, ph_emit
    SW    x20, 0(x30)
    JALR  x0, 0(x1)

print_fail_msg:
    PUTC 0x46
    PUTC 0x41
    PUTC 0x49
    PUTC 0x4C
    PUTC 0x0D
    PUTC 0x0A
    JAL   x0, done

print_ok:
    PUTC 0x4F
    PUTC 0x4B
    PUTC 0x0D
    PUTC 0x0A
    JAL   x0, done

done:
    JAL   x0, done
"""


def parse_mem(arg):
    m = re.match(r"(-?\d+)\((x\d+)\)", arg.replace(" ", ""))
    if not m:
        raise ValueError(f"bad memory operand {arg}")
    return int(m.group(1), 0), reg(m.group(2))


def parse():
    raw = []
    labels = {}
    pc_words = 0
    fail_ctx = 0
    for line in ASM.strip().splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        if line.endswith(":"):
            labels[line[:-1]] = pc_words * 4
            continue
        parts = [p.strip().rstrip(",") for p in line.split()]
        op = parts[0].upper()
        if op == "PUTC":
            ch = int(parts[1], 0)
            raw.append(("ADDI", ["x20", "x0", str(ch)])); pc_words += 1
            lbl = f".putc_{pc_words}"
            labels[lbl] = pc_words * 4
            raw.append(("LW", ["x31", "4(x30)"])); pc_words += 1
            raw.append(("ANDI", ["x31", "x31", "1"])); pc_words += 1
            raw.append(("BNE", ["x31", "x0", lbl])); pc_words += 1
            raw.append(("SW", ["x20", "0(x30)"])); pc_words += 1
        elif op == "BNE" and len(parts) == 4 and parts[3] == "fail":
            fail_ctx += 1
            fail_lbl = f".failctx_{fail_ctx}"
            after_lbl = f".after_failctx_{fail_ctx}"
            raw.append(("BNE", [parts[1], parts[2], fail_lbl])); pc_words += 1
            raw.append(("JAL", ["x0", after_lbl])); pc_words += 1
            labels[fail_lbl] = pc_words * 4
            raw.append(("ADD", ["x27", parts[1], "x0"])); pc_words += 1
            raw.append(("ADD", ["x28", parts[2], "x0"])); pc_words += 1
            raw.append(("JAL", ["x0", "fail"])); pc_words += 1
            labels[after_lbl] = pc_words * 4
        else:
            raw.append((op, parts[1:]))
            pc_words += 1
    return raw, labels


def encode(raw, labels):
    code = []
    for idx, (op, args) in enumerate(raw):
        pc = idx * 4
        if op == "LUI":
            code.append(asm_u(reg(args[0]), int(args[1], 0)))
        elif op in ("ADDI", "ANDI", "SRLI", "SLLI"):
            funct3 = {"ADDI": 0, "SLLI": 1, "SRLI": 5, "ANDI": 7}[op]
            code.append(asm_i(OPC_I, funct3, reg(args[0]), reg(args[1]), int(args[2], 0)))
        elif op == "ADD":
            code.append(asm_r(0, 0, reg(args[0]), reg(args[1]), reg(args[2])))
        elif op == "LW":
            imm, rs1 = parse_mem(args[1])
            code.append(asm_i(OPC_L, 2, reg(args[0]), rs1, imm))
        elif op == "SW":
            imm, rs1 = parse_mem(args[1])
            code.append(asm_s(2, rs1, reg(args[0]), imm))
        elif op in ("BNE", "BLT"):
            funct3 = {"BNE": 1, "BLT": 4}[op]
            code.append(asm_b(funct3, reg(args[0]), reg(args[1]), labels[args[2]] - pc))
        elif op == "JAL":
            code.append(asm_j(reg(args[0]), labels[args[1]] - pc))
        elif op == "JALR":
            imm, rs1 = parse_mem(args[1])
            code.append(asm_i(OPC_JALR, 0, reg(args[0]), rs1, imm))
        elif op in ("MUL", "MULH", "MULHSU", "MULHU", "DIV", "DIVU", "REM", "REMU"):
            funct3 = {
                "MUL": 0, "MULH": 1, "MULHSU": 2, "MULHU": 3,
                "DIV": 4, "DIVU": 5, "REM": 6, "REMU": 7,
            }[op]
            code.append(asm_r(funct3, 1, reg(args[0]), reg(args[1]), reg(args[2])))
        else:
            raise ValueError(f"unsupported op {op}")
    return code


def main():
    out_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "mem" / "m_ext_test.hex"
    raw, labels = parse()
    code = encode(raw, labels)
    lines = [f"{word:08X}" for word in code]
    while len(lines) < 2048:
        lines.append("00000013")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n")
    print(f"wrote {len(lines)} lines to {out_path} ({len(code)} instructions before padding)")


if __name__ == "__main__":
    main()

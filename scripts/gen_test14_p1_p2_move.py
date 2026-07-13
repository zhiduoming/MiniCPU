"""Generate the two-player horizontal movement test for CPU game MMIO."""
from pathlib import Path


def lui(rd, imm20):
    return (imm20 << 12) | (rd << 7) | 0x37


def i_type(rd, rs1, funct3, imm12, opcode=0x13):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def s_type(rs2, rs1, funct3, imm12):
    imm = imm12 & 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | 0x23


def bne(rs1, rs2, offset):
    imm = offset & 0x1FFF
    return ((imm >> 12) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (1 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63


def jal(rd, offset):
    imm = offset & 0x1FFFFF
    return ((imm >> 20) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def build_program():
    code, labels, fixups = [], {}, []

    def emit(word):
        code.append(word)

    def mark(name):
        labels[name] = len(code)

    def branch(rs1, rs2, target):
        fixups.append((len(code), "branch", rs1, rs2, target))
        emit(0)

    def jump(target):
        fixups.append((len(code), "jump", 0, 0, target))
        emit(0)

    emit(lui(5, 0x10010))                # x5 = 0x10010000
    emit(i_type(5, 5, 0, 0x100))         # x5 = game position MMIO base
    emit(i_type(7, 5, 0, 0x010))         # x7 = game input MMIO register
    emit(lui(6, 0x280))                  # x6 = P1 Y=40
    emit(i_type(6, 6, 0, 100))           # x6 = P1 initial X=100
    emit(lui(11, 0x280))                 # x11 = P2 Y=40
    emit(i_type(11, 11, 0, 650))         # x11 = P2 initial X=650

    mark("loop")
    emit(s_type(6, 5, 2, 0))             # SW P1 position
    emit(s_type(11, 5, 2, 4))            # SW P2 position
    emit(lui(9, 0x18))                   # 98,304
    emit(i_type(9, 9, 0, 1696))          # 100,000-cycle movement delay
    mark("delay")
    emit(i_type(9, 9, 0, -1))
    branch(9, 0, "delay")
    emit(i_type(8, 7, 2, 0, 0x03))       # LW input bits

    # P1: bit 0 = keypad 4 left, bit 1 = keypad 6 right.
    emit(i_type(10, 8, 7, 0x001))
    branch(10, 0, "p1_left")
    emit(i_type(10, 8, 7, 0x002))
    branch(10, 0, "p1_right")

    mark("after_p1")
    # P2: bit 8 = S2 left, bit 9 = S1 right.
    emit(i_type(10, 8, 7, 0x100))
    branch(10, 0, "p2_left")
    emit(i_type(10, 8, 7, 0x200))
    branch(10, 0, "p2_right")
    jump("loop")

    mark("p1_left")
    emit(i_type(6, 6, 0, -2))
    jump("after_p1")
    mark("p1_right")
    emit(i_type(6, 6, 0, 2))
    jump("after_p1")
    mark("p2_left")
    emit(i_type(11, 11, 0, -2))
    jump("loop")
    mark("p2_right")
    emit(i_type(11, 11, 0, 2))
    jump("loop")

    for index, kind, rs1, rs2, target in fixups:
        offset = (labels[target] - index) * 4
        code[index] = bne(rs1, rs2, offset) if kind == "branch" else jal(0, offset)
    return code


def main():
    output = Path(__file__).resolve().parents[1] / "test_programs" / "test14_p1_p2_move.hex"
    program = build_program()
    words = program + [0x00000013] * (2048 - len(program))
    output.write_text("\n".join(f"{word:08X}" for word in words) + "\n", encoding="ascii")


if __name__ == "__main__":
    main()

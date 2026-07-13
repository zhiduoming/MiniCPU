"""Generate a P1 matrix-keypad movement test for the CPU game MMIO."""
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


PROGRAM = [
    lui(5, 0x10010),                    # x5 = 0x10010000
    i_type(5, 5, 0, 0x100),             # x5 = P1-position register: 0x10010100
    i_type(7, 5, 0, 0x010),             # x7 = input register:       0x10010110
    lui(6, 0x280),                      # x6 = (Y=40, X=0)
    i_type(6, 6, 0, 100),               # x6 = P1 initial position:  (100, 40)
    s_type(6, 5, 2, 0),                 # loop: store current P1 position
    lui(9, 0x18),                       # x9 = 98,304
    i_type(9, 9, 0, 1696),              # x9 = 100,000: movement delay
    i_type(9, 9, 0, -1),                # delay: x9--
    bne(9, 0, -4),                      # repeat delay
    i_type(8, 7, 2, 0, 0x03),           # x8 = LW input bits
    i_type(10, 8, 7, 1),                # x10 = input & 1: key 4 (left)
    bne(10, 0, 16),                     # -> left handler
    i_type(10, 8, 7, 2),                # x10 = input & 2: key 6 (right)
    bne(10, 0, 16),                     # -> right handler
    jal(0, -40),                        # no key: go back to loop
    i_type(6, 6, 0, -2),                # left:  X -= 2
    jal(0, -48),                        # go back to loop
    i_type(6, 6, 0, 2),                 # right: X += 2
    jal(0, -56),                        # go back to loop
]


def main():
    output = Path(__file__).resolve().parents[1] / "test_programs" / "test13_p1_keypad_move.hex"
    words = PROGRAM + [0x00000013] * (2048 - len(PROGRAM))
    output.write_text("\n".join(f"{word:08X}" for word in words) + "\n", encoding="ascii")


if __name__ == "__main__":
    main()

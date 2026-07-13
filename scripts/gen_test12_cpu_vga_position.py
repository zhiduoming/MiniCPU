"""Generate the CPU-to-VGA MMIO position test program."""
from pathlib import Path


PROGRAM = [
    0x100102B7,  # lui  x5, 0x10010       -> 0x10010000
    0x10028293,  # addi x5, x5, 0x100     -> game MMIO base 0x10010100
    0x00280337,  # lui  x6, 0x280         -> Y=40, X=0
    0x11830313,  # addi x6, x6, 280       -> P1: (280, 40)
    0x0062A023,  # sw   x6, 0(x5)
    0x0F030313,  # addi x6, x6, 240       -> P2: (520, 40)
    0x0062A223,  # sw   x6, 4(x5)
    0x0000006F,  # jal  x0, 0             -> hold the final scene
]


def main():
    output = Path(__file__).resolve().parents[1] / "test_programs" / "test12_cpu_vga_position.hex"
    words = PROGRAM + [0x00000013] * (2048 - len(PROGRAM))
    output.write_text("\n".join(f"{word:08X}" for word in words) + "\n", encoding="ascii")


if __name__ == "__main__":
    main()

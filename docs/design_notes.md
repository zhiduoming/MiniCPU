# Design Notes

## System Overview

- ISA target: RV32I base integer subset with RV32M multiply/divide extension (`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`).
- Pipeline stages: classic five-stage pipeline, IF / ID / EX / MEM / WB.
- Memory map:
  - instruction ROM: `0x00000000` region, initialized from `mem/program.hex`.
  - data RAM: `0x10000000` region, implemented by `DataMemory`.
  - UART MMIO: `0x10010000` transmit data, `0x10010004` status.
- MMIO devices: UART transmit path plus debug UART/button/LED integration at board top.
- FPGA board: Minisys, Xilinx Artix-7, Vivado flow through `scripts/vivado_import.tcl`.

## Key Modules

| Module | File | Responsibility | Owner |
| --- | --- | --- | --- |
| `RV32I46F5SPMMIOSoCTOP` | `rtl/top/46F5SP_MMIO_SoC_TOP.v` | FPGA board integration | |
| `RV32I46F5SPMMIO` | `rtl/top/RV32I46F_5SP_MMIO.v` | CPU system top | |
| `ControlUnit` | `rtl/core/Control_Unit.v` | Instruction control signals | |
| `HazardUnit` | `rtl/core/Hazard_Unit.v` | Stall and flush control | |
| `ForwardUnit` | `rtl/core/Forward_Unit.v` | Data forwarding | |
| `InstructionMemory` | `rtl/memory/Instruction_Memory.v` | ROM instruction fetch | |
| `ALUController` | `rtl/core/ALU_Controller.v` | Decode ALU operation, including RV32M operations when `funct7=0000001` | |
| `ALU` | `rtl/core/ALU.v` | Execute integer ALU and RV32M multiply/divide operations | |

## RV32M Extension

The RV32M extension is implemented as an EX-stage combinational ALU extension. It reuses the existing R-type datapath, register file, forwarding path, and write-back path. The divider follows RISC-V edge-case semantics for divide-by-zero and signed overflow.

| Instruction | Encoding condition | Result |
| --- | --- | --- |
| `MUL` | `opcode=0110011`, `funct7=0000001`, `funct3=000` | low 32 bits of `rs1 * rs2` |
| `MULH` | `opcode=0110011`, `funct7=0000001`, `funct3=001` | high 32 bits of signed x signed product |
| `MULHSU` | `opcode=0110011`, `funct7=0000001`, `funct3=010` | high 32 bits of signed x unsigned product |
| `MULHU` | `opcode=0110011`, `funct7=0000001`, `funct3=011` | high 32 bits of unsigned x unsigned product |
| `DIV` | `opcode=0110011`, `funct7=0000001`, `funct3=100` | signed quotient, rounded toward zero |
| `DIVU` | `opcode=0110011`, `funct7=0000001`, `funct3=101` | unsigned quotient |
| `REM` | `opcode=0110011`, `funct7=0000001`, `funct3=110` | signed remainder |
| `REMU` | `opcode=0110011`, `funct7=0000001`, `funct3=111` | unsigned remainder |

The CSR `misa` value is updated to `0x40001100`, declaring RV32IM support (`I` and `M` bits set).

Focused verification files:

- `scripts/gen_m_ext_test.py`: generates `mem/m_ext_test.hex`.
- `sim/tb_m_ext.v`: runs only the RV32M multiply/divide focused ROM and reports `M_EXT_RESULT`.

## Verification Checklist

- [ ] Basic arithmetic and logic instructions
- [ ] Load/store instructions
- [ ] Branch and jump instructions
- [ ] Pipeline stall and flush behavior
- [ ] MMIO and UART output
- [x] RV32M reference-program generation
- [x] RV32M Verilog simulation
- [ ] FPGA synthesis
- [ ] FPGA implementation/timing
- [ ] Board-level validation

## External Interrupt

- Board source: `SW20`, synchronized and debounced for 50 ms.
- Trigger: one pulse on the stable `0 -> 1` transition; return `SW20` to zero
  before triggering it again.
- Trap code: machine external interrupt, `mcause = 0x8000000B`.
- Entry: the interrupted fetch PC is saved to `mepc`, then execution redirects
  to `mtvec`.
- Return: `MRET` resumes at the saved `mepc` value.
- Verification: `sim/tb_external_irq.v` with
  `test_programs/irq_external.hex` prints `EXTERNAL_IRQ_PASS` in simulation.
- The game program installs its own `mtvec` handler. An interrupt pauses all
  game state, drives `game_flags[30]`, displays `PERF REPORT` for about six
  seconds, prints the in-game CPU counters over UART, then executes `MRET` and
  resumes the interrupted game instruction.
- Integrated verification: `sim/tb_game_external_irq.v` reports
  `GAME_EXTERNAL_IRQ_PASS` with a screen counter of 751.

## In-Game Performance Report

- The match-start transition clears `PerfMon`; menus and initialization are
  therefore excluded from the measurement window.
- Counted values: cycles, retired instructions, pipeline stalls, branches,
  branch mispredictions, load/store operations, I-cache accesses/hits/misses,
  RV32M instructions, custom MAC instructions, and multiply/divide/MAC EX
  occupancy cycles.
- Additional MMIO registers: `0x10010038` stall, `0x1001003C` branch,
  `0x10010040` mispredict, `0x10010044` memory, `0x10010048` RV32M,
  `0x1001004C` MAC, and `0x10010050` unit cycles.
- The core has no D-cache. Its current I-cache is non-stalling, so the reported
  I-cache miss penalty is zero. Speedups requiring a non-pipelined,
  prediction-disabled, or cache-disabled reference core are not claimed.

## Buzzer Audio States

- Mode/time menus: `assets/menu_theme.mp3`, converted to `Menu_Theme_Player`.
- Active match: `assets/game_bgm.mp3`, converted to track 2 of
  `Buzzer_Track_Player` and enabled by CPU flag bit 31.
- Five-second death result: `assets/player_down.mp3`, track 0, enabled by the
  CPU round-over flag bit 12.
- `TIME RUN OUT`: `assets/time_run_out.mp3`, track 1, enabled by bit 29.
- `SW21=1` is a hardware master mute for music and sound effects.

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

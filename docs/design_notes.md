# Design Notes

## System Overview

- ISA target: RV32I base integer subset with RV32M multiply subset (`MUL`, `MULH`, `MULHSU`, `MULHU`).
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
| `ALUController` | `rtl/core/ALU_Controller.v` | Decode ALU operation, including RV32M multiply operations when `funct7=0000001` | |
| `ALU` | `rtl/core/ALU.v` | Execute integer ALU and RV32M multiply subset operations | |

## RV32M Multiply Extension

The multiply extension is implemented as an EX-stage combinational ALU extension. It reuses the existing R-type datapath, register file, forwarding path, and write-back path.

| Instruction | Encoding condition | Result |
| --- | --- | --- |
| `MUL` | `opcode=0110011`, `funct7=0000001`, `funct3=000` | low 32 bits of `rs1 * rs2` |
| `MULH` | `opcode=0110011`, `funct7=0000001`, `funct3=001` | high 32 bits of signed x signed product |
| `MULHSU` | `opcode=0110011`, `funct7=0000001`, `funct3=010` | high 32 bits of signed x unsigned product |
| `MULHU` | `opcode=0110011`, `funct7=0000001`, `funct3=011` | high 32 bits of unsigned x unsigned product |

The CSR `misa` value is updated to `0x40001100`, declaring RV32IM support (`I` and `M` bits set).

## Verification Checklist

- [ ] Basic arithmetic and logic instructions
- [ ] Load/store instructions
- [ ] Branch and jump instructions
- [ ] Pipeline stall and flush behavior
- [ ] MMIO and UART output
- [x] RV32M multiply subset reference-program generation
- [ ] RV32M multiply subset Verilog simulation
- [ ] FPGA synthesis
- [ ] FPGA implementation/timing
- [ ] Board-level validation

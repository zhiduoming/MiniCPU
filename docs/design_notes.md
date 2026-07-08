# Design Notes

## System Overview

- ISA target:
- Pipeline stages:
- Memory map:
- MMIO devices:
- FPGA board:

## Key Modules

| Module | File | Responsibility | Owner |
| --- | --- | --- | --- |
| `RV32I46F5SPMMIOSoCTOP` | `rtl/top/46F5SP_MMIO_SoC_TOP.v` | FPGA board integration | |
| `RV32I46F5SPMMIO` | `rtl/top/RV32I46F_5SP_MMIO.v` | CPU system top | |
| `ControlUnit` | `rtl/core/Control_Unit.v` | Instruction control signals | |
| `HazardUnit` | `rtl/core/Hazard_Unit.v` | Stall and flush control | |
| `ForwardUnit` | `rtl/core/Forward_Unit.v` | Data forwarding | |
| `InstructionMemory` | `rtl/memory/Instruction_Memory.v` | ROM instruction fetch | |

## Verification Checklist

- [ ] Basic arithmetic and logic instructions
- [ ] Load/store instructions
- [ ] Branch and jump instructions
- [ ] Pipeline stall and flush behavior
- [ ] MMIO and UART output
- [ ] FPGA synthesis
- [ ] FPGA implementation/timing
- [ ] Board-level validation


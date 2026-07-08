# RV32I Five-Stage Pipeline CPU Course Project

This repository contains a Verilog HDL course project for an RV32I-based CPU system with pipeline, MMIO, UART, memory, and FPGA top-level integration.

## Project Layout

```text
.
├─ rtl/
│  ├─ core/       # CPU datapath, control, hazard, forwarding, CSR, trap logic
│  ├─ pipeline/   # IF/ID, ID/EX, EX/MEM, MEM/WB pipeline registers
│  ├─ memory/     # instruction/data memory and instruction cache
│  ├─ mmio/       # board buttons, MMIO interface, debug UART controller
│  ├─ uart/       # UART transmitter
│  └─ top/        # CPU top and FPGA SoC top
├─ include/       # Verilog macro/header files
├─ sim/           # testbenches
├─ mem/           # ROM/RAM initialization files
├─ constraints/   # FPGA constraint files
├─ scripts/       # filelists and Vivado helper scripts
└─ docs/          # report notes, debug log, AI usage, team contribution notes
```

## Main Entry Points

- FPGA top: `rtl/top/46F5SP_MMIO_SoC_TOP.v`, module `RV32I46F5SPMMIOSoCTOP`
- CPU top: `rtl/top/RV32I46F_5SP_MMIO.v`, module `RV32I46F5SPMMIO`
- Smoke testbench: `sim/tb_cpu_smoke.v`
- ROM initialization: `mem/rom_init.mem`
- FPGA constraints: `constraints/minisys_fight_constraint.xdc`

## Build Notes

All RTL files use short `include` names such as `opcode.vh`, so the HDL tool must add `include/` to the Verilog include path.

For Vivado, open or create a project and run:

```tcl
source scripts/vivado_import.tcl
```

For command-line simulators, use the filelists:

```text
scripts/rtl_files.f
scripts/sim_files.f
```

The instruction memory defaults to `mem/rom_init.mem` through the `ROM_INIT_FILE` parameter. Run simulation from the repository root unless overriding this parameter.

## Team Workflow

1. Pull the latest code before editing.
2. Work on a feature branch for each module or bug fix.
3. Keep commits small and describe the hardware behavior changed.
4. Update `docs/debug_log.md` when debugging, especially for synthesis, timing, board validation, and AI/open-source assisted work.
5. Update `docs/division_of_work.md` before course acceptance.


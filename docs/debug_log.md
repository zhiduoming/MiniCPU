# Debug Log

Record debugging steps for course acceptance. Include AI/open-source assisted debugging when applicable.

| Date | Area | Symptom | Cause | Fix | Evidence | Owner |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-07-08 | Project structure | Source files were all in the project root | No repository layout yet | Split files into rtl/include/sim/mem/constraints/docs/scripts | Directory structure checked | |
| 2026-07-09 | RV32M multiply extension | R-type `funct7=0000001` instructions would be decoded as existing RV32I ALU operations | ALU control only inspected `funct7[5]`, which is enough for ADD/SUB and SRL/SRA but not for M-extension decode | Expanded ALU op encoding to 5 bits, passed full `funct7` into `ALUController`, added `MUL/MULH/MULHSU/MULHU` execution in `ALU`, updated `misa` to RV32IM, and regenerated `mem/program.hex` with Test 17 | `python3 scripts/gen_program.py mem/program.hex` prints `Result: PASS`; Icarus `tb_selfcheck` prints `RESULT: PASS (OK)` | |
| 2026-07-09 | Icarus Verilog compatibility | `iverilog` failed to elaborate `Hazard_Unit.v` because `store_hazard_mem` and `store_hazard_wb` referenced hazard wires before their declarations | Icarus is stricter about declaration-before-use than the existing source ordering | Moved store hazard assignments after `mem_hazard_rs2` and `wb_hazard_rs2` declarations without changing the Boolean logic | `iverilog -I include -g2012 -s tb_selfcheck -o sim.vvp -f scripts/rtl_files.f sim/tb_selfcheck.v` compiles; `vvp sim.vvp` passes | |

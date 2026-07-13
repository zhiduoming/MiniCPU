# RV32IM CPU — 测试体系与修复记录

> 版本基线文档。记录当前仓库源码的测试方式、测试用例，以及历次关键修复，便于版本管理与回归定位。

---

## 1. 源码与工程的对应关系

- **唯一真源（source of truth）**：本 Git 仓库 `E:/Code/cpu`，远程仓库为 `https://github.com/zhiduoming/MiniCPU.git`。
- **RTL 源码**：`rtl/` 目录。
- **头文件**：`include/` 目录，Vivado 需要加入 Verilog include path。
- **程序镜像**：`mem/program.hex` 是主自检程序，`mem/csr_test.hex` 是 CSR RAW 专测程序，`mem/smoke.hex` 是 JAL 冒烟测试程序。
- **Vivado 工程**：建议通过 `scripts/vivado_import.tcl` 或 `scripts/vivado_refresh_project.tcl` 导入/刷新，不再手动维护 Vivado 工程副本。

---

## 2. 测试体系（仿真）

仿真器：Icarus Verilog（`iverilog` / `vvp`），位于 `D:/iverilog/bin/`。
所有 testbench 实例化顶层 `RV32I46F5SPMMIO`，通过 MMIO UART 输出判定结果。

### 2.1 一键运行（主自检）

仓库中的 `scripts/sim_files.f` 默认选择主自检 testbench。若本机已安装 Icarus Verilog 且命令在 `PATH` 中，可在仓库根目录运行等价命令：

```bat
iverilog -I include -g2012 -s tb_selfcheck -o sim.vvp -f scripts/sim_files.f
vvp sim.vvp
```

结果写入 `sim_result.txt`：
- `RESULT: PASS (OK)` —— 通过
- `RESULT: FAIL at test id 'xx'` —— 第 xx 号测试失败
- `RESULT: UNKNOWN` —— 非 OK/FAIL（通常是 PC 跑飞、未走到 print_ok/fail）

### 2.2 测试台一览

| Testbench | 程序源 | 作用 |
|-----------|--------|------|
| `tb_selfcheck.v` | `program.hex`（`gen_program.py` 生成） | **主自检**：18 项 ISA+CSR+RV32M 乘除法测试，UART 输出 `OK` 即全过 |
| `tb_m_ext.v` | `m_ext_test.hex`（`gen_m_ext_test.py` 生成） | **RV32M 专项测试**：只覆盖 MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU 与关键边界 |
| `tb_csr.v` | `csr_test.hex`（`gen_csr_test.py` 生成） | **聚焦 CSR 写后读（RAW）**：线性无分支程序，专测 CSRRW→CSRRS 回读是否为写后值（Test 16b 场景） |
| `tb_cpu_smoke.v` | `smoke.hex` | JAL/跳转冒烟测试 |
| `tb_min.v` | —（空跑） | 最小可达性测试（`MIN_DISPLAY reached`） |

### 2.3 主自检 18 项（`gen_program.py` 内 `ASM`）

| # | 测试内容 | 关键指令 |
|---|----------|----------|
| 1 | ADDI / ADD | ADDI, ADD |
| 2 | SUB | SUB |
| 3 | XOR | XOR |
| 4 | OR | OR |
| 5 | AND | AND |
| 6 | SLT（有符号） | SLT |
| 7 | SLTU（无符号） | SLTU |
| 8 | SLL | SLL |
| 9 | SRL | SRL |
| 10 | SW / LW（访存） | SW, LW |
| 11 | 条件分支 TAKEN（前向跳） | BEQ 前向 |
| 12 | JAL（带链接）+ JALR 返回 | JAL, JALR |
| 13 | 后向分支（循环 countdown） | BNE 后向循环 |
| 14 | SB/LB/LBU/SH/LH/LHU（字节/半字） | 全部访存变体 |
| 15 | SRA / SRAI（算术右移，保符号） | SRA, SRAI, SRLI 对照 |
| 16 | **CSR 指令** | 见下 |
| 17 | **RV32M 乘法指令** | MUL, MULH, MULHSU, MULHU |
| 18 | **RV32M 除法/取余指令** | DIV, DIVU, REM, REMU |

**Test 16 子项**：
- 16a：只读 machine-info CSR（`mvendorid/marchid/mimpid/mhartid/mstatus/misa`）
- 16b：可写 `mtvec` 的写后回读（CSRRW → CSRRS 读回写后值）
- 16c：原子置位/清零（CSRRS / CSRRC）
- 16d：立即数 CSR 变体（CSRRWI / CSRRSI / CSRRCI，zimm 0..31）
- 16e：`mcycle` / `minstret` 单调递增计数

**Test 17 子项**：
- `MUL`：验证低 32 位乘积，例如 `7 * 6 = 42`
- `MULH`：验证有符号乘有符号的高 32 位，例如 `-2 * 3`
- `MULHSU`：验证有符号乘无符号的高 32 位，例如 `-2 * 3`
- `MULHU`：验证无符号乘无符号的高 32 位，例如 `0xFFFFFFFF * 2`

**Test 18 子项**：
- `DIV` / `REM`：验证有符号除法向 0 截断，例如 `-21 / 4 = -5`、`-21 % 4 = -1`
- `DIVU` / `REMU`：验证无符号除法，例如 `0xFFFFFFFF / 2 = 0x7FFFFFFF`、余数为 `1`
- 除数为 0：`DIV/DIVU` 返回 `0xFFFFFFFF`，`REM/REMU` 返回被除数
- 有符号溢出：`0x80000000 / -1` 返回 `0x80000000`，余数返回 `0`

> 失败信息格式：`fail:` 先打印失败测试号 `x26` 的 2 位十六进制，再打印 `FAIL\r\n`。

---

## 3. 历史修复记录

> ### ⚠️ 两个核心缺陷（务必牢记，调试优先排查）
>
> 1. **CSR 写后读（RAW）数据冒险** —— CSR 写指令尚未提交，紧随其后的读指令就采样到旧值（Test 16 失败）。靠 `CSR_File.v` 组合逻辑读 + `Hazard_Unit.v` CSR RAW 停顿 + `EX_csr_read_data` 取边界锁存值共同解决。
> 2. **分支预测立即数符号扩展错误** —— `RV32I46F_5SP_MMIO.v` 的 `IF_imm` 符号扩展少 1 位（`{{19{` 应为 `{{20{`），负偏移后向分支目标最高位被清零，PC 飞进数据区（Test 13 跑飞）。

### 3.1 CSR 写后读（RAW）数据冒险修复（Test 16 通过，已在板子）

解决 CSR 写后紧接着读同一 CSR 读到旧值的问题。涉及改动（均于本次基线前完成、且板子已验证 OK）：

- **`CSR_File.v`**：`csr_read_out` 改为**组合逻辑**（`assign csr_read_out = csr_read_data`），读采样当前 CSR 值而非延迟一拍的锁存值。
- **`Control_Unit.v`**：`pc_stall` 不再包含 `!csr_ready`（避免其每周期振荡导致 PC 卡死）；新增 `rs1` 输入（用于 CSRRWI/CSI 的 zimm）。
- **`EX_MEM_Register.v`**：新增 `bubble` 输入，用于抑制 CSR 写被重复提交。
- **`Hazard_Unit.v`**：新增 **CSR RAW 停顿**（shift-register 跟踪在途 CSR 写，读到写后值才放行 reader）；`csr_bubble` 仅在 `EX_csr_write_enable` 时注入 NOP，避免误删合法间隔指令。
- **`RV32I46F_5SP_MMIO.v`**：接线 `hazard_unit.csr_bubble → EX_MEM.bubble`；CSR 运算的 ALU 源由 `csr_forward_data` 改为 **`EX_csr_read_data`**（ID→EX 边界锁存的写前值，RAW 停顿保证其为写后值）。

### 3.2 分支预测立即数符号扩展错误修复（本次回归，2026-07-09）

**现象**：`tb_selfcheck` 报 `RESULT: UNKNOWN`，PC 在 Test 13（后向循环）飞入数据区 `0x800000xx`；但板子（旧 bitstream）仍输出 `OK`。

**根因（唯一回归点）**：`RV32I46F_5SP_MMIO.v` 中分支预测用的 IF 阶段立即数**符号扩展错误**（少 1 位）：

```verilog
// 错误（导致负偏移后向分支目标最高位被清零 → PC 飞进数据区）
assign IF_imm = {{19{instruction[31]}}, instruction[7], instruction[30:25], instruction[11:8], 1'b0};
// 正确
assign IF_imm = {{20{instruction[31]}}, instruction[7], instruction[30:25], instruction[11:8], 1'b0};
```

少 1 位符号位 → 32 位立即数 bit31 被补 0；对**负偏移后向分支**，`branch_target = IF_pc + IF_imm` 算出错误正地址 → 跑飞。该 typo 在板子刷出 OK **之后**才被误改进工作区，故板子（旧 bitstream）照常 OK，仿真（磁盘最新源码）才挂。

**附带纠正**：之前误判 `Hazard_Unit.v` 的 `EX_jump` 块（`ID_EX_flush = 1'b1`）为 bug 并将其删除，是**错误判断**。板子正是用带该 flush 的版本跑通的。已将其**恢复**：

```verilog
if (EX_jump) begin
    IF_ID_flush = 1'b1;
    ID_EX_flush = 1'b1;
end
```

**注意**：`Immediate_Generator.v` 第 22 行 B-type 的 `{{19{raw_imm[11]}}, raw_imm[11:0], 1'b0}` 是**正确的**（其 `raw_imm[11:0]` 已在译码阶段打包好 12 位含符号位，19+12+1=32），且与板子一致，**不要改动**。

---

## 4. 原 RV32I 基线状态

- `tb_selfcheck` 结果：**`RESULT: PASS (OK)`**
- 板子串口输出：**`OK`**（单步 dump 末尾停在 `0x3AC` 即 `print_ok` 收尾地址；`BBBBBBBB` 是数据存储器 `0x80000000` 区初始化读回，非取指）
- 当前 C 盘源码已与"板子当初综合用的源码"一致，**可安全重新综合**。

### 4.1 `feat/multiply` 分支状态（2026-07-09）

- 新增完整 RV32M 乘除法扩展：`MUL`、`MULH`、`MULHSU`、`MULHU`、`DIV`、`DIVU`、`REM`、`REMU`。
- `misa` 从 `0x40000100` 更新为 `0x40001100`，声明 RV32IM。
- `scripts/gen_program.py mem/program.hex` 的参考模型输出：`Result: PASS`。
- Windows/Vivado 上板验证：主自检最终通过，Tera Term 输出 `OK`。
- 注意：当前板级顶层默认使用 10 MHz 系统时钟，以保证单周期组合 `DIV/REM` 有足够时序余量；串口仍为 115200 8N1。

### 4.2 RV32M 上板调试记录（2026-07-09）

**现象**：烧录后 Tera Term 曾输出：

```text
ID=12 ACT=F6002001 EXP=FFFFFFFB FAIL
```

其中 `ID=12` 是十六进制，等于十进制 18，对应主自检 Test 18（RV32M 除法/取余）。失败点是：

```asm
ADDI  x1, x0, -21
ADDI  x2, x0, 4
DIV   x3, x1, x2
ADDI  x9, x0, -5
BNE   x3, x9, fail
```

期望 `-21 / 4 = -5`，即 `0xFFFFFFFB`，但板上实际读到 `0xF6002001`。

**定位**：

- 仿真和 Python 参考模型均通过，说明测试程序和功能模型本身正确。
- 失败只出现在 FPGA 上板运行。
- Vivado timing report 曾显示 `There are no user specified timing constraints.`，说明此前工程缺少明确时钟约束。
- `ALU.v` 中 `DIV/REM` 使用单周期组合 `/` 和 `%`，在较高板级系统时钟下容易成为长组合路径。

**修复 / 规避**：

- 在 `constraints/minisys_fight_constraint.xdc` 中加入输入 100 MHz 时钟和板级 `clk_sys` 派生时钟约束。
- 将 `rtl/top/46F5SP_MMIO_SoC_TOP.v` 的板级系统时钟降为 10 MHz，用于课程验收和功能演示。
- 将 `rtl/uart/UART_TX.v` 的波特率分频改为参数化，系统时钟改变后串口助手仍配置为 115200 8N1。

**证据**：

- 重新综合、实现、生成 bitstream 并烧录后，Tera Term 最新输出为：

```text
OK
```

说明主自检完整通过，包括基础 RV32I、访存、分支跳转、CSR、RV32M 乘法和 RV32M 除法/取余。

**后续改进建议**：

- 当前 10 MHz 是低风险上板验证方案。若后续需要提高频率，应将 `DIV/REM` 改为多周期除法单元，并给流水线增加 stall/ready 控制，而不是继续依赖单周期组合除法。

---

## 5. 更新 Vivado / 重新综合步骤

1. 在 Vivado 中打开工程。
2. 在 Tcl Console 中执行：`source E:/Code/cpu/scripts/vivado_refresh_project.tcl`。
3. 重新 Run Synthesis → Implementation → Generate Bitstream。
4. 烧录后串口应收到 `OK`。

> 不要手动维护散落的 Vivado 源码副本；应以 Git 仓库中的源码为准。

---

## 6. 待办 / 建议

- [ ] 将本次基线（`IF_imm` 改回 `20` + `Hazard_Unit` 恢复 + 此前的 CSR 修复）`git commit`，留可重建的干净基线。
- [ ] 后续任何 `.v` 改动后，先跑 `run_sim.bat` 确认 `RESULT: PASS (OK)` 再烧板。

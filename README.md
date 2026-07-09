# MiniCPU - RV32IM 五级流水 CPU 课设

本仓库是项目式课程阶段二的 Verilog HDL 处理器设计工程，目标是在 FPGA 平台上实现一个基于 RV32I 子集并扩展 RV32M 乘除法指令的五级流水 CPU，并集成存储器、MMIO、UART、板级顶层、仿真文件和约束文件。

当前工程重点包含：

- RV32I 指令译码、控制、ALU、寄存器堆和立即数生成
- RV32M 乘除法扩展：`MUL`、`MULH`、`MULHSU`、`MULHU`、`DIV`、`DIVU`、`REM`、`REMU`
- IF/ID、ID/EX、EX/MEM、MEM/WB 五级流水寄存器
- 数据前递、暂停、冲刷、分支/跳转处理
- CSR、异常/陷入控制相关模块
- 指令存储器、数据存储器和初始化文件
- MMIO、UART 输出和 FPGA 板级顶层
- Vivado 导入脚本、仿真 filelist 和课设过程文档模板

## 目录结构

```text
.
|-- rtl/
|   |-- core/       # CPU 核心逻辑：数据通路、控制、冒险、前递、CSR、Trap 等
|   |-- pipeline/   # 五级流水寄存器
|   |-- memory/     # 指令/数据存储器和指令缓存相关模块
|   |-- mmio/       # MMIO、按键控制、调试 UART 控制
|   |-- uart/       # UART 发送模块
|   `-- top/        # CPU 顶层和 FPGA SoC 顶层
|-- include/        # Verilog 宏定义和头文件
|-- sim/            # 仿真 testbench
|-- mem/            # ROM/RAM 初始化文件
|-- constraints/    # FPGA 约束文件
|-- scripts/        # Vivado 导入脚本和编译文件列表
`-- docs/           # 设计说明、调试日志、AI 使用记录、分工说明
```

## 主要入口

| 用途 | 文件 | 模块名 |
| --- | --- | --- |
| FPGA 板级顶层 | `rtl/top/46F5SP_MMIO_SoC_TOP.v` | `RV32I46F5SPMMIOSoCTOP` |
| CPU 系统顶层 | `rtl/top/RV32I46F_5SP_MMIO.v` | `RV32I46F5SPMMIO` |
| 主自检 testbench | `sim/tb_selfcheck.v` | `tb_selfcheck` |
| CSR 专项 testbench | `sim/tb_csr.v` | `tb_csr` |
| JAL 冒烟测试 testbench | `sim/tb_cpu_smoke.v` | `tb_cpu_smoke` |
| 默认 ROM 初始化 | `mem/program.hex` | - |
| FPGA 约束 | `constraints/minisys_fight_constraint.xdc` | - |

## Vivado 使用方式

所有 RTL 文件中的 `` `include `` 都使用短文件名，例如：

```verilog
`include "opcode.vh"
```

因此 Vivado 工程中必须把 `include/` 加入 Verilog include path。

推荐方式是在 Vivado 中新建或打开工程后，在 Tcl Console 执行：

```tcl
source scripts/vivado_import.tcl
```

该脚本会自动导入：

- `rtl/` 下的全部设计文件
- `include/` 作为头文件搜索路径
- `sim/` 下的 testbench，默认仿真顶层为 `tb_selfcheck`
- `constraints/minisys_fight_constraint.xdc` 作为约束文件
- `mem/` 下的初始化文件

## 仿真说明

命令行仿真工具可以参考：

```text
scripts/rtl_files.f
scripts/sim_files.f
```

如果本机已安装 Icarus Verilog，并且 `iverilog`/`vvp` 已加入 `PATH`，可在仓库根目录运行：

```powershell
scripts\run_selfcheck.bat
```

指令存储器 `InstructionMemory` 通过参数 `ROM_INIT_FILE` 指定初始化文件，默认文件名为：

```text
program.hex
```

该文件在仓库中的位置是 `mem/program.hex`，用于主自检。当前主自检程序包含原 RV32I/CSR 测试以及 RV32M 乘除法扩展测试。另有 `mem/csr_test.hex` 用于 CSR RAW 专项测试，`mem/smoke.hex` 用于 JAL 冒烟测试。Vivado 工程会把这些 memory 初始化文件加入项目；命令行仿真时 testbench 会通过 `ROM_INIT_FILE` 参数选择对应文件。

## 课设文档

`docs/` 目录用于整理验收和答辩材料：

- `docs/design_notes.md`：系统设计说明和模块职责
- `docs/debug_log.md`：调试日志，记录问题、原因、修改和验证证据
- `docs/ai_usage.md`：AI/开源参考使用记录
- `docs/division_of_work.md`：小组成员分工和贡献说明

这些文件需要在开发过程中持续更新，尤其是综合、时序、上板、UART/MMIO 调试以及 AI 辅助修改的记录。

## 协作流程

建议小组按下面方式协作：

1. 每次开始修改前先执行 `git pull`。
2. 每个功能或 bug fix 单独开分支。
3. 提交时说明修改的硬件行为，例如“修复 JAL 后继指令 flush”。
4. 修改 RTL 后同步更新相关仿真、调试日志或设计说明。
5. 合并前至少确认 Vivado 能够正常导入工程。

常用命令：

```powershell
git status
git pull
git checkout -b feature/your-task
git add .
git commit -m "描述本次修改"
git push -u origin feature/your-task
```

## 当前注意事项

- 当前仓库只保存源代码、约束、初始化文件和文档模板，不提交 Vivado 自动生成目录。
- Vivado 生成的 `.runs/`、`.sim/`、`.cache/`、`.xpr` 等文件已在 `.gitignore` 中忽略。
- 如果更换主自检 ROM 程序，请更新 `mem/program.hex`，或在实例化 `RV32I46F5SPMMIO` / `InstructionMemory` 时覆盖 `ROM_INIT_FILE` 参数。
- 如果新增 `.v` 文件，需要同步更新 `scripts/rtl_files.f` 和 `scripts/vivado_import.tcl`。

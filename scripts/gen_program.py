#!/usr/bin/env python3
# Generate program.hex: a self-test RISC-V program for the RV32IM CPU.
# Tests arithmetic, memory, CSR, and multiply/divide extension instructions; prints
# "OK\r\n" on success, "FAIL\r\n" on any mismatch.
import sys

OPC_R=0x33; OPC_I=0x13; OPC_L=0x03; OPC_S=0x23; OPC_B=0x63; OPC_LUI=0x37; OPC_JAL=0x6F; OPC_JALR=0x67; OPC_SYS=0x73

def reg(name):
    name=name.lower().strip()
    if name in ('x0','zero'): return 0
    assert name[0]=='x', name
    return int(name[1:])

def asm_R(funct3,funct7,rd,rs1,rs2):
    return (funct7<<25)|(rs2<<20)|(rs1<<15)|(funct3<<12)|(rd<<7)|OPC_R
def asm_I(funct3,rd,rs1,imm):
    chk_imm12(imm)
    imm&=0xFFF
    return (imm<<20)|(rs1<<15)|(funct3<<12)|(rd<<7)|OPC_I

def chk_imm12(imm):
    # 12-bit signed immediate range for ADDI / loads / stores
    if imm < -2048 or imm > 2047:
        raise Exception("immediate %d out of 12-bit signed range (-2048..2047)" % imm)
def asm_S(funct3,rs1,rs2,imm):
    imm&=0xFFF
    return ((imm&0x1F)<<7)|(funct3<<12)|(rs1<<15)|(rs2<<20)|((imm&0xFE0)<<25)|OPC_S
def asm_B(funct3,rs1,rs2,imm):
    i12=(imm>>12)&1; i11=(imm>>11)&1; i10_5=(imm>>5)&0x3F; i4_1=(imm>>1)&0xF
    return (i12<<31)|(i10_5<<25)|(rs2<<20)|(rs1<<15)|(funct3<<12)|(i4_1<<8)|(i11<<7)|OPC_B
def asm_U(rd,imm20):
    return (imm20<<12)|(rd<<7)|OPC_LUI
def asm_J(rd,imm):
    i20=(imm>>20)&1; i10_1=(imm>>1)&0x3FF; i11=(imm>>11)&1; i19_12=(imm>>12)&0xFF
    return (i20<<31)|(i10_1<<21)|(i11<<20)|(i19_12<<12)|(rd<<7)|OPC_JAL

ASM = r"""
    LUI   x30, 0x10010        # UART TX base = 0x10010000
    # ---- Test 1: ADDI / ADD ----
    ADDI  x26, x0, 1
    ADDI  x1, x0, 10
    ADDI  x2, x0, 3
    ADD   x3, x1, x2
    ADDI  x9, x0, 13
    BNE   x3, x9, fail
    # ---- Test 2: SUB ----
    ADDI  x26, x0, 2
    SUB   x4, x1, x2
    ADDI  x9, x0, 7
    BNE   x4, x9, fail
    # ---- Test 3: XOR ----
    ADDI  x26, x0, 3
    XOR   x5, x1, x2
    ADDI  x9, x0, 9
    BNE   x5, x9, fail
    # ---- Test 4: OR ----
    ADDI  x26, x0, 4
    OR    x6, x1, x2
    ADDI  x9, x0, 11
    BNE   x6, x9, fail
    # ---- Test 5: AND ----
    ADDI  x26, x0, 5
    AND   x7, x1, x2
    ADDI  x9, x0, 2
    BNE   x7, x9, fail
    # ---- Test 6: SLT (signed) ----
    ADDI  x26, x0, 6
    SLT   x10, x1, x2
    BNE   x10, x0, fail
    # ---- Test 7: SLTU ----
    ADDI  x26, x0, 7
    SLTU  x11, x2, x1
    ADDI  x9, x0, 1
    BNE   x11, x9, fail
    # ---- Test 8: SLL ----
    ADDI  x26, x0, 8
    ADDI  x12, x0, 1
    SLL   x13, x1, x12
    ADDI  x9, x0, 20
    BNE   x13, x9, fail
    # ---- Test 9: SRL ----
    ADDI  x26, x0, 9
    SRL   x14, x13, x12
    ADDI  x9, x0, 10
    BNE   x14, x9, fail
    # ---- Test 10: SW / LW (memory) ----
    ADDI  x26, x0, 10
    LUI   x16, 0x10000        # RAM base 0x10000000
    SW    x1, 0(x16)
    ADDI  x0, x0, 0           # NOP (hazard gap)
    LW    x17, 0(x16)
    ADDI  x9, x0, 10
    BNE   x17, x9, fail
    # ---- Test 11: conditional branch TAKEN (forward jump) ----
    ADDI  x26, x0, 11
    ADDI  x21, x0, 5
    ADDI  x22, x0, 5
    BEQ   x21, x22, fwd_taken
    ADDI  x23, x0, 0x55        # MUST be skipped by the taken branch
    JAL   x0, fail
fwd_taken:
    ADDI  x9, x0, 0
    BNE   x23, x9, fail        # x23 must stay 0 -> branch was taken
    # ---- Test 12: JAL with link + JALR return ----
    ADDI  x26, x0, 12
    JAL   x1, sub_routine      # x1 = return address (link)
    ADDI  x9, x0, 0xAB
    BNE   x24, x9, fail        # subroutine must have set x24 = 0xAB
    # ---- Test 13: backward branch (loop countdown) ----
    ADDI  x26, x0, 13
    ADDI  x25, x0, 4
loop_top:
    ADDI  x25, x25, -1
    BNE   x25, x0, loop_top
    ADDI  x9, x0, 0
    BNE   x25, x9, fail
    # ---- Test 14: SB/LB/LBU/SH/LH/LHU ----
    ADDI  x26, x0, 14
    LUI   x16, 0x10000          # RAM base 0x10000000
    LUI   x14, 0x12345
    ADDI  x14, x14, 0x678       # x14 = 0x12345678
    SW    x14, 16(x16)          # store word
    ADDI  x0, x0, 0             # NOP (hazard gap)
    LB    x15, 16(x16)          # byte0 = 0x78 (positive)
    ADDI  x9, x0, 0x78
    BNE   x15, x9, fail
    LB    x15, 19(x16)          # byte3 = 0x12 (positive)
    ADDI  x9, x0, 0x12
    BNE   x15, x9, fail
    LBU   x15, 18(x16)          # byte2 = 0x34 zero-extended
    ADDI  x9, x0, 0x34
    BNE   x15, x9, fail
    ADDI  x14, x0, 0x80
    SB    x14, 20(x16)          # store negative byte 0x80
    ADDI  x0, x0, 0             # NOP
    LB    x15, 20(x16)          # sign-ext -> 0xFFFFFF80 (=-128)
    ADDI  x9, x0, -128
    BNE   x15, x9, fail
    LBU   x15, 20(x16)          # zero-ext -> 0x00000080
    ADDI  x9, x0, 0x80
    BNE   x15, x9, fail
    LUI   x14, 0x00008          # x14 = 0x00008000 (negative as halfword)
    SH    x14, 24(x16)          # store negative halfword 0x8000
    ADDI  x0, x0, 0             # NOP
    LH    x15, 24(x16)          # sign-ext -> 0xFFFF8000
    LUI   x9, 0xFFFF8
    BNE   x15, x9, fail
    LHU   x15, 24(x16)          # zero-ext -> 0x00008000
    LUI   x9, 0x00008
    BNE   x15, x9, fail
    LUI   x14, 0x00001
    ADDI  x14, x14, 0x234       # x14 = 0x00001234
    SH    x14, 26(x16)          # store positive halfword 0x1234
    ADDI  x0, x0, 0             # NOP
    LHU   x15, 26(x16)          # 0x00001234
    LUI   x9, 0x00001
    ADDI  x9, x9, 0x234
    BNE   x15, x9, fail
    # ---- Test 15: SRA / SRAI (arithmetic right shift, sign preserving) ----
    ADDI  x26, x0, 15
    ADDI  x14, x0, -8           # 0xFFFFFFF8
    SRAI  x15, x14, 1           # -8 >> 1 = -4 = 0xFFFFFFFC
    ADDI  x9, x0, -4
    BNE   x15, x9, fail
    SRAI  x15, x14, 4           # -8 >> 4 = -1 = 0xFFFFFFFF
    ADDI  x9, x0, -1
    BNE   x15, x9, fail
    ADDI  x18, x0, 3
    SRA   x15, x14, x18         # -8 >> 3 = -1 = 0xFFFFFFFF
    ADDI  x9, x0, -1
    BNE   x15, x9, fail
    ADDI  x14, x0, 0x80
    SRA   x15, x14, x18         # 0x80 >> 3 = 0x10 (positive == SRL)
    ADDI  x9, x0, 0x10
    BNE   x15, x9, fail
    # SRA vs SRL on a negative value: 0x80000000 has bit31 set
    LUI   x14, 0x80000          # 0x80000000
    ADDI  x18, x0, 4
    SRLI  x15, x14, 4           # logical -> 0x08000000 (zero-filled)
    LUI   x9, 0x08000
    BNE   x15, x9, fail
    SRA   x15, x14, x18         # arithmetic -> 0xF8000000 (sign-extended)
    LUI   x9, 0xF8000
    BNE   x15, x9, fail
    # ---- Test 16: CSR instructions ----
    ADDI  x26, x0, 16
    # 16a. read-only machine-info CSRs
    CSRRS  x15, 0xF11, x0     # mvendorid = 0x52564B43
    LUI    x9, 0x52564
    ADDI   x9, x9, 0x700
    ADDI   x9, x9, 0x443
    BNE    x15, x9, fail
    CSRRS  x15, 0xF12, x0     # marchid = 0x34365335
    LUI    x9, 0x34365
    ADDI   x9, x9, 0x335
    BNE    x15, x9, fail
    CSRRS  x15, 0xF13, x0     # mimpid = 0x34364931
    LUI    x9, 0x34364
    ADDI   x9, x9, 0x700
    ADDI   x9, x9, 0x231
    BNE    x15, x9, fail
    CSRRS  x15, 0xF14, x0     # mhartid = 0x524B4330
    LUI    x9, 0x524B4
    ADDI   x9, x9, 0x330
    BNE    x15, x9, fail
    CSRRS  x15, 0x300, x0     # mstatus = 0x00001800
    LUI    x9, 0x00002
    ADDI   x9, x9, -2048      # 0x2000 - 0x800 = 0x1800
    BNE    x15, x9, fail
    CSRRS  x15, 0x301, x0     # misa = 0x40001100 (RV32IM)
    LUI    x9, 0x40001
    ADDI   x9, x9, 0x100
    BNE    x15, x9, fail
    # 16b. writable CSR: mtvec default then write / read-back
    # NOTE: back-to-back CSR write->read is now handled correctly by the
    # hardware (CSR RAW hazard stall in Hazard_Unit), so no NOPs are needed.
    CSRRS  x15, 0x305, x0     # default mtvec = 0x00001000
    LUI    x9, 0x00001
    BNE    x15, x9, fail
    LUI    x14, 0x12345
    ADDI   x14, x14, 0x678    # x14 = 0x12345678
    CSRRW  x15, 0x305, x14    # mtvec <- 0x12345678, x15 <- old (0x1000)
    LUI    x9, 0x00001
    BNE    x15, x9, fail
    CSRRS  x15, 0x305, x0     # read back -> 0x12345678
    LUI    x9, 0x12345
    ADDI   x9, x9, 0x678
    BNE    x15, x9, fail
    # 16c. atomic set / clear (CSRRS / CSRRC)
    ADDI   x14, x0, 0x1
    CSRRS  x15, 0x305, x14    # set bit0 -> 0x12345679, x15 <- 0x12345678
    LUI    x9, 0x12345
    ADDI   x9, x9, 0x678
    BNE    x15, x9, fail
    CSRRS  x15, 0x305, x0     # read -> 0x12345679
    LUI    x9, 0x12345
    ADDI   x9, x9, 0x679
    BNE    x15, x9, fail
    CSRRC  x15, 0x305, x14    # clear bit0 -> 0x12345678, x15 <- 0x12345679
    LUI    x9, 0x12345
    ADDI   x9, x9, 0x679
    BNE    x15, x9, fail
    CSRRS  x15, 0x305, x0     # read -> 0x12345678
    LUI    x9, 0x12345
    ADDI   x9, x9, 0x678
    BNE    x15, x9, fail
    # 16d. immediate CSR variants (zimm must be 0..31)
    CSRRWI x15, 0x1B, 0x305   # mtvec <- 0x1B, x15 <- old (0x12345678)
    LUI    x9, 0x12345
    ADDI   x9, x9, 0x678
    BNE    x15, x9, fail
    CSRRS  x15, 0x305, x0     # read -> 0x1B
    ADDI   x9, x0, 0x1B
    BNE    x15, x9, fail
    CSRRSI x15, 0x04, 0x305   # set bit2 -> 0x1F, x15 <- 0x1B
    ADDI   x9, x0, 0x1B
    BNE    x15, x9, fail
    CSRRS  x15, 0x305, x0     # read -> 0x1F
    ADDI   x9, x0, 0x1F
    BNE    x15, x9, fail
    CSRRCI x15, 0x1F, 0x305   # clear 0x1F -> 0x00, x15 <- 0x1F
    ADDI   x9, x0, 0x1F
    BNE    x15, x9, fail
    CSRRS  x15, 0x305, x0     # read -> 0x00
    BNE    x15, x0, fail
    # 16e. mcycle / minstret are monotonic counters
    CSRRS  x15, 0xB00, x0     # mcycle low
    ADDI   x0, x0, 0
    ADDI   x0, x0, 0
    ADDI   x0, x0, 0
    ADDI   x0, x0, 0
    ADDI   x0, x0, 0
    CSRRS  x16, 0xB00, x0     # mcycle low again
    SUB    x17, x16, x15
    SLTI   x9, x17, 1         # 1 if increase <= 0
    BNE    x9, x0, fail       # require increase > 0
    CSRRS  x15, 0xB02, x0     # minstret low
    ADDI   x0, x0, 0
    ADDI   x0, x0, 0
    ADDI   x0, x0, 0
    ADDI   x0, x0, 0
    ADDI   x0, x0, 0
    CSRRS  x16, 0xB02, x0     # minstret low again
    SUB    x17, x16, x15
    SLTI   x9, x17, 1
    BNE    x9, x0, fail
    # ---- Test 17: RV32M multiply instructions ----
    ADDI  x26, x0, 17
    ADDI  x1, x0, 7
    ADDI  x2, x0, 6
    MUL   x3, x1, x2           # low32(7 * 6) = 42
    ADDI  x9, x0, 42
    BNE   x3, x9, fail
    ADDI  x1, x0, -2
    ADDI  x2, x0, 3
    MULH  x3, x1, x2           # high32(signed -2 * signed 3) = 0xFFFFFFFF
    ADDI  x9, x0, -1
    BNE   x3, x9, fail
    MULHSU x3, x1, x2          # high32(signed -2 * unsigned 3) = 0xFFFFFFFF
    ADDI  x9, x0, -1
    BNE   x3, x9, fail
    ADDI  x1, x0, -1           # unsigned 0xFFFFFFFF
    ADDI  x2, x0, 2
    MULHU x3, x1, x2           # high32(0xFFFFFFFF * 2) = 1
    ADDI  x9, x0, 1
    BNE   x3, x9, fail
    # ---- Test 18: RV32M divide/remainder instructions ----
    ADDI  x26, x0, 18
    ADDI  x1, x0, -21
    ADDI  x2, x0, 4
    DIV   x3, x1, x2           # signed -21 / 4 truncates toward zero -> -5
    ADDI  x9, x0, -5
    BNE   x3, x9, fail
    REM   x3, x1, x2           # signed -21 % 4 -> -1
    ADDI  x9, x0, -1
    BNE   x3, x9, fail
    ADDI  x1, x0, -1           # unsigned 0xFFFFFFFF
    ADDI  x2, x0, 2
    DIVU  x3, x1, x2           # 0xFFFFFFFF / 2 = 0x7FFFFFFF
    LUI   x9, 0x80000
    ADDI  x9, x9, -1
    BNE   x3, x9, fail
    REMU  x3, x1, x2           # 0xFFFFFFFF % 2 = 1
    ADDI  x9, x0, 1
    BNE   x3, x9, fail
    ADDI  x1, x0, 123
    ADDI  x2, x0, 0
    DIV   x3, x1, x2           # divide by zero -> -1
    ADDI  x9, x0, -1
    BNE   x3, x9, fail
    REM   x3, x1, x2           # remainder by zero -> dividend
    ADDI  x9, x0, 123
    BNE   x3, x9, fail
    DIVU  x3, x1, x2           # unsigned divide by zero -> 0xFFFFFFFF
    ADDI  x9, x0, -1
    BNE   x3, x9, fail
    REMU  x3, x1, x2           # unsigned remainder by zero -> dividend
    ADDI  x9, x0, 123
    BNE   x3, x9, fail
    LUI   x1, 0x80000          # signed overflow case: INT_MIN / -1
    ADDI  x2, x0, -1
    DIV   x3, x1, x2           # quotient stays INT_MIN
    LUI   x9, 0x80000
    BNE   x3, x9, fail
    REM   x3, x1, x2           # overflow remainder is 0
    BNE   x3, x0, fail
    # ---- all passed ----
    JAL   x0, print_ok
fail:
    # print failing test id (x26), actual value (x27), and expected value (x28)
    PUTC 0x49                       # 'I'
    PUTC 0x44                       # 'D'
    PUTC 0x3D                       # '='
    SRLI  x20, x26, 4          # high nibble
    ANDI  x20, x20, 0xF
    JAL   x1, put_hex
    ANDI  x20, x26, 0xF        # low nibble
    JAL   x1, put_hex
    PUTC 0x20
    PUTC 0x41                       # 'A'
    PUTC 0x43                       # 'C'
    PUTC 0x54                       # 'T'
    PUTC 0x3D                       # '='
    ADD   x21, x27, x0
    JAL   x1, put_hex32
    PUTC 0x20
    PUTC 0x45                       # 'E'
    PUTC 0x58                       # 'X'
    PUTC 0x50                       # 'P'
    PUTC 0x3D                       # '='
    ADD   x21, x28, x0
    JAL   x1, put_hex32
    PUTC 0x20
    JAL   x0, print_fail_msg
put_hex32:
    ADD   x29, x1, x0
    ADDI  x22, x0, 8
ph32_loop:
    SRLI  x20, x21, 28
    JAL   x1, put_hex
    SLLI  x21, x21, 4
    ADDI  x22, x22, -1
    BNE   x22, x0, ph32_loop
    JALR  x0, 0(x29)
put_hex:
    ADDI  x9, x0, 10
    BLT   x20, x9, ph_num
    ADDI  x20, x20, -10
    ADDI  x20, x20, 0x41       # 'A'..'F'
    JAL   x0, ph_emit
ph_num:
    ADDI  x20, x20, 0x30       # '0'..'9'
ph_emit:
    LW    x31, 4(x30)
    ANDI  x31, x31, 1
    BNE   x31, x0, ph_emit
    SW    x20, 0(x30)
    JALR  x0, 0(x1)            # return to caller
print_fail_msg:
    PUTC 0x46
    PUTC 0x41
    PUTC 0x49
    PUTC 0x4C
    PUTC 0x0D
    PUTC 0x0A
    JAL   x0, done
print_ok:
    PUTC 0x4F
    PUTC 0x4B
    PUTC 0x0D
    PUTC 0x0A
    JAL   x0, done
done:
    JAL   x0, done
sub_routine:
    ADDI  x24, x0, 0xAB
    JALR  x0, 0(x1)            # return to link stored in x1
"""

def parse():
    raw=[]; labels={}
    plc=0
    fail_ctx=0
    for ln in ASM.strip().splitlines():
        ln=ln.split('#')[0].strip()
        if not ln: continue
        if ln.endswith(':'):
            labels[ln[:-1]]=plc*4
            continue
        parts=[p.strip().rstrip(',') for p in ln.split()]
        op=parts[0].upper()
        if op=='PUTC':
            ch=int(parts[1],0)
            raw.append(('ADDI',['x20','x0',str(ch)])); plc+=1
            lbl='.p%d'%plc
            labels[lbl]=plc*4
            raw.append(('LW',['x31','4(x30)'])); plc+=1
            raw.append(('ANDI',['x31','x31','1'])); plc+=1
            raw.append(('BNE',['x31','x0',lbl])); plc+=1
            raw.append(('SW',['x20','0(x30)'])); plc+=1
        elif op=='BNE' and len(parts)==4 and parts[3]=='fail':
            fail_ctx+=1
            fail_lbl='.failctx%d'%fail_ctx
            after_lbl='.after_failctx%d'%fail_ctx
            raw.append(('BNE',[parts[1],parts[2],fail_lbl])); plc+=1
            raw.append(('JAL',['x0',after_lbl])); plc+=1
            labels[fail_lbl]=plc*4
            raw.append(('ADD',['x27',parts[1],'x0'])); plc+=1
            raw.append(('ADD',['x28',parts[2],'x0'])); plc+=1
            raw.append(('JAL',['x0','fail'])); plc+=1
            labels[after_lbl]=plc*4
        else:
            raw.append((op,parts[1:])); plc+=1
    return raw,labels

def encode(raw,labels):
    code=[]
    for idx,(op,args) in enumerate(raw):
        a=pc=idx*4
        if op=='LUI':
            rd=reg(args[0]); imm20=int(args[1],0)
            code.append(asm_U(rd,imm20&0xFFFFF))
        elif op=='ADDI':
            rd=reg(args[0]); rs1=reg(args[1]); imm=int(args[2],0)
            code.append(asm_I(0,rd,rs1,imm))
        elif op=='ADD':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(0,0,rd,rs1,rs2))
        elif op=='SUB':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(0,0x20,rd,rs1,rs2))
        elif op=='XOR':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(4,0,rd,rs1,rs2))
        elif op=='OR':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(6,0,rd,rs1,rs2))
        elif op=='AND':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(7,0,rd,rs1,rs2))
        elif op=='SLT':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(2,0,rd,rs1,rs2))
        elif op=='SLTU':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(3,0,rd,rs1,rs2))
        elif op=='SLL':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(1,0,rd,rs1,rs2))
        elif op=='SRL':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(5,0,rd,rs1,rs2))
        elif op=='SRA':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(5,0x20,rd,rs1,rs2))
        elif op=='MUL':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(0,1,rd,rs1,rs2))
        elif op=='MULH':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(1,1,rd,rs1,rs2))
        elif op=='MULHSU':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(2,1,rd,rs1,rs2))
        elif op=='MULHU':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(3,1,rd,rs1,rs2))
        elif op=='DIV':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(4,1,rd,rs1,rs2))
        elif op=='DIVU':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(5,1,rd,rs1,rs2))
        elif op=='REM':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(6,1,rd,rs1,rs2))
        elif op=='REMU':
            rd=reg(args[0]); rs1=reg(args[1]); rs2=reg(args[2])
            code.append(asm_R(7,1,rd,rs1,rs2))
        elif op=='SLTI':
            rd=reg(args[0]); rs1=reg(args[1]); imm=int(args[2],0)
            code.append(asm_I(2,rd,rs1,imm))
        elif op=='ANDI':
            rd=reg(args[0]); rs1=reg(args[1]); imm=int(args[2],0)
            code.append(asm_I(7,rd,rs1,imm))
        elif op=='XORI':
            rd=reg(args[0]); rs1=reg(args[1]); imm=int(args[2],0)
            code.append(asm_I(4,rd,rs1,imm))
        elif op=='ORI':
            rd=reg(args[0]); rs1=reg(args[1]); imm=int(args[2],0)
            code.append(asm_I(6,rd,rs1,imm))
        elif op=='SLLI':
            rd=reg(args[0]); rs1=reg(args[1]); shamt=int(args[2],0)
            code.append(asm_I(1,rd,rs1,shamt))
        elif op=='SRLI':
            rd=reg(args[0]); rs1=reg(args[1]); shamt=int(args[2],0)
            code.append(asm_I(5,rd,rs1,shamt))
        elif op=='SRAI':
            rd=reg(args[0]); rs1=reg(args[1]); shamt=int(args[2],0)
            code.append(asm_I(5,rd,rs1,shamt|(0x20<<5)))
        elif op in ('LW','LB','LBU','LH','LHU'):
            rd=reg(args[0]); off,rs1=parse_off(args[1])
            chk_imm12(off)
            f3={'LW':2,'LB':0,'LBU':4,'LH':1,'LHU':5}[op]
            code.append((off<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|OPC_L)
        elif op in ('SW','SB','SH'):
            rs2=reg(args[0]); off,rs1=parse_off(args[1])
            chk_imm12(off)
            f3={'SW':2,'SB':0,'SH':1}[op]
            code.append(asm_S(f3,rs1,rs2,off))
        elif op=='BEQ':
            rs1=reg(args[0]); rs2=reg(args[1]); t=labels[args[2]]
            code.append(asm_B(0,rs1,rs2,t-pc))
        elif op=='BNE':
            rs1=reg(args[0]); rs2=reg(args[1]); t=labels[args[2]]
            code.append(asm_B(1,rs1,rs2,t-pc))
        elif op=='BLT':
            rs1=reg(args[0]); rs2=reg(args[1]); t=labels[args[2]]
            code.append(asm_B(4,rs1,rs2,t-pc))
        elif op=='BGE':
            rs1=reg(args[0]); rs2=reg(args[1]); t=labels[args[2]]
            code.append(asm_B(5,rs1,rs2,t-pc))
        elif op=='BLTU':
            rs1=reg(args[0]); rs2=reg(args[1]); t=labels[args[2]]
            code.append(asm_B(6,rs1,rs2,t-pc))
        elif op=='BGEU':
            rs1=reg(args[0]); rs2=reg(args[1]); t=labels[args[2]]
            code.append(asm_B(7,rs1,rs2,t-pc))
        elif op=='JAL':
            rd=reg(args[0]); t=labels[args[1]]
            code.append(asm_J(rd,t-pc))
        elif op=='JALR':
            rd=reg(args[0]); off,rs1=parse_off(args[1])
            off&=0xFFF
            code.append((off<<20)|(rs1<<15)|(0<<12)|(rd<<7)|OPC_JALR)
        elif op in ('CSRRW','CSRRS','CSRRC'):
            rd=reg(args[0]); csr=int(args[1],0); rs=reg(args[2])
            f3={'CSRRW':1,'CSRRS':2,'CSRRC':3}[op]
            code.append((csr<<20)|(rs<<15)|(f3<<12)|(rd<<7)|OPC_SYS)
        elif op in ('CSRRWI','CSRRSI','CSRRCI'):
            rd=reg(args[0]); zimm=int(args[1],0); csr=int(args[2],0)
            if zimm<0 or zimm>31:
                raise Exception("CSR immediate %d out of 5-bit range (0..31)"%zimm)
            f3={'CSRRWI':5,'CSRRSI':6,'CSRRCI':7}[op]
            code.append((csr<<20)|(zimm<<15)|(f3<<12)|(rd<<7)|OPC_SYS)
        else:
            raise Exception("unknown op "+op)
    return code

def parse_off(s):
    import re
    m=re.match(r'(-?\d+)\(x(\d+)\)',s)
    return int(m.group(1)), int(m.group(2))

def simulate(code):
    regs=[0]*32
    def sx(v):
        v&=0xFFFFFFFF
        return v-(1<<32) if v&(1<<31) else v
    def div_trunc_zero(a,b):
        q=abs(a)//abs(b)
        return -q if (a<0) ^ (b<0) else q
    ram={}
    uart=[]
    pc=0
    UART_TX=0x10010000
    trace=[]
    # ---- CSR file model (mirrors CSR_File.v) ----
    csr_state={
        0xF11:0x52564B43, 0xF12:0x34365335, 0xF13:0x34364931, 0xF14:0x524B4330,
        0x300:0x00001800, 0x301:0x40001100,
        0x305:0x00001000, 0x341:0, 0x342:0,
        0xB00:0, 0xB02:0, 0xB80:0, 0xB82:0,   # mcycle / minstret (low & high)
    }
    csr_writable={0x305, 0x341, 0x342}        # only mtvec/mepc/mcause are writable
    mcycle=0; minstret=0
    for _ in range(20000):
        idx=pc>>2
        if idx>=len(code): break
        inst=code[idx]
        opcode=inst&0x7f
        rd=(inst>>7)&0x1f; funct3=(inst>>12)&0x7
        rs1=(inst>>15)&0x1f; rs2=(inst>>20)&0x1f; funct7=(inst>>25)&0x7f
        imm_i=(inst>>20)&0xFFF; imm_i=imm_i-(1<<12) if imm_i&(1<<11) else imm_i
        # mcycle / minstret increment once per instruction (mirrors CSR_File.v)
        mcycle=(mcycle+1)&0xFFFFFFFF; minstret=(minstret+1)&0xFFFFFFFF
        csr_state[0xB00]=mcycle; csr_state[0xB02]=minstret
        csr_state[0xB80]=(mcycle>>16)>>16; csr_state[0xB82]=(minstret>>16)>>16
        if opcode==OPC_LUI:
            regs[rd]=(inst>>12)&0xFFFFF; regs[rd]=(regs[rd]<<12)&0xFFFFFFFF
        elif opcode==OPC_JAL:
            imm=0
            imm|=((inst>>31)&1)<<20; imm|=((inst>>21)&0x3FF)<<1
            imm|=((inst>>20)&1)<<11; imm|=((inst>>12)&0xFF)<<12
            if imm&(1<<20): imm-=(1<<21)
            nxt=(pc+imm)&~1
            if rd!=0: regs[rd]=(pc+4)&0xFFFFFFFF
            pc=nxt; continue
        elif opcode==OPC_JALR:
            target=(regs[rs1]+imm_i)&~1
            if rd!=0: regs[rd]=(pc+4)&0xFFFFFFFF
            pc=target; continue
        elif opcode==OPC_B:
            imm=0
            imm|=((inst>>31)&1)<<12; imm|=((inst>>25)&0x3F)<<5
            imm|=((inst>>8)&0xF)<<1; imm|=((inst>>7)&1)<<11
            if imm&(1<<12): imm-=(1<<13)
            a=sx(regs[rs1]); b=sx(regs[rs2])
            au=regs[rs1]&0xFFFFFFFF; bu=regs[rs2]&0xFFFFFFFF
            take={0:a==b,1:a!=b,4:a<b,5:a>=b,6:au<bu,7:au>=bu}.get(funct3,False)
            pc=(pc+imm) if take else (pc+4); continue
        elif opcode==OPC_L:
            addr=(regs[rs1]+imm_i)&0xFFFFFFFF
            word=ram.get(addr&~3,0)
            if funct3==2:
                val=word
            elif funct3==0:
                b=(word>>((addr&3)*8))&0xFF
                val=b-(1<<8) if b&(1<<7) else b          # LB  sign-extend
            elif funct3==4:
                val=(word>>((addr&3)*8))&0xFF            # LBU zero-extend
            elif funct3==1:
                h=(word>>((addr&2)*8))&0xFFFF
                val=h-(1<<16) if h&(1<<15) else h        # LH  sign-extend
            elif funct3==5:
                val=(word>>((addr&2)*8))&0xFFFF          # LHU zero-extend
            else:
                val=0
            if rd!=0: regs[rd]=val&0xFFFFFFFF
        elif opcode==OPC_S:
            imm_s=((inst>>25)&0x7F)<<5|((inst>>7)&0x1F)
            if imm_s&(1<<11): imm_s-=(1<<12)
            addr=(regs[rs1]+imm_s)&0xFFFFFFFF
            if addr==UART_TX:
                uart.append(regs[rs2]&0xFF)
            else:
                word_addr=addr&~3
                if funct3==2:
                    ram[word_addr]=regs[rs2]&0xFFFFFFFF
                elif funct3==0:                           # SB  single byte
                    shift=(addr&3)*8
                    cur=ram.get(word_addr,0)
                    ram[word_addr]=(cur&~(0xFF<<shift))|((regs[rs2]&0xFF)<<shift)
                elif funct3==1:                           # SH  halfword
                    shift=(addr&2)*8
                    cur=ram.get(word_addr,0)
                    ram[word_addr]=(cur&~(0xFFFF<<shift))|((regs[rs2]&0xFFFF)<<shift)
        elif opcode==OPC_I:
            if funct3==0: regs[rd]=(regs[rs1]+imm_i)&0xFFFFFFFF
            elif funct3==2: regs[rd]=1 if sx(regs[rs1])<imm_i else 0
            elif funct3==3: regs[rd]=1 if (regs[rs1]&0xFFFFFFFF)<(imm_i&0xFFFFFFFF) else 0
            elif funct3==4: regs[rd]=(regs[rs1]^imm_i)&0xFFFFFFFF
            elif funct3==6: regs[rd]=(regs[rs1]|imm_i)&0xFFFFFFFF
            elif funct3==7: regs[rd]=(regs[rs1]&imm_i)&0xFFFFFFFF
            elif funct3==1: regs[rd]=(regs[rs1]<<(imm_i&0x1f))&0xFFFFFFFF
            elif funct3==5:
                if funct7==0x20: regs[rd]=sx(regs[rs1])>>(imm_i&0x1f)
                else: regs[rd]=(regs[rs1]&0xFFFFFFFF)>>(imm_i&0x1f)
                regs[rd]&=0xFFFFFFFF
        elif opcode==OPC_SYS:
            csr_addr=(inst>>20)&0xFFF
            if funct3==0:
                pass  # ECALL/EBREAK: no-op in this model
            else:
                old=csr_state.get(csr_addr,0)
                zimm=(inst>>15)&0x1f
                if funct3 in (1,5):        # CSRRW / CSRRWI -> write = src
                    src = zimm if funct3==5 else regs[rs1]
                    new = src & 0xFFFFFFFF
                    do_write = True
                elif funct3 in (2,6):      # CSRRS / CSRRSI -> write = old | src
                    src = zimm if funct3==6 else regs[rs1]
                    new = (old | src) & 0xFFFFFFFF
                    do_write = (src != 0)
                elif funct3 in (3,7):      # CSRRC / CSRRCI -> write = old & ~src
                    src = zimm if funct3==7 else regs[rs1]
                    new = (old & (~src & 0xFFFFFFFF)) & 0xFFFFFFFF
                    do_write = (src != 0)
                else:
                    new = old; do_write = False
                if do_write and csr_addr in csr_writable:
                    csr_state[csr_addr]=new
                if rd!=0:
                    regs[rd]=old & 0xFFFFFFFF
        elif opcode==OPC_R:
            if funct7==1:
                a_s=sx(regs[rs1]); b_s=sx(regs[rs2])
                a_u=regs[rs1]&0xFFFFFFFF; b_u=regs[rs2]&0xFFFFFFFF
                if funct3==0:
                    regs[rd]=(a_u*b_u)&0xFFFFFFFF
                elif funct3==1:
                    regs[rd]=((a_s*b_s)&0xFFFFFFFFFFFFFFFF)>>32
                elif funct3==2:
                    regs[rd]=((a_s*b_u)&0xFFFFFFFFFFFFFFFF)>>32
                elif funct3==3:
                    regs[rd]=((a_u*b_u)&0xFFFFFFFFFFFFFFFF)>>32
                elif funct3==4:
                    if b_u==0:
                        regs[rd]=0xFFFFFFFF
                    elif a_u==0x80000000 and b_u==0xFFFFFFFF:
                        regs[rd]=0x80000000
                    else:
                        regs[rd]=div_trunc_zero(a_s,b_s)&0xFFFFFFFF
                elif funct3==5:
                    regs[rd]=0xFFFFFFFF if b_u==0 else (a_u//b_u)&0xFFFFFFFF
                elif funct3==6:
                    if b_u==0:
                        regs[rd]=a_u
                    elif a_u==0x80000000 and b_u==0xFFFFFFFF:
                        regs[rd]=0
                    else:
                        regs[rd]=(a_s - div_trunc_zero(a_s,b_s)*b_s)&0xFFFFFFFF
                elif funct3==7:
                    regs[rd]=a_u if b_u==0 else (a_u%b_u)&0xFFFFFFFF
            elif funct3==0 and funct7==0: regs[rd]=(regs[rs1]+regs[rs2])&0xFFFFFFFF
            elif funct3==0 and funct7==0x20: regs[rd]=(regs[rs1]-regs[rs2])&0xFFFFFFFF
            elif funct3==1: regs[rd]=(regs[rs1]<<(regs[rs2]&0x1f))&0xFFFFFFFF
            elif funct3==2: regs[rd]=1 if sx(regs[rs1])<sx(regs[rs2]) else 0
            elif funct3==3: regs[rd]=1 if (regs[rs1]&0xFFFFFFFF)<(regs[rs2]&0xFFFFFFFF) else 0
            elif funct3==4: regs[rd]=(regs[rs1]^regs[rs2])&0xFFFFFFFF
            elif funct3==5 and funct7==0: regs[rd]=((regs[rs1]&0xFFFFFFFF)>>(regs[rs2]&0x1f))&0xFFFFFFFF
            elif funct3==5 and funct7==0x20: regs[rd]=sx(regs[rs1])>>(regs[rs2]&0x1f); regs[rd]&=0xFFFFFFFF
            elif funct3==6: regs[rd]=(regs[rs1]|regs[rs2])&0xFFFFFFFF
            elif funct3==7: regs[rd]=(regs[rs1]&regs[rs2])&0xFFFFFFFF
        else:
            raise Exception("bad opcode %x at pc %x"%(opcode,pc))
        if rd!=0: regs[rd]&=0xFFFFFFFF
        pc+=4
    return uart

raw,labels=parse()
code=encode(raw,labels)
uart=simulate(code)
out=''.join(chr(b) for b in uart)
print("Simulated UART output:", repr(out))
if out=="OK\r\n":
    print("Result: PASS")
elif "FAIL" in out:
    tid=out.split("FAIL")[0]
    print("Result: FAIL at test", tid if tid else "?")
else:
    print("Result: UNEXPECTED")

# write program.hex (2048 lines, padded with NOP)
with open(sys.argv[1],'w') as f:
    lines=['%08X'%c for c in code]
    while len(lines)<2048:
        lines.append('00000013')
    f.write('\n'.join(lines)+'\n')
print("Wrote", sys.argv[1], "with", len(code), "instructions")

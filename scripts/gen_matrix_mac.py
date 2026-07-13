#!/usr/bin/env python3
# ============================================================================
# gen_matrix_mac.py
#   Generate mem/matrix_mac.hex : a 2x2 integer matrix-multiply self-test that
#   exercises the custom MAC instruction (rd = rd + rs1*rs2).
#
#   C = A * B, with
#       A = [[2,3],[4,5]]      B = [[6,7],[8,9]]
#   Expected:
#       C00 = 2*6+3*8 = 36 (0x24)   C01 = 2*7+3*9 = 41 (0x29)
#       C10 = 4*6+5*8 = 64 (0x40)   C11 = 4*7+5*9 = 73 (0x49)
#
#   Each element is computed by loading A/B from data RAM and accumulating with
#   MAC into a result register, then stored back to RAM. The program then
#   reloads the results, compares them to the expected constants, prints the
#   four results as hex bytes over UART, and finally prints "PASS" or "FAIL".
#
#   MAC encoding (R-type fields on the FENCE opcode 0x0F):
#       funct7=0000001, rs2=[24:20], rs1=[19:15], rd=[11:7]; acc = rd.
# ============================================================================
import sys

OPC_R=0x33; OPC_I=0x13; OPC_L=0x03; OPC_S=0x23; OPC_B=0x63
OPC_LUI=0x37; OPC_JAL=0x6F; OPC_JALR=0x67; OPC_FENCE=0x0F

UART = 0x10010000   # UART TX (write low byte)
RAM  = 0x10000000   # data RAM base

def u(x): return x & 0xFFFFFFFF

# ---- encoders ----
def R(f3,f7,rd,rs1,rs2): return u((f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|OPC_R)
def I(f3,rd,rs1,imm):    return u(((imm&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|OPC_I)
def LW_(rd,rs1,imm):     return u(((imm&0xFFF)<<20)|(rs1<<15)|(2<<12)|(rd<<7)|OPC_L)
def SW_(rs2,rs1,imm):
    imm&=0xFFF
    return u(((imm&0xFE0)<<20)|(rs2<<20)|(rs1<<15)|(2<<12)|((imm&0x1F)<<7)|OPC_S)
def B_(f3,rs1,rs2,imm):
    i12=(imm>>12)&1; i11=(imm>>11)&1; i10_5=(imm>>5)&0x3F; i4_1=(imm>>1)&0xF
    return u((i12<<31)|(i10_5<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(i4_1<<8)|(i11<<7)|OPC_B)
def LUI_(rd,imm20):      return u(((imm20&0xFFFFF)<<12)|(rd<<7)|OPC_LUI)
def JAL_(rd,imm):
    i20=(imm>>20)&1; i10_1=(imm>>1)&0x3FF; i11=(imm>>11)&1; i19_12=(imm>>12)&0xFF
    return u((i20<<31)|(i10_1<<21)|(i11<<20)|(i19_12<<12)|(rd<<7)|OPC_JAL)
def JALR_(rd,rs1,imm):   return u(((imm&0xFFF)<<20)|(rs1<<15)|(0<<12)|(rd<<7)|OPC_JALR)
def MAC_(rd,rs1,rs2):    return u((1<<25)|(rs2<<20)|(rs1<<15)|(0<<12)|(rd<<7)|OPC_FENCE)

# ---- tiny two-pass assembler over a program list ----
# Each program item is either ('label', name) or (mnemonic, args...) where
# branch/jump args may reference a label name (resolved in pass 2).
prog = []
def lbl(n): prog.append(('label', n))
def emit(*t): prog.append(t)

# PUTC pseudo: load literal into x20, then call put_char (which polls the UART
# status and only writes when the transmitter is NOT busy). x30 = UART base.
# NOTE: the real on-board UART is a shift register and MUST be polled busy
# (status @ 0x10010004, bit0) before each byte. The simulation UART model
# captured tx_start instantly, which hid this requirement and made the naive
# direct-SW version appear to work in simulation only.
def PUTC(ch):
    emit('ADDI','x20','x0', ch)
    emit('JAL','x1','put_char')

def r(x): return int(x[1:])

# ---------------------------------------------------------------------------
#  Program
# ---------------------------------------------------------------------------
# x30 = UART base, x31 = RAM base
emit('LUI','x30', UART>>12)          # 0x10010000
emit('LUI','x31', RAM>>12)           # 0x10000000

# store A = [[2,3],[4,5]] at 0(x31)
for off,val in [(0,2),(4,3),(8,4),(12,5)]:
    emit('ADDI','x5','x0', val); emit('SW','x5','x31', off)
# store B = [[6,7],[8,9]] at 16(x31)
for off,val in [(16,6),(20,7),(24,8),(28,9)]:
    emit('ADDI','x5','x0', val); emit('SW','x5','x31', off)

# ---- matrix multiply: C[i][j] = sum_k A[i][k]*B[k][j] ----
# A[i][k] at (i*2+k)*4 ; B[k][j] at 16 + (k*2+j)*4 ; C[i][j] at 32 + (i*2+j)*4
# accumulator registers: C00->x12, C01->x13, C10->x14, C11->x15
accreg = {(0,0):12,(0,1):13,(1,0):14,(1,1):15}
for i in range(2):
    for j in range(2):
        acc = accreg[(i,j)]
        emit('ADDI','x%d'%acc,'x0', 0)         # acc = 0
        for k in range(2):
            aoff = (i*2+k)*4
            boff = 16 + (k*2+j)*4
            emit('LW','x6','x31', aoff)         # A[i][k]
            emit('LW','x7','x31', boff)         # B[k][j]
            emit('MAC','x%d'%acc,'x6','x7')     # acc += A[i][k]*B[k][j]
        emit('SW','x%d'%acc,'x31', 32+(i*2+j)*4)

# ---- verify results against expected constants ----
expected = {(0,0):36,(0,1):41,(1,0):64,(1,1):73}
emit('ADDI','x28','x0', 0)   # x28 = fail flag (0 = pass)
for i in range(2):
    for j in range(2):
        emit('LW','x5','x31', 32+(i*2+j)*4)
        emit('ADDI','x6','x0', expected[(i,j)])
        emit('BNE','x5','x6','set_fail')

emit('JAL','x0','print_results')
lbl('set_fail')
emit('ADDI','x28','x0', 1)

lbl('print_results')
# print "MM " header
for ch in "MM ": PUTC(ord(ch))
# print each result as 2 hex chars + space
for i in range(2):
    for j in range(2):
        emit('LW','x21','x31', 32+(i*2+j)*4)
        emit('JAL','x1','put_hex8')
        PUTC(ord(' '))
PUTC(0x0D); PUTC(0x0A)
# print PASS/FAIL depending on x28
emit('BNE','x28','x0','pf_fail')
for ch in "PASS": PUTC(ord(ch))
PUTC(0x0D); PUTC(0x0A)
emit('JAL','x0','done')
lbl('pf_fail')
for ch in "FAIL": PUTC(ord(ch))
PUTC(0x0D); PUTC(0x0A)

lbl('done')
emit('JAL','x0','done')      # halt: self loop

# ---- subroutine: put_hex8  (prints low byte of x21 as 2 hex chars) ----
lbl('put_hex8')
# high nibble
emit('SRLI','x22','x21', 4)
emit('ANDI','x22','x22', 0xF)
emit('ADDI','x24','x22', 6)   # branchless hex: >9 ? +7 : +0
emit('SRLI','x24','x24', 4)
emit('ANDI','x24','x24', 1)
emit('SLLI','x25','x24', 3)
emit('SUB','x25','x25','x24') # x25 = x24*7
emit('ADDI','x20','x22', 0x30)
emit('ADD','x20','x20','x25')
# wait for UART ready, then send high nibble
lbl('ph_wait_h')
emit('LW','x29','x30', 4)
emit('ANDI','x29','x29', 1)
emit('BNE','x29','x0','ph_wait_h')
emit('SW','x20','x30', 0)
# low nibble
emit('ANDI','x22','x21', 0xF)
emit('ADDI','x24','x22', 6)
emit('SRLI','x24','x24', 4)
emit('ANDI','x24','x24', 1)
emit('SLLI','x25','x24', 3)
emit('SUB','x25','x25','x24')
emit('ADDI','x20','x22', 0x30)
emit('ADD','x20','x20','x25')
# wait for UART ready, then send low nibble
lbl('ph_wait_l')
emit('LW','x29','x30', 4)
emit('ANDI','x29','x29', 1)
emit('BNE','x29','x0','ph_wait_l')
emit('SW','x20','x30', 0)
emit('JALR','x0','x1', 0)

# ---- subroutine: put_char  (x20 = char to send; x1 = return address) ----
# Polls UART status (0x10010004, bit0 = busy) and only writes when not busy.
# Placed after the 'done' dead-loop so it is never reached by straight-line
# execution; it is only entered via JAL.
lbl('put_char')
lbl('pc_wait')
emit('LW','x29','x30', 4)
emit('ANDI','x29','x29', 1)
emit('BNE','x29','x0','pc_wait')
emit('SW','x20','x30', 0)
emit('JALR','x0','x1', 0)

# ---------------------------------------------------------------------------
#  Two-pass assembly
# ---------------------------------------------------------------------------
# pass 1: assign addresses (4 bytes each real instruction; labels are 0-size)
addr = 0
labels = {}
insns = []
for item in prog:
    if item[0]=='label':
        labels[item[1]] = addr
    else:
        insns.append((addr, item)); addr += 4

def resolve(cur, tgt):
    return labels[tgt] - cur

words = []
for cur, ins in insns:
    op = ins[0]
    if op=='LUI':   words.append(LUI_(r(ins[1]), ins[2]))
    elif op=='ADDI':words.append(I(0, r(ins[1]), r(ins[2]), ins[3]))
    elif op=='ANDI':words.append(I(7, r(ins[1]), r(ins[2]), ins[3]))
    elif op=='SLLI':words.append(I(1, r(ins[1]), r(ins[2]), ins[3]))
    elif op=='SRLI':words.append(I(5, r(ins[1]), r(ins[2]), ins[3]))
    elif op=='ADD': words.append(R(0,0x00, r(ins[1]), r(ins[2]), r(ins[3])))
    elif op=='SUB': words.append(R(0,0x20, r(ins[1]), r(ins[2]), r(ins[3])))
    elif op=='LW':  words.append(LW_(r(ins[1]), r(ins[2]), ins[3]))
    elif op=='SW':  words.append(SW_(r(ins[1]), r(ins[2]), ins[3]))
    elif op=='BNE': words.append(B_(1, r(ins[1]), r(ins[2]), resolve(cur, ins[3])))
    elif op=='BEQ': words.append(B_(0, r(ins[1]), r(ins[2]), resolve(cur, ins[3])))
    elif op=='JAL': words.append(JAL_(r(ins[1]), resolve(cur, ins[2])))
    elif op=='JALR':words.append(JALR_(r(ins[1]), r(ins[2]), ins[3]))
    elif op=='MAC': words.append(MAC_(r(ins[1]), r(ins[2]), r(ins[3])))
    else: raise Exception("unknown op %s" % op)

out = "mem/matrix_mac.hex"
with open(out,"w") as f:
    for w in words:
        f.write("%08X\n" % w)

print("wrote %s (%d instructions)" % (out, len(words)))
print("Expected results: C00=0x24 C01=0x29 C10=0x40 C11=0x49  (36 41 64 73)")

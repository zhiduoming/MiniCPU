"""Build the integrated CPU-controlled two-player VGA interaction program."""
from pathlib import Path


def u(rd, imm): return (imm << 12) | (rd << 7) | 0x37
def i(rd, rs1, f3, imm, op=0x13): return ((imm & 0xfff) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def r(rd, rs1, rs2, f3, f7=0): return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33
def s(rs2, rs1, f3, imm):
    imm &= 0xfff; return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 31) << 7) | 0x23
def br(rs1, rs2, f3, off):
    imm = off & 0x1fff; return ((imm >> 12) << 31) | (((imm >> 5) & 63) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (((imm >> 1) & 15) << 8) | (((imm >> 11) & 1) << 7) | 0x63
def jal(rd, off):
    imm = off & 0x1fffff; return ((imm >> 20) << 31) | (((imm >> 1) & 0x3ff) << 21) | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xff) << 12) | (rd << 7) | 0x6f


def build():
    c, lab, fix = [], {}, []
    def e(x): c.append(x)
    def mark(n): lab[n] = len(c)
    def beq(a,b,n): fix.append((len(c),'b',a,b,0,n)); e(0)
    def bne(a,b,n): fix.append((len(c),'b',a,b,1,n)); e(0)
    def blt(a,b,n): fix.append((len(c),'b',a,b,4,n)); e(0)
    def j(n): fix.append((len(c),'j',0,0,0,n)); e(0)

    # x5 MMIO base; x6 input; x8/x9 P1 x/y; x10/x11 P2 x/y.
    e(u(5,0x10010)); e(i(5,5,0,0x100)); e(i(6,5,0,0x10))
    e(i(8,0,0,100)); e(i(9,0,0,40)); e(i(10,0,0,650)); e(i(11,0,0,40))
    # x1/x2 are scores; x3 is the round-over display countdown; x4 selects winner.
    e(i(1,0,0,0)); e(i(2,0,0,0)); e(i(3,0,0,0)); e(i(4,0,0,0))
    # x13/x14 directions, x15..x20 projectile x/active/direction, x25 previous input.
    e(i(13,0,0,1)); e(i(14,0,0,0)); e(i(15,0,0,0)); e(i(16,0,0,0)); e(i(17,0,0,0))
    e(i(18,0,0,0)); e(i(19,0,0,0)); e(i(20,0,0,0)); e(i(21,0,0,0)); e(i(25,0,0,0)); e(u(27,1))
    e(i(28,0,0,100)); e(i(29,0,0,100)) # P1/P2 HP
    e(i(30,0,0,100)); e(i(31,0,0,100)) # P1/P2 MP

    mark('loop')
    # One-frame CPU hit-event pulses. They are consumed by the VGA renderer.
    e(i(22,0,0,0)); e(i(26,0,0,0))
    # Hold the result on screen, then restore the fighters and begin a new round.
    beq(3,0,'play_round')
    e(i(3,3,0,-1)); bne(3,0,'render')
    e(i(8,0,0,100)); e(i(9,0,0,40)); e(i(10,0,0,650)); e(i(11,0,0,40))
    e(i(13,0,0,1)); e(i(14,0,0,0)); e(i(15,0,0,0)); e(i(16,0,0,0)); e(i(17,0,0,0))
    e(i(18,0,0,0)); e(i(19,0,0,0)); e(i(20,0,0,0)); e(i(21,0,0,0)); e(i(25,0,0,0))
    e(i(28,0,0,100)); e(i(29,0,0,100)); e(i(30,0,0,100)); e(i(31,0,0,100)); j('loop')
    mark('play_round')
    # Read inputs before state update.
    e(i(12,6,2,0,0x03))
    # P1 horizontal: keypad 4/6.
    e(i(23,12,7,1)); beq(23,0,'p1_r_check'); e(i(23,8,2,2)); bne(23,0,'p1_done'); e(i(8,8,0,-2)); e(i(13,0,0,0)); j('p1_done')
    mark('p1_r_check'); e(i(23,12,7,2)); beq(23,0,'p1_done'); e(i(23,8,2,759)); beq(23,0,'p1_done'); e(i(8,8,0,2)); e(i(13,0,0,1))
    mark('p1_done')
    # P2 horizontal: S2/S1.
    e(i(23,12,7,0x100)); beq(23,0,'p2_r_check'); e(i(23,10,2,2)); bne(23,0,'p2_done'); e(i(10,10,0,-2)); e(i(14,0,0,0)); j('p2_done')
    mark('p2_r_check'); e(i(23,12,7,0x200)); beq(23,0,'p2_done'); e(i(23,10,2,759)); beq(23,0,'p2_done'); e(i(10,10,0,2)); e(i(14,0,0,1))
    mark('p2_done')
    # A held jump key raises the sprite; release returns it to the ground.
    e(i(23,12,7,4)); beq(23,0,'p1_ground'); e(i(9,0,0,200)); j('p1_jump_done')
    mark('p1_ground'); e(i(9,0,0,40)); mark('p1_jump_done')
    e(i(23,12,7,0x400)); beq(23,0,'p2_ground'); e(i(11,0,0,200)); j('p2_jump_done')
    mark('p2_ground'); e(i(11,0,0,40)); mark('p2_jump_done')
    # New projectile presses: P1 key 8 (bit4), P2 S5 (bit12).
    e(i(23,25,4,-1)); e(r(24,12,23,7))
    e(i(23,24,7,0x10)); beq(23,0,'p1_spawn_done'); bne(16,0,'p1_spawn_done'); e(i(23,30,2,20)); bne(23,0,'p1_spawn_done'); e(i(15,8,0,0)); e(i(16,0,0,1)); e(i(17,13,0,0)); e(i(30,30,0,-20))
    mark('p1_spawn_done'); e(r(23,24,27,7)); beq(23,0,'p2_spawn_done'); bne(19,0,'p2_spawn_done'); e(i(23,31,2,20)); bne(23,0,'p2_spawn_done'); e(i(18,10,0,0)); e(i(19,0,0,1)); e(i(20,14,0,0)); e(i(31,31,0,-20))
    mark('p2_spawn_done')
    # New melee presses deal five HP when the fighters are within 60 pixels.
    e(i(23,24,7,8)); beq(23,0,'p1_melee_done'); e(r(23,10,8,0,0x20)); blt(23,0,'p1_dist_neg'); j('p1_dist_ready')
    mark('p1_dist_neg'); e(r(23,0,23,0,0x20)); mark('p1_dist_ready'); e(i(23,23,2,25)); beq(23,0,'p1_melee_done'); e(i(29,29,0,-5)); e(i(26,0,0,1))
    mark('p1_melee_done')
    e(i(23,24,5,11)); e(i(23,23,7,1)); beq(23,0,'p2_melee_done'); e(r(23,10,8,0,0x20)); blt(23,0,'p2_dist_neg'); j('p2_dist_ready')
    mark('p2_dist_neg'); e(r(23,0,23,0,0x20)); mark('p2_dist_ready'); e(i(23,23,2,25)); beq(23,0,'p2_melee_done'); e(i(28,28,0,-5)); e(i(22,0,0,1))
    mark('p2_melee_done')
    # Advance active projectiles by six pixels per game tick.
    beq(16,0,'p1_proj_done'); beq(17,0,'p1_proj_left'); e(i(15,15,0,6)); j('p1_proj_moved')
    mark('p1_proj_left'); e(i(15,15,0,-6)); mark('p1_proj_moved')
    e(i(23,15,2,800)); beq(23,0,'p1_proj_off'); e(i(23,15,2,0)); bne(23,0,'p1_proj_off')
    e(r(23,15,10,0,0x20)); blt(23,0,'p1_hit_abs'); j('p1_hit_check')
    mark('p1_hit_abs'); e(r(23,0,23,0,0x20)); mark('p1_hit_check'); e(i(23,23,2,36)); beq(23,0,'p1_proj_done')
    # A projectile only hurts a player whose body overlaps it vertically.
    e(r(23,9,11,0,0x20)); blt(23,0,'p1_height_abs'); j('p1_height_check')
    mark('p1_height_abs'); e(r(23,0,23,0,0x20)); mark('p1_height_check'); e(i(23,23,2,48)); beq(23,0,'p1_proj_done')
    e(i(29,29,0,-8)); e(i(26,0,0,1)); e(i(16,0,0,0)); j('p1_proj_done')
    mark('p1_proj_off'); e(i(16,0,0,0)); mark('p1_proj_done')
    beq(19,0,'p2_proj_done'); beq(20,0,'p2_proj_left'); e(i(18,18,0,6)); j('p2_proj_moved')
    mark('p2_proj_left'); e(i(18,18,0,-6)); mark('p2_proj_moved')
    e(i(23,18,2,800)); beq(23,0,'p2_proj_off'); e(i(23,18,2,0)); bne(23,0,'p2_proj_off')
    e(r(23,18,8,0,0x20)); blt(23,0,'p2_hit_abs'); j('p2_hit_check')
    mark('p2_hit_abs'); e(r(23,0,23,0,0x20)); mark('p2_hit_check'); e(i(23,23,2,36)); beq(23,0,'p2_proj_done')
    e(r(23,11,9,0,0x20)); blt(23,0,'p2_height_abs'); j('p2_height_check')
    mark('p2_height_abs'); e(r(23,0,23,0,0x20)); mark('p2_height_check'); e(i(23,23,2,48)); beq(23,0,'p2_proj_done')
    e(i(28,28,0,-8)); e(i(22,0,0,1)); e(i(19,0,0,0)); j('p2_proj_done')
    mark('p2_proj_off'); e(i(19,0,0,0)); mark('p2_proj_done')
    # A player dies at zero HP. Freeze the round for about five seconds, then restart.
    beq(28,0,'p2_wins'); blt(28,0,'p2_wins'); beq(29,0,'p1_wins'); blt(29,0,'p1_wins'); j('mp_regen_start')
    mark('p2_wins'); e(i(28,0,0,0)); e(i(4,0,0,1)); e(i(2,2,0,1)); e(i(3,0,0,250)); e(i(16,0,0,0)); e(i(19,0,0,0)); j('render')
    mark('p1_wins'); e(i(29,0,0,0)); e(i(4,0,0,0)); e(i(1,1,0,1)); e(i(3,0,0,250)); e(i(16,0,0,0)); e(i(19,0,0,0)); j('render')
    # The loop is about 125 Hz. Restore one MP every 62 ticks: two MP per second.
    mark('mp_regen_start'); e(i(21,21,0,1)); e(i(23,0,0,62)); bne(21,23,'mp_regen_done'); e(i(21,0,0,0))
    e(i(23,30,2,100)); beq(23,0,'p1_mp_full'); e(i(30,30,0,1)); mark('p1_mp_full')
    e(i(23,31,2,100)); beq(23,0,'mp_regen_done'); e(i(31,31,0,1)); mark('mp_regen_done')
    mark('render')
    # Write P1/P2 packed positions.
    e(i(23,9,1,16)); e(r(23,23,8,6)); e(s(23,5,2,0))
    e(i(23,11,1,16)); e(r(23,23,10,6)); e(s(23,5,2,4))
    # Pack P1/P2 MP and HP. Explicit bubbles avoid an uncovered store-forward path.
    e(i(23,31,1,23)); e(0x00000013)
    e(i(24,30,1,16)); e(0x00000013)
    e(r(23,23,24,6)); e(0x00000013)
    e(i(24,29,1,8)); e(0x00000013)
    e(r(23,23,24,6)); e(0x00000013)
    e(r(23,23,28,6)); e(0x00000013)
    e(s(23,5,2,8))
    # Build the render flags from input and persistent direction/projectile state.
    e(i(24,0,0,0)); e(r(24,24,13,6)); e(i(23,14,1,1)); e(r(24,24,23,6))
    e(i(23,12,7,8)); beq(23,0,'no_p1_atk'); e(i(24,24,6,4)); mark('no_p1_atk')
    e(i(23,12,5,11)); e(i(23,23,7,1)); beq(23,0,'no_p2_atk'); e(i(24,24,6,8)); mark('no_p2_atk')
    e(i(23,12,7,4)); beq(23,0,'no_p1_jmp'); e(i(24,24,6,16)); mark('no_p1_jmp')
    e(i(23,12,7,0x400)); beq(23,0,'no_p2_jmp'); e(i(24,24,6,32)); mark('no_p2_jmp')
    e(i(23,22,1,6)); e(r(24,24,23,6)); e(i(23,26,1,7)); e(r(24,24,23,6))
    e(i(23,16,1,8)); e(r(24,24,23,6)); e(i(23,19,1,9)); e(r(24,24,23,6))
    e(i(23,17,1,10)); e(r(24,24,23,6)); e(i(23,20,1,11)); e(r(24,24,23,6))
    # Add score and round-end state to unused high bits of game_flags.
    e(i(23,1,1,16)); e(r(24,24,23,6)); e(i(23,2,1,20)); e(r(24,24,23,6))
    beq(3,0,'no_round_over'); e(i(23,0,0,1)); e(i(23,23,1,12)); e(r(24,24,23,6)); e(i(23,4,1,13)); e(r(24,24,23,6))
    mark('no_round_over'); e(0x00000013); e(s(24,5,2,12))
    # Write projectile positions using the current player height.
    # P_HEIGHT=64 and PROJ_SIZE=12: Y+26 centers the projectile at chest height.
    e(i(23,9,0,26)); e(i(23,23,1,16)); e(r(23,23,15,6)); e(s(23,5,2,20))
    e(i(23,11,0,26)); e(i(23,23,1,16)); e(r(23,23,18,6)); e(s(23,5,2,24))
    e(i(25,12,0,0))
    # About 50 FPS at the 5 MHz CPU clock.
    e(u(26,5)); e(i(26,26,0,-480)); mark('delay'); e(i(26,26,0,-1)); bne(26,0,'delay'); j('loop')

    for n,k,a,b,f,t in fix:
        off=(lab[t]-n)*4; c[n]=br(a,b,f,off) if k=='b' else jal(0,off)
    return c


def main():
    words=build(); words += [0x00000013]*(2048-len(words))
    out=Path(__file__).resolve().parents[1]/'test_programs'/'game_interactive.hex'
    out.write_text('\n'.join(f'{x:08X}' for x in words)+'\n',encoding='ascii')

if __name__=='__main__': main()

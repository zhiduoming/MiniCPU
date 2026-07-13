"""Generate the RISC-V program that owns the two-player fight state.

The program mirrors the old fight_game_logic.v rules.  Verilog only exposes
MMIO registers and renders the state on VGA; no HDL combat state machine is
instantiated in the CPU design.
"""
from pathlib import Path


def u(rd, imm): return (imm << 12) | (rd << 7) | 0x37
def i(rd, rs1, f3, imm, op=0x13): return ((imm & 0xfff) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def r(rd, rs1, rs2, f3, f7=0): return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33
def s(rs2, rs1, f3, imm):
    imm &= 0xfff
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 31) << 7) | 0x23
def br(rs1, rs2, f3, off):
    imm = off & 0x1fff
    return ((imm >> 12) << 31) | (((imm >> 5) & 63) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (((imm >> 1) & 15) << 8) | (((imm >> 11) & 1) << 7) | 0x63
def jal(rd, off):
    imm = off & 0x1fffff
    return ((imm >> 20) << 31) | (((imm >> 1) & 0x3ff) << 21) | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xff) << 12) | (rd << 7) | 0x6f
def lw(rd, rs1, imm): return i(rd, rs1, 2, imm, 0x03)


# CPU data-RAM fields at 0x1000_0000. The program owns every one of them.
P1_VY, P2_VY = 0, 4
P1_ATK, P2_ATK = 8, 12
P1_HIT, P2_HIT = 16, 20
P1_PY, P2_PY = 24, 28
P1_PD, P2_PD = 32, 36
MED_SPAWN, MED_LIFE, MED_ACTIVE, MED_X, MED_Y, RAND_SEED = 40, 44, 48, 52, 56, 60
ROUND_TIMER, ROUND_WINNER = 64, 68
MENU_ACTIVE, MENU_SELECT = 72, 76
AI_ATTACK_CD, AI_JUMP_CD, AI_RANGED_CD = 80, 84, 88
MENU_STAGE, TIME_INDEX, TIME_SECONDS, TIME_FRAME = 92, 96, 100, 104
AI_LFSR, AI_P1_PREV_RAW, AI_P1_PREV_SAFE = 108, 112, 116
AI_P1_ATTACK_PREV, AI_WHIFF_TIMER, AI_COMBO_TIMER = 120, 124, 128
AI_SPAM_X, AI_SPAM_DURATION, AI_PATTERN_TIMER = 132, 136, 140
AI_JUMP_COUNT, AI_AIR_PREV, AI_PREV_DIST = 144, 148, 152
AI_AGGRO_TIMER, AI_WHIFF_STREAK = 156, 160
AI_STYLE_TIMER, AI_PREF_GROUND = 164, 168
IRQ_SCREEN, IRQ_SAVE_X23, IRQ_SAVE_X24 = 172, 176, 180
IRQ_SAVE_X1, IRQ_SAVE_X20, IRQ_SAVE_X21, IRQ_SAVE_X22 = 184, 188, 192, 196
IRQ_SAVE_X25, IRQ_SAVE_X26, IRQ_SAVE_X27, IRQ_SAVE_X28 = 200, 204, 208, 212
IRQ_SAVE_X29, IRQ_SAVE_X30, IRQ_SAVE_X31 = 216, 220, 224
PERF_CYC_S, PERF_INST_S, PERF_ACC_S, PERF_HIT_S = 228, 232, 236, 240
PERF_MISS_S, PERF_MODE_S, PERF_STALL_S, PERF_BRANCH_S = 244, 248, 252, 256
PERF_BPM_S, PERF_MEMORY_S, PERF_MEXT_S, PERF_MAC_S, PERF_MULCYC_S = 260, 264, 268, 272, 276
IRQ_SAVE_X19, IRQ_REQUEST = 280, 284
IRQ_SAVE_X18 = 288


def build():
    c, labels, fix = [], {}, []
    def e(word): c.append(word)
    def mark(name): labels[name] = len(c)
    def beq(a, b, target): fix.append((len(c), 'b', a, b, 0, target)); e(0)
    def bne(a, b, target): fix.append((len(c), 'b', a, b, 1, target)); e(0)
    def blt(a, b, target): fix.append((len(c), 'b', a, b, 4, target)); e(0)
    def bltu(a, b, target): fix.append((len(c), 'b', a, b, 6, target)); e(0)
    def j(target): fix.append((len(c), 'j', 0, 0, 0, target)); e(0)
    def call(target): fix.append((len(c), 'c', 1, 0, 0, target)); e(0)
    def la(rd, target):
        fix.append((len(c), 'u', rd, 0, 0, target)); e(0)
        fix.append((len(c), 'i', rd, 0, 0, target)); e(0)
    def nop(): e(0x00000013)
    def li(rd, value): e(i(rd, 0, 0, value))
    def load(rd, offset): e(lw(rd, 7, offset)); nop()
    def store(rs, offset): nop(); e(s(rs, 7, 2, offset))
    def put_text(text):
        for ch in text:
            li(20, ord(ch)); call('perf_putc')
    def print_metric(name, offset):
        put_text(name + '=')
        e(lw(21, 7, offset)); nop(); call('perf_dec32')
        put_text('\r\n')
    def print_ratio100(name, numerator_off, denominator_off, tag, scale=100):
        # Overflow-safe fixed point. scale=100 is used for CPI/MIPS; scale=10000
        # prints percentages with two digits after the decimal point.
        put_text(name + '=')
        e(lw(21, 7, numerator_off)); nop(); e(lw(22, 7, denominator_off)); nop()
        beq(22, 0, tag + '_zero')
        e(r(24, 21, 22, 5, 1)); e(r(25, 21, 22, 7, 1))
        if scale == 100:
            li(23, 100); e(u(26, 0x02800))
        else:
            e(u(23, 0x2)); e(i(23, 23, 0, 1808)); e(u(26, 0x00060))
        e(r(24, 24, 23, 0, 1)); bltu(22, 26, tag + '_exact')
        e(r(22, 22, 23, 5, 1)); bne(22, 0, tag + '_den_ok')
        li(22, 1); mark(tag + '_den_ok'); e(r(25, 25, 22, 5, 1)); e(r(21, 24, 25, 0)); j(tag + '_print')
        mark(tag + '_exact'); e(r(25, 25, 23, 0, 1)); e(r(25, 25, 22, 5, 1)); e(r(21, 24, 25, 0)); j(tag + '_print')
        mark(tag + '_zero'); li(21, 0); mark(tag + '_print'); call('perf_fixed2')
        put_text('\r\n')
    def abs_reg(reg, tag):
        blt(reg, 0, tag + '_neg'); j(tag + '_done')
        mark(tag + '_neg'); e(r(reg, 0, reg, 0, 0x20))
        mark(tag + '_done')

    # x1/x2 score; x3/x4 are P1/P2 jump phase counters (32..1).
    # x5 MMIO game base, x6 input address, x7 data-RAM base.
    e(u(5, 0x10010)); e(i(5, 5, 0, 0x100)); e(i(6, 5, 0, 0x10)); e(u(7, 0x10000))
    li(1, 0); li(2, 0); li(3, 0); li(4, 0)
    # x8/x9 P1 x/y, x10/x11 P2 x/y. x13/x14 facing direction.
    li(8, 100); li(9, 40); li(10, 650); li(11, 40); li(13, 1); li(14, 0)
    # x15..x20: projectile X, active, direction for P1 then P2.
    li(15, 0); li(16, 0); li(17, 0); li(18, 0); li(19, 0); li(20, 0)
    # x21 MP regeneration frame counter, x22/x26 hit pulses, x25 previous
    # inputs, x27 preserved new-press bits for attack/projectile edge tests.
    li(21, 0); li(22, 0); li(25, 0); li(26, 0); li(27, 0)
    li(28, 100); li(29, 100); li(30, 100); li(31, 100)
    for off, value in ((P1_VY, 0), (P2_VY, 0), (P1_ATK, 0), (P2_ATK, 0),
                       (P1_HIT, 0), (P2_HIT, 0), (P1_PY, 0), (P2_PY, 0),
                       (P1_PD, 0), (P2_PD, 0), (MED_SPAWN, 0),
                       (MED_LIFE, 0), (MED_ACTIVE, 0), (MED_X, 390), (MED_Y, 40),
                       (RAND_SEED, 1445), (ROUND_TIMER, 0), (ROUND_WINNER, 0),
                       (MENU_ACTIVE, 1), (MENU_SELECT, 0),
                       (AI_ATTACK_CD, 0), (AI_JUMP_CD, 0), (AI_RANGED_CD, 0),
                       (MENU_STAGE, 0), (TIME_INDEX, 0),
                       (TIME_SECONDS, 60), (TIME_FRAME, 0),
                       (AI_LFSR, 0x6e1), (AI_P1_PREV_RAW, 100),
                       (AI_P1_PREV_SAFE, 100), (AI_P1_ATTACK_PREV, 0),
                       (AI_WHIFF_TIMER, 0), (AI_COMBO_TIMER, 0),
                       (AI_SPAM_X, 100), (AI_SPAM_DURATION, 0),
                       (AI_PATTERN_TIMER, 0), (AI_JUMP_COUNT, 0),
                       (AI_AIR_PREV, 0), (AI_PREV_DIST, 550),
                       (AI_AGGRO_TIMER, 0), (AI_WHIFF_STREAK, 0),
                       (AI_STYLE_TIMER, 0), (AI_PREF_GROUND, 0),
                       (IRQ_SCREEN, 0), (IRQ_SAVE_X23, 0), (IRQ_SAVE_X24, 0),
                       (IRQ_SAVE_X1, 0), (IRQ_SAVE_X20, 0), (IRQ_SAVE_X21, 0),
                       (IRQ_SAVE_X22, 0), (IRQ_SAVE_X25, 0), (IRQ_SAVE_X26, 0),
                       (IRQ_SAVE_X27, 0), (IRQ_SAVE_X28, 0), (IRQ_SAVE_X29, 0),
                       (IRQ_SAVE_X30, 0), (IRQ_SAVE_X31, 0),
                       (IRQ_SAVE_X19, 0), (IRQ_REQUEST, 0), (IRQ_SAVE_X18, 0)):
        li(23, value); store(23, off)

    # The game installs its own machine-mode external interrupt handler.
    nop(); nop(); nop(); nop()
    la(23, 'irq_handler')
    e((0x305 << 20) | (23 << 15) | (1 << 12) | 0x73)  # csrrw x0, mtvec, x23
    nop(); nop(); nop(); nop()
    e(s(0, 7, 2, IRQ_SCREEN))
    nop(); nop(); nop(); nop()

    mark('loop')
    li(22, 0); li(26, 0)
    # While the IRQ result is visible, pause every game state including time.
    load(23, IRQ_SCREEN); beq(23, 0, 'irq_screen_done')
    e(i(23, 23, 0, -1)); store(23, IRQ_SCREEN); j('render')
    mark('irq_screen_done')
    # The ISR only posts a request. Run the long UART formatter here, at a
    # clean game-loop boundary, so no live combat instruction is interrupted.
    load(23, IRQ_REQUEST); beq(23, 0, 'irq_request_done')
    li(23, 0); store(23, IRQ_REQUEST); j('perf_report')
    mark('irq_request_done')
    # Inputs are sampled in every stage so the two menus also use CPU edge logic.
    e(lw(12, 6, 0)); nop()
    e(r(27, 12, 25, 4)); e(r(27, 27, 12, 7))

    # MENU_STAGE: 0=mode, 1=time, 2=match, 3=time-out screen.
    load(23, MENU_STAGE); beq(23, 0, 'mode_menu')
    li(24, 1); beq(23, 24, 'time_menu'); li(24, 3); beq(23, 24, 'render')

    # A death pauses the match clock throughout the five-second result screen.
    load(23, ROUND_TIMER); bne(23, 0, 'round_screen_check')
    load(23, TIME_FRAME); e(i(23, 23, 0, 1)); store(23, TIME_FRAME)
    li(24, 125); bne(23, 24, 'round_screen_check'); li(23, 0); store(23, TIME_FRAME)
    load(23, TIME_SECONDS); beq(23, 0, 'time_expired'); e(i(23, 23, 0, -1)); store(23, TIME_SECONDS)
    bne(23, 0, 'round_screen_check')
    mark('time_expired'); li(23, 3); store(23, MENU_STAGE); li(16, 0); li(19, 0); j('render')

    mark('round_screen_check')
    # During the result screen input and combat stop. Scores persist between rounds.
    load(23, ROUND_TIMER); beq(23, 0, 'play')
    e(i(23, 23, 0, -1)); store(23, ROUND_TIMER); bne(23, 0, 'render')
    li(8, 100); li(9, 40); li(10, 650); li(11, 40); li(13, 1); li(14, 0)
    li(15, 0); li(16, 0); li(17, 0); li(18, 0); li(19, 0); li(20, 0)
    li(3, 0); li(4, 0); li(21, 0); li(25, 0); li(28, 100); li(29, 100); li(30, 100); li(31, 100)
    for off, value in ((P1_VY, 0), (P2_VY, 0), (P1_ATK, 0), (P2_ATK, 0),
                       (P1_HIT, 0), (P2_HIT, 0), (P1_PY, 0), (P2_PY, 0),
                       (P1_PD, 0), (P2_PD, 0), (MED_SPAWN, 0),
                       (MED_LIFE, 0), (MED_ACTIVE, 0), (RAND_SEED, 1445),
                        (ROUND_TIMER, 0), (ROUND_WINNER, 0),
                        (AI_ATTACK_CD, 0), (AI_JUMP_CD, 0), (AI_RANGED_CD, 0),
                        (AI_P1_ATTACK_PREV, 0), (AI_WHIFF_TIMER, 0),
                        (AI_COMBO_TIMER, 0), (AI_SPAM_DURATION, 0)):
        li(23, value); store(23, off)
    j('loop')

    # Initial mode menu. P1 4 selects human-vs-CPU, 6 selects PVP, 5 confirms.
    mark('mode_menu')
    e(i(23, 27, 7, 1)); nop(); beq(23, 0, 'menu_right_check'); li(23, 0); store(23, MENU_SELECT)
    mark('menu_right_check'); e(i(23, 27, 7, 2)); nop(); beq(23, 0, 'menu_confirm_check'); li(23, 1); store(23, MENU_SELECT)
    mark('menu_confirm_check'); e(i(23, 27, 7, 8)); nop(); beq(23, 0, 'menu_wait'); li(23, 1); store(23, MENU_STAGE)
    mark('menu_wait'); li(27, 0); j('render')

    # Duration menu: 4/6 move through 1,3,5,10,15 minutes; 5 confirms.
    mark('time_menu')
    load(23, TIME_INDEX)
    e(i(24, 27, 7, 1)); beq(24, 0, 'time_right_check'); beq(23, 0, 'time_selection_done'); e(i(23, 23, 0, -1)); store(23, TIME_INDEX); j('time_selection_changed')
    mark('time_right_check'); e(i(24, 27, 7, 2)); beq(24, 0, 'time_confirm_check'); li(24, 4); beq(23, 24, 'time_selection_done'); e(i(23, 23, 0, 1)); store(23, TIME_INDEX); j('time_selection_changed')
    mark('time_confirm_check'); e(i(24, 27, 7, 8)); beq(24, 0, 'time_selection_done'); li(23, 2); store(23, MENU_STAGE); li(23, 0); store(23, TIME_FRAME)
    # Start the performance window exactly when the selected match starts.
    e(u(23, 0x10010)); e(s(0, 23, 2, 8)); nop(); nop(); j('render')
    mark('time_selection_changed')
    # Convert selection index to seconds; the same MMIO value drives the menu box.
    load(23, TIME_INDEX); beq(23, 0, 'time_value_1'); li(24, 1); beq(23, 24, 'time_value_3'); li(24, 2); beq(23, 24, 'time_value_5'); li(24, 3); beq(23, 24, 'time_value_10'); li(23, 900); j('time_value_store')
    mark('time_value_1'); li(23, 60); j('time_value_store')
    mark('time_value_3'); li(23, 180); j('time_value_store')
    mark('time_value_5'); li(23, 300); j('time_value_store')
    mark('time_value_10'); li(23, 600)
    mark('time_value_store'); store(23, TIME_SECONDS)
    mark('time_selection_done'); li(27, 0); j('render')

    mark('play')
    mark('mode_selected')
    # MENU_SELECT=0: software AI owns P2. MENU_SELECT=1: S1-S5 own P2.
    load(23, MENU_SELECT); bne(23, 0, 'p2_input_ready')
    e(i(12, 12, 7, 31)); e(i(27, 27, 7, 31))
    # Full software port of fight_ai_logic: timers, opponent sampling,
    # adaptive counters, style randomization and all eight tactical families.
    load(23, AI_ATTACK_CD); beq(23, 0, 'ai_attack_cd_done'); e(i(23, 23, 0, -1)); store(23, AI_ATTACK_CD); mark('ai_attack_cd_done')
    load(23, AI_JUMP_CD); beq(23, 0, 'ai_jump_cd_done'); e(i(23, 23, 0, -1)); store(23, AI_JUMP_CD); mark('ai_jump_cd_done')
    load(23, AI_RANGED_CD); beq(23, 0, 'ai_ranged_cd_done'); e(i(23, 23, 0, -1)); store(23, AI_RANGED_CD); mark('ai_ranged_cd_done')
    e(r(24, 10, 8, 0, 0x20)); abs_reg(24, 'ai_distance')

    # Original 16-bit LFSR polynomial: bit15 xor bit13 xor bit4.
    load(23, AI_LFSR); e(i(26, 23, 5, 15)); e(i(22, 23, 5, 13)); e(r(26, 26, 22, 4)); e(i(22, 23, 5, 4)); e(r(26, 26, 22, 4)); e(i(26, 26, 7, 1))
    e(i(23, 23, 1, 1)); e(i(23, 23, 1, 16)); e(i(23, 23, 5, 16)); e(r(23, 23, 26, 6)); store(23, AI_LFSR)

    # Random ground/air preference changes every 30 frames.
    load(23, AI_STYLE_TIMER); bne(23, 0, 'ai_style_tick'); load(23, AI_LFSR); e(i(23, 23, 7, 127)); e(i(26, 23, 2, 40)); store(26, AI_PREF_GROUND); li(23, 30); store(23, AI_STYLE_TIMER); j('ai_style_done')
    mark('ai_style_tick'); e(i(23, 23, 0, -1)); store(23, AI_STYLE_TIMER); mark('ai_style_done')

    # Attack edge, whiff window and adaptive whiff streak.
    load(23, P1_ATK); e(i(26, 23, 3, 1)); load(22, AI_P1_ATTACK_PREV); beq(26, 0, 'ai_no_attack_edge'); bne(22, 0, 'ai_no_attack_edge')
    li(22, 45); store(22, AI_WHIFF_TIMER); e(i(22, 24, 2, 41)); bne(22, 0, 'ai_whiff_reset'); load(22, AI_WHIFF_STREAK); e(i(22, 22, 0, 1)); store(22, AI_WHIFF_STREAK); j('ai_no_attack_edge')
    mark('ai_whiff_reset'); li(22, 0); store(22, AI_WHIFF_STREAK)
    mark('ai_no_attack_edge'); store(26, AI_P1_ATTACK_PREV)
    load(22, AI_WHIFF_TIMER); beq(22, 0, 'ai_whiff_tick_done'); e(i(22, 22, 0, -1)); store(22, AI_WHIFF_TIMER); mark('ai_whiff_tick_done')

    # Continuous pressure detector and reference position.
    beq(26, 0, 'ai_spam_clear'); load(22, AI_SPAM_DURATION); bne(22, 0, 'ai_spam_inc'); store(8, AI_SPAM_X)
    mark('ai_spam_inc'); e(i(22, 22, 0, 1)); store(22, AI_SPAM_DURATION); j('ai_spam_done')
    mark('ai_spam_clear'); li(22, 0); store(22, AI_SPAM_DURATION); mark('ai_spam_done')

    # Jump-frequency learning over the original 600-frame observation window.
    load(22, AI_PATTERN_TIMER); e(i(22, 22, 0, 1)); li(23, 600); bne(22, 23, 'ai_pattern_store'); li(22, 0); li(23, 0); store(23, AI_JUMP_COUNT)
    mark('ai_pattern_store'); store(22, AI_PATTERN_TIMER)
    load(22, AI_AIR_PREV); beq(3, 0, 'ai_air_state_store'); bne(22, 0, 'ai_air_state_store'); load(22, AI_JUMP_COUNT); e(i(22, 22, 0, 1)); store(22, AI_JUMP_COUNT)
    mark('ai_air_state_store'); e(i(22, 3, 3, 1)); store(22, AI_AIR_PREV)

    # Two-frame speed sample and aggression accumulation.
    load(22, AI_P1_PREV_RAW); load(23, AI_P1_PREV_SAFE); store(22, AI_P1_PREV_SAFE); store(8, AI_P1_PREV_RAW)
    e(r(22, 23, 8, 0, 0x20)); abs_reg(22, 'ai_p1_speed')
    load(23, AI_PREV_DIST); store(24, AI_PREV_DIST); blt(24, 23, 'ai_aggro_nearer'); j('ai_aggro_decay')
    mark('ai_aggro_nearer'); e(i(23, 24, 2, 110)); beq(23, 0, 'ai_aggro_decay'); load(23, AI_AGGRO_TIMER); e(i(23, 23, 0, 1)); store(23, AI_AGGRO_TIMER); j('ai_aggro_done')
    mark('ai_aggro_decay'); load(23, AI_AGGRO_TIMER); beq(23, 0, 'ai_aggro_done'); e(i(23, 23, 0, -1)); store(23, AI_AGGRO_TIMER); mark('ai_aggro_done')

    # T_ANTI_SPAM has highest priority when pressure stays nearly stationary.
    load(23, AI_SPAM_DURATION); e(i(23, 23, 2, 19)); bne(23, 0, 'ai_evade_check'); load(23, AI_SPAM_X); e(r(23, 8, 23, 0, 0x20)); abs_reg(23, 'ai_spam_distance'); e(i(23, 23, 2, 8)); beq(23, 0, 'ai_evade_check'); beq(3, 0, 'ai_evade_action')

    # T_EVADE: attack danger or a fast rush inside footsies distance.
    mark('ai_evade_check'); load(23, P1_ATK); beq(23, 0, 'ai_rush_check'); e(i(23, 24, 2, 70)); bne(23, 0, 'ai_evade_action')
    mark('ai_rush_check'); e(i(23, 22, 2, 7)); bne(23, 0, 'ai_punish_check'); e(i(23, 24, 2, 110)); bne(23, 0, 'ai_evade_action'); j('ai_punish_check')
    mark('ai_evade_action'); load(23, AI_LFSR); e(i(23, 23, 7, 127)); e(i(23, 23, 2, 85)); beq(23, 0, 'ai_retreat')
    load(23, AI_JUMP_CD); bne(23, 0, 'ai_retreat'); e(i(27, 27, 6, 0x400)); li(23, 60); store(23, AI_JUMP_CD)
    mark('ai_retreat'); blt(8, 10, 'ai_retreat_right'); e(i(12, 12, 6, 0x100)); j('p2_input_ready'); mark('ai_retreat_right'); e(i(12, 12, 6, 0x200)); j('p2_input_ready')

    # T_PUNISH: close during the latter half of the opponent whiff window.
    mark('ai_punish_check'); load(23, AI_WHIFF_TIMER); beq(23, 0, 'ai_air_intercept_check'); e(i(23, 23, 2, 25)); beq(23, 0, 'ai_air_intercept_check'); j('ai_pressure_move')

    # T_AIR_INT: adaptive intercept; frequent jumpers bypass the random retreat.
    mark('ai_air_intercept_check'); beq(3, 0, 'ai_pressure_check'); e(i(23, 24, 2, 90)); beq(23, 0, 'ai_pressure_check'); bne(4, 0, 'ai_pressure_check')
    load(23, AI_JUMP_CD); bne(23, 0, 'ai_pressure_move'); e(i(27, 27, 6, 0x400)); li(23, 60); store(23, AI_JUMP_CD); j('ai_pressure_move')

    # T_PRESSURE and close-range combo behavior.
    mark('ai_pressure_check'); e(i(23, 24, 2, 40)); beq(23, 0, 'ai_ranged_check')
    mark('ai_pressure_move'); blt(8, 10, 'ai_pressure_left'); e(i(12, 12, 6, 0x200)); j('ai_pressure_attack'); mark('ai_pressure_left'); e(i(12, 12, 6, 0x100))
    mark('ai_pressure_attack'); load(23, AI_ATTACK_CD); bne(23, 0, 'p2_input_ready'); li(23, 1); e(i(23, 23, 1, 11)); e(r(27, 27, 23, 6)); load(23, AI_WHIFF_STREAK); e(i(23, 23, 2, 3)); beq(23, 0, 'ai_attack_normal_cd'); li(23, 15); j('ai_attack_cd_store'); mark('ai_attack_normal_cd'); li(23, 48); mark('ai_attack_cd_store'); store(23, AI_ATTACK_CD); j('p2_input_ready')

    # T_RANGED: original MP/projectile checks, retuned to 100..260 pixels.
    mark('ai_ranged_check'); e(i(23, 24, 2, 100)); bne(23, 0, 'ai_mirror'); e(i(23, 24, 2, 261)); beq(23, 0, 'ai_mirror'); e(i(23, 31, 2, 20)); bne(23, 0, 'ai_mirror'); bne(19, 0, 'ai_mirror'); load(23, P1_ATK); bne(23, 0, 'ai_mirror')
    load(23, AI_RANGED_CD); bne(23, 0, 'ai_mirror'); li(23, 1); e(i(23, 23, 1, 12)); e(r(27, 27, 23, 6)); li(23, 40); store(23, AI_RANGED_CD); j('p2_input_ready')

    # T_MIRROR/T_APPROACH: preserve 100..120 spacing, otherwise approach.
    mark('ai_mirror'); e(i(23, 24, 2, 100)); bne(23, 0, 'ai_retreat'); e(i(23, 24, 2, 121)); bne(23, 0, 'p2_input_ready')
    blt(8, 10, 'ai_approach_left'); e(i(12, 12, 6, 0x200)); j('p2_input_ready'); mark('ai_approach_left'); e(i(12, 12, 6, 0x100))
    mark('p2_input_ready')
    # AI scratch registers overlap the one-frame hit-pulse registers only
    # before combat; clear them at this boundary so rendering stays exact.
    li(22, 0); li(26, 0)

    # P1 horizontal movement, 2 pixels per logic tick.
    e(i(23, 12, 7, 1)); beq(23, 0, 'p1_right')
    e(i(23, 8, 2, 2)); bne(23, 0, 'p1_move_done'); e(i(8, 8, 0, -2)); li(13, 0); j('p1_move_done')
    mark('p1_right'); e(i(23, 12, 7, 2)); beq(23, 0, 'p1_move_done')
    e(i(23, 8, 2, 758)); beq(23, 0, 'p1_move_done'); e(i(8, 8, 0, 2)); li(13, 1)
    mark('p1_move_done')
    # P2 horizontal movement, S2/S1.
    e(i(23, 12, 7, 0x100)); beq(23, 0, 'p2_right')
    e(i(23, 10, 2, 2)); bne(23, 0, 'p2_move_done'); e(i(10, 10, 0, -2)); li(14, 0); j('p2_move_done')
    mark('p2_right'); e(i(23, 12, 7, 0x200)); beq(23, 0, 'p2_move_done')
    e(i(23, 10, 2, 758)); beq(23, 0, 'p2_move_done'); e(i(10, 10, 0, 2)); li(14, 1)
    mark('p2_move_done')

    # 240-pixel triangular jump: 24 frames up by 10, then 24 down by 10.
    # x3/x4 hold phase, so no CPU data-RAM dependency is involved.
    beq(3, 0, 'p1_on_ground'); e(i(24, 3, 2, 25)); nop(); bne(24, 0, 'p1_fall')
    e(i(9, 9, 0, 10)); j('p1_jump_phase_done')
    mark('p1_fall'); e(i(9, 9, 0, -10))
    mark('p1_jump_phase_done'); e(i(3, 3, 0, -1)); nop(); bne(3, 0, 'p1_jump_done'); li(9, 40); j('p1_jump_done')
    # Use the edge bitmap, not the held keyboard level: one press, one jump.
    mark('p1_on_ground'); e(i(24, 27, 7, 4)); nop(); beq(24, 0, 'p1_jump_done'); li(3, 48)
    mark('p1_jump_done')
    beq(4, 0, 'p2_on_ground'); e(i(24, 4, 2, 25)); nop(); bne(24, 0, 'p2_fall')
    e(i(11, 11, 0, 10)); j('p2_jump_phase_done')
    mark('p2_fall'); e(i(11, 11, 0, -10))
    mark('p2_jump_phase_done'); e(i(4, 4, 0, -1)); nop(); bne(4, 0, 'p2_jump_done'); li(11, 40); j('p2_jump_done')
    mark('p2_on_ground'); e(i(24, 27, 7, 0x400)); nop(); beq(24, 0, 'p2_jump_done'); li(4, 48)
    mark('p2_jump_done')

    # New melee press starts a 12-frame attack. Each attack can damage once.
    e(i(23, 27, 7, 8)); beq(23, 0, 'p1_attack_start_done'); li(23, 12); store(23, P1_ATK); li(23, 0); store(23, P1_HIT)
    mark('p1_attack_start_done')
    e(i(23, 27, 5, 11)); e(i(23, 23, 7, 1)); beq(23, 0, 'p2_attack_start_done'); li(23, 12); store(23, P2_ATK); li(23, 0); store(23, P2_HIT)
    mark('p2_attack_start_done')

    # New projectile press, 20 MP cost. Projectile Y is fixed at firing height.
    e(i(23, 27, 5, 4)); e(i(23, 23, 7, 1)); beq(23, 0, 'p1_spawn_done'); bne(16, 0, 'p1_spawn_done')
    e(i(23, 30, 2, 20)); bne(23, 0, 'p1_spawn_done'); beq(13, 0, 'p1_spawn_left'); e(i(15, 8, 0, 40)); j('p1_spawn_x_done')
    mark('p1_spawn_left'); e(i(15, 8, 0, -12)); mark('p1_spawn_x_done'); li(16, 1); e(i(17, 13, 0, 0)); e(i(30, 30, 0, -20)); e(i(23, 9, 0, 26)); store(23, P1_PY); li(23, 0); store(23, P1_PD)
    mark('p1_spawn_done')
    e(i(23, 27, 5, 12)); e(i(23, 23, 7, 1)); beq(23, 0, 'p2_spawn_done'); bne(19, 0, 'p2_spawn_done')
    e(i(23, 31, 2, 20)); bne(23, 0, 'p2_spawn_done'); beq(14, 0, 'p2_spawn_left'); e(i(18, 10, 0, 40)); j('p2_spawn_x_done')
    mark('p2_spawn_left'); e(i(18, 10, 0, -12)); mark('p2_spawn_x_done'); li(19, 1); e(i(20, 14, 0, 0)); e(i(31, 31, 0, -20)); e(i(23, 11, 0, 26)); store(23, P2_PY); li(23, 0); store(23, P2_PD)
    mark('p2_spawn_done')

    # P1 attack timer and directional body-contact hit test. Both 40x64
    # character rectangles must genuinely overlap; no extra reach is added.
    load(23, P1_ATK); beq(23, 0, 'p1_attack_done'); e(i(23, 23, 0, -1)); store(23, P1_ATK)
    load(23, P1_HIT); bne(23, 0, 'p1_attack_done'); beq(13, 0, 'p1_atk_left')
    e(r(23, 10, 8, 0, 0x20)); blt(23, 0, 'p1_attack_done'); e(i(23, 23, 2, 40)); nop(); beq(23, 0, 'p1_attack_done'); j('p1_atk_x_ok')
    mark('p1_atk_left'); e(r(23, 8, 10, 0, 0x20)); blt(23, 0, 'p1_attack_done'); e(i(23, 23, 2, 40)); nop(); beq(23, 0, 'p1_attack_done')
    mark('p1_atk_x_ok'); e(r(23, 9, 11, 0, 0x20)); abs_reg(23, 'p1_atk_y'); e(i(23, 23, 2, 64)); nop(); beq(23, 0, 'p1_attack_done')
    e(i(29, 29, 0, -5)); blt(29, 0, 'p1_atk_clamp'); j('p1_atk_damage_done'); mark('p1_atk_clamp'); li(29, 0); mark('p1_atk_damage_done'); li(26, 1); li(23, 1); store(23, P1_HIT)
    mark('p1_attack_done')
    # P2 uses the same body-contact rule.
    load(23, P2_ATK); beq(23, 0, 'p2_attack_done'); e(i(23, 23, 0, -1)); store(23, P2_ATK)
    load(23, P2_HIT); bne(23, 0, 'p2_attack_done'); beq(14, 0, 'p2_atk_left')
    e(r(23, 8, 10, 0, 0x20)); blt(23, 0, 'p2_attack_done'); e(i(23, 23, 2, 40)); nop(); beq(23, 0, 'p2_attack_done'); j('p2_atk_x_ok')
    mark('p2_atk_left'); e(r(23, 10, 8, 0, 0x20)); blt(23, 0, 'p2_attack_done'); e(i(23, 23, 2, 40)); nop(); beq(23, 0, 'p2_attack_done')
    mark('p2_atk_x_ok'); e(r(23, 11, 9, 0, 0x20)); abs_reg(23, 'p2_atk_y'); e(i(23, 23, 2, 64)); nop(); beq(23, 0, 'p2_attack_done')
    e(i(28, 28, 0, -5)); blt(28, 0, 'p2_atk_clamp'); j('p2_atk_damage_done'); mark('p2_atk_clamp'); li(28, 0); mark('p2_atk_damage_done'); li(22, 1); li(23, 1); store(23, P2_HIT)
    mark('p2_attack_done')

    # P1 projectile movement, 300-pixel range, and two-dimensional hit test.
    beq(16, 0, 'p1_proj_done'); beq(17, 0, 'p1_proj_left'); e(i(15, 15, 0, 3)); j('p1_proj_moved')
    mark('p1_proj_left'); e(i(15, 15, 0, -3)); mark('p1_proj_moved')
    load(23, P1_PD); e(i(23, 23, 0, 3)); store(23, P1_PD); e(i(24, 23, 2, 300)); beq(24, 0, 'p1_proj_off')
    blt(15, 0, 'p1_proj_off'); e(i(24, 15, 2, 800)); beq(24, 0, 'p1_proj_off')
    e(r(23, 15, 10, 0, 0x20)); abs_reg(23, 'p1_proj_x'); e(i(23, 23, 2, 52)); beq(23, 0, 'p1_proj_done')
    load(23, P1_PY); e(r(23, 23, 11, 0, 0x20)); abs_reg(23, 'p1_proj_y'); e(i(23, 23, 2, 64)); beq(23, 0, 'p1_proj_done')
    e(i(29, 29, 0, -8)); blt(29, 0, 'p1_proj_clamp'); j('p1_proj_damage_done'); mark('p1_proj_clamp'); li(29, 0); mark('p1_proj_damage_done'); li(26, 1); li(16, 0); j('p1_proj_done')
    mark('p1_proj_off'); li(16, 0); mark('p1_proj_done')
    # P2 projectile movement and hit test.
    beq(19, 0, 'p2_proj_done'); beq(20, 0, 'p2_proj_left'); e(i(18, 18, 0, 3)); j('p2_proj_moved')
    mark('p2_proj_left'); e(i(18, 18, 0, -3)); mark('p2_proj_moved')
    load(23, P2_PD); e(i(23, 23, 0, 3)); store(23, P2_PD); e(i(24, 23, 2, 300)); beq(24, 0, 'p2_proj_off')
    blt(18, 0, 'p2_proj_off'); e(i(24, 18, 2, 800)); beq(24, 0, 'p2_proj_off')
    e(r(23, 18, 8, 0, 0x20)); abs_reg(23, 'p2_proj_x'); e(i(23, 23, 2, 52)); beq(23, 0, 'p2_proj_done')
    load(23, P2_PY); e(r(23, 23, 9, 0, 0x20)); abs_reg(23, 'p2_proj_y'); e(i(23, 23, 2, 64)); beq(23, 0, 'p2_proj_done')
    e(i(28, 28, 0, -8)); blt(28, 0, 'p2_proj_clamp'); j('p2_proj_damage_done'); mark('p2_proj_clamp'); li(28, 0); mark('p2_proj_damage_done'); li(22, 1); li(19, 0); j('p2_proj_done')
    mark('p2_proj_off'); li(19, 0); mark('p2_proj_done')

    # MP recovery: one point every 30 software frames, capped at 100.
    e(i(21, 21, 0, 1)); li(23, 30); bne(21, 23, 'mp_done'); li(21, 0)
    e(i(23, 30, 2, 100)); beq(23, 0, 'p1_mp_full'); e(i(30, 30, 0, 1)); mark('p1_mp_full')
    e(i(23, 31, 2, 100)); beq(23, 0, 'mp_done'); e(i(31, 31, 0, 1)); mark('mp_done')

    # Medicine spawn, lifetime, and pickup. Position is CPU-selected and can
    # later be replaced by a software PRNG without changing the VGA hardware.
    li(27, 0)  # Reuse the edge register as a one-frame medicine-pickup pulse.
    load(23, MED_ACTIVE); bne(23, 0, 'medicine_live')
    load(23, MED_SPAWN); e(i(23, 23, 0, 1)); store(23, MED_SPAWN); li(24, 600); bne(23, 24, 'medicine_done')
    li(23, 0); store(23, MED_SPAWN); li(23, 1); store(23, MED_ACTIVE); li(23, 480); store(23, MED_LIFE)
    # Software xorshift PRNG: the random state lives in CPU data RAM, not HDL.
    load(23, RAND_SEED); e(i(24, 23, 1, 7)); e(r(23, 23, 24, 4)); e(i(24, 23, 5, 9)); e(r(23, 23, 24, 4)); e(i(24, 23, 1, 8)); e(r(23, 23, 24, 4)); store(23, RAND_SEED)
    # Keep medicine within Y=40..231 so every spawn is reachable in one jump.
    e(i(23, 23, 7, 191)); e(i(23, 23, 0, 40)); store(23, MED_Y); li(23, 390); store(23, MED_X); j('medicine_done')
    mark('medicine_live'); load(23, MED_LIFE); e(i(23, 23, 0, -1)); store(23, MED_LIFE); beq(23, 0, 'medicine_off')
    load(23, MED_X); e(r(24, 8, 23, 0, 0x20)); abs_reg(24, 'med_p1_x'); e(i(24, 24, 2, 40)); beq(24, 0, 'med_p2_check')
    load(24, MED_Y); e(r(24, 9, 24, 0, 0x20)); abs_reg(24, 'med_p1_y'); e(i(24, 24, 2, 64)); beq(24, 0, 'med_p2_check')
    e(i(28, 28, 0, 5)); e(i(24, 28, 2, 101)); bne(24, 0, 'med_p1_hp_ok'); li(28, 100); mark('med_p1_hp_ok'); li(27, 1); j('medicine_off')
    mark('med_p2_check'); load(23, MED_X); e(r(24, 10, 23, 0, 0x20)); abs_reg(24, 'med_p2_x'); e(i(24, 24, 2, 40)); beq(24, 0, 'medicine_done')
    load(24, MED_Y); e(r(24, 11, 24, 0, 0x20)); abs_reg(24, 'med_p2_y'); e(i(24, 24, 2, 64)); beq(24, 0, 'medicine_done')
    e(i(29, 29, 0, 5)); e(i(24, 29, 2, 101)); bne(24, 0, 'med_p2_hp_ok'); li(29, 100); mark('med_p2_hp_ok'); li(27, 1)
    mark('medicine_off'); li(23, 0); store(23, MED_ACTIVE); mark('medicine_done')

    # HP zero starts a five-second result screen and awards one software score.
    beq(28, 0, 'p2_wins'); beq(29, 0, 'p1_wins'); j('render')
    mark('p2_wins'); e(i(2, 2, 0, 1)); li(3, 0); li(4, 0); li(23, 1); store(23, ROUND_WINNER); li(23, 625); store(23, ROUND_TIMER); li(16, 0); li(19, 0); j('render')
    mark('p1_wins'); e(i(1, 1, 0, 1)); li(3, 0); li(4, 0); li(23, 0); store(23, ROUND_WINNER); li(23, 625); store(23, ROUND_TIMER); li(16, 0); li(19, 0); j('render')

    mark('render')
    # Position writes: low 11 bits X, bits [26:16] Y.
    e(i(23, 9, 1, 16)); e(r(23, 23, 8, 6)); nop(); e(s(23, 5, 2, 0))
    e(i(23, 11, 1, 16)); e(r(23, 23, 10, 6)); nop(); e(s(23, 5, 2, 4))
    # Status packing: P1 HP, P2 HP, P1 MP, P2 MP.
    e(i(23, 31, 1, 23)); nop(); e(i(24, 30, 1, 16)); nop(); e(r(23, 23, 24, 6)); nop()
    e(i(24, 29, 1, 8)); nop(); e(r(23, 23, 24, 6)); nop(); e(r(23, 23, 28, 6)); nop(); e(s(23, 5, 2, 8))
    # Render flags contain only CPU state: direction, active attack, jump,
    # hit pulses, projectiles, scores, round result, and medicine.
    li(24, 0); e(r(24, 24, 13, 6)); e(i(23, 14, 1, 1)); e(r(24, 24, 23, 6))
    load(23, P1_ATK); beq(23, 0, 'flag_p1_atk_done'); e(i(24, 24, 6, 4)); mark('flag_p1_atk_done')
    load(23, P2_ATK); beq(23, 0, 'flag_p2_atk_done'); e(i(24, 24, 6, 8)); mark('flag_p2_atk_done')
    beq(3, 0, 'flag_p1_jump_done'); e(i(24, 24, 6, 16)); mark('flag_p1_jump_done')
    beq(4, 0, 'flag_p2_jump_done'); e(i(24, 24, 6, 32)); mark('flag_p2_jump_done')
    e(i(23, 22, 1, 6)); e(r(24, 24, 23, 6)); e(i(23, 26, 1, 7)); e(r(24, 24, 23, 6))
    e(i(23, 16, 1, 8)); e(r(24, 24, 23, 6)); e(i(23, 19, 1, 9)); e(r(24, 24, 23, 6))
    e(i(23, 17, 1, 10)); e(r(24, 24, 23, 6)); e(i(23, 20, 1, 11)); e(r(24, 24, 23, 6))
    e(i(23, 1, 1, 16)); e(r(24, 24, 23, 6)); e(i(23, 2, 1, 20)); e(r(24, 24, 23, 6))
    load(23, ROUND_TIMER); beq(23, 0, 'flag_round_done'); li(23, 1); e(i(23, 23, 1, 12)); e(r(24, 24, 23, 6)); load(23, ROUND_WINNER); e(i(23, 23, 1, 13)); e(r(24, 24, 23, 6)); mark('flag_round_done')
    # Menu/match bits are produced by RISC-V; VGA only renders those states.
    load(23, MENU_STAGE); bne(23, 0, 'flag_mode_done'); li(23, 1); e(i(23, 23, 1, 26)); e(r(24, 24, 23, 6)); mark('flag_mode_done')
    load(23, MENU_SELECT); e(i(23, 23, 1, 27)); e(r(24, 24, 23, 6))
    load(23, MENU_STAGE); li(26, 1); bne(23, 26, 'flag_time_done'); li(23, 1); e(i(23, 23, 1, 28)); e(r(24, 24, 23, 6)); mark('flag_time_done')
    load(23, MENU_STAGE); li(26, 3); bne(23, 26, 'flag_timeout_done'); li(23, 1); e(i(23, 23, 1, 29)); e(r(24, 24, 23, 6)); mark('flag_timeout_done')
    load(23, IRQ_SCREEN); beq(23, 0, 'flag_irq_done'); li(23, 1); e(i(23, 23, 1, 30)); e(r(24, 24, 23, 6)); mark('flag_irq_done')
    load(23, MENU_STAGE); li(26, 2); bne(23, 26, 'flag_game_active_done'); li(23, 1); e(i(23, 23, 1, 31)); e(r(24, 24, 23, 6)); mark('flag_game_active_done')
    load(23, MED_ACTIVE); beq(23, 0, 'flag_med_done'); li(23, 1); e(i(23, 23, 1, 24)); e(r(24, 24, 23, 6)); mark('flag_med_done')
    e(i(23, 27, 1, 25)); e(r(24, 24, 23, 6)); nop(); e(s(24, 5, 2, 12))
    # Projectile and medicine position writes.
    load(23, P1_PY); e(i(23, 23, 1, 16)); e(r(23, 23, 15, 6)); nop(); e(s(23, 5, 2, 20))
    load(23, P2_PY); e(i(23, 23, 1, 16)); e(r(23, 23, 18, 6)); nop(); e(s(23, 5, 2, 24))
    load(23, MED_Y); e(i(23, 23, 1, 16)); load(26, MED_X); e(r(23, 23, 26, 6)); nop(); e(s(23, 5, 2, 28))
    load(23, TIME_SECONDS); nop(); e(s(23, 5, 2, 32))
    e(i(25, 12, 0, 0))
    # Fixed delay makes one iteration approximately a 50-60 Hz game frame.
    e(u(26, 5)); e(i(26, 26, 0, -480)); mark('delay'); e(i(26, 26, 0, -1)); bne(26, 0, 'delay'); j('loop')

    # Long report routine, entered only from the safe game-loop boundary.
    mark('perf_report')
    store(1, IRQ_SAVE_X1); store(18, IRQ_SAVE_X18); store(19, IRQ_SAVE_X19); store(20, IRQ_SAVE_X20); store(21, IRQ_SAVE_X21)
    store(22, IRQ_SAVE_X22); store(23, IRQ_SAVE_X23); store(24, IRQ_SAVE_X24)
    store(25, IRQ_SAVE_X25); store(26, IRQ_SAVE_X26); store(27, IRQ_SAVE_X27)
    store(29, IRQ_SAVE_X29); store(30, IRQ_SAVE_X30)
    store(31, IRQ_SAVE_X31)
    # Make the VGA black immediately; the regular game loop maintains it for
    # six seconds after mret through IRQ_SCREEN/game_flags[30].
    e(u(23, 0x40000)); nop(); e(s(23, 5, 2, 12))
    e(u(30, 0x10010))
    for mmio_off, ram_off in ((0x20, PERF_CYC_S), (0x24, PERF_INST_S),
                              (0x28, PERF_ACC_S), (0x2c, PERF_HIT_S),
                              (0x30, PERF_MISS_S), (0x34, PERF_MODE_S),
                              (0x38, PERF_STALL_S), (0x3c, PERF_BRANCH_S),
                              (0x40, PERF_BPM_S), (0x44, PERF_MEMORY_S),
                              (0x48, PERF_MEXT_S), (0x4c, PERF_MAC_S),
                              (0x50, PERF_MULCYC_S)):
        e(lw(21, 30, mmio_off)); nop(); store(21, ram_off)

    put_text('[GAME CPU PERF]\r\n')
    print_metric('MODE', PERF_MODE_S)
    print_metric('CYC', PERF_CYC_S); print_metric('INST', PERF_INST_S)
    print_ratio100('CPI', PERF_CYC_S, PERF_INST_S, 'ratio_cpi')
    # At 5 MHz, MIPS*100 = INST*500/CYC. Use quotient/remainder form so the
    # multiplication cannot overflow during a long match.
    put_text('MIPS='); e(lw(21, 7, PERF_INST_S)); nop(); e(lw(22, 7, PERF_CYC_S)); nop()
    beq(22, 0, 'mips_zero'); e(r(24, 21, 22, 5, 1)); e(r(25, 21, 22, 7, 1))
    li(23, 500); e(r(24, 24, 23, 0, 1)); e(u(26, 0x00800)); bltu(22, 26, 'mips_exact')
    e(r(22, 22, 23, 5, 1))
    bne(22, 0, 'mips_den_ok'); li(22, 1)
    mark('mips_den_ok'); e(r(25, 25, 22, 5, 1)); e(r(21, 24, 25, 0)); j('mips_print')
    mark('mips_exact'); e(r(25, 25, 23, 0, 1)); e(r(25, 25, 22, 5, 1)); e(r(21, 24, 25, 0)); j('mips_print')
    mark('mips_zero'); li(21, 0); mark('mips_print'); call('perf_fixed2'); put_text('\r\n')
    print_metric('STALL', PERF_STALL_S)
    print_metric('BR', PERF_BRANCH_S); print_metric('BPM', PERF_BPM_S)
    print_ratio100('BPMR', PERF_BPM_S, PERF_BRANCH_S, 'ratio_bpmr', 10000)
    # This five-stage implementation flushes IF/ID and ID/EX on a miss.
    put_text('BP_PENALTY_CYC='); e(lw(21, 7, PERF_BPM_S)); nop(); e(i(21, 21, 1, 1))
    call('perf_dec32'); put_text('\r\n')
    print_metric('MEM', PERF_MEMORY_S)
    print_metric('ICACC', PERF_ACC_S); print_metric('ICHIT', PERF_HIT_S)
    print_metric('ICMISS', PERF_MISS_S)
    print_ratio100('ICHR', PERF_HIT_S, PERF_ACC_S, 'ratio_ichr', 10000)
    print_ratio100('ICMR', PERF_MISS_S, PERF_ACC_S, 'ratio_icmr', 10000)
    print_metric('RV32M', PERF_MEXT_S); print_metric('MAC', PERF_MAC_S)
    print_metric('MULCYC', PERF_MULCYC_S)
    put_text('IC_MISS_PENALTY=0\r\n[D-CACHE NOT IMPLEMENTED]\r\n')

    li(23, 751)
    e(s(23, 7, 2, IRQ_SCREEN))
    load(31, IRQ_SAVE_X31); load(30, IRQ_SAVE_X30); load(29, IRQ_SAVE_X29)
    load(27, IRQ_SAVE_X27); load(26, IRQ_SAVE_X26)
    load(25, IRQ_SAVE_X25); load(24, IRQ_SAVE_X24); load(23, IRQ_SAVE_X23)
    load(22, IRQ_SAVE_X22); load(21, IRQ_SAVE_X21); load(20, IRQ_SAVE_X20)
    load(19, IRQ_SAVE_X19); load(18, IRQ_SAVE_X18); load(1, IRQ_SAVE_X1)
    j('render')

    # Decimal printer. x21=value; all scratch registers are preserved by the
    # interrupt prologue, and x28 holds this routine's return address.
    mark('perf_dec32'); e(i(18, 1, 0, 0)); li(27, 0)
    e(u(24, 0x3B9AD)); e(i(24, 24, 0, -1536)); li(25, 10)
    mark('perf_dec_loop')
    e(r(22, 21, 24, 5, 1)); e(r(21, 21, 24, 7, 1))
    bne(22, 0, 'perf_dec_emit'); beq(27, 0, 'perf_dec_skip')
    mark('perf_dec_emit'); li(27, 1); e(i(20, 22, 0, 48)); call('perf_putc')
    mark('perf_dec_skip'); e(r(24, 24, 25, 5, 1)); bne(24, 0, 'perf_dec_loop')
    bne(27, 0, 'perf_dec_done'); li(20, 48); call('perf_putc')
    mark('perf_dec_done'); e(i(1, 18, 0, 0)); e(i(0, 1, 0, 0, 0x67))

    # Print x21, which is scaled by 100, as an ordinary decimal with exactly
    # two fractional digits (for example 160 -> 1.60).
    mark('perf_fixed2'); e(i(19, 1, 0, 0)); li(23, 100)
    e(r(22, 21, 23, 5, 1)); e(r(26, 21, 23, 7, 1)); e(i(21, 22, 0, 0)); call('perf_dec32')
    li(20, 46); call('perf_putc'); li(23, 10)
    e(r(22, 26, 23, 5, 1)); e(i(20, 22, 0, 48)); call('perf_putc')
    e(r(22, 26, 23, 7, 1)); e(i(20, 22, 0, 48)); call('perf_putc')
    e(i(1, 19, 0, 0)); e(i(0, 1, 0, 0, 0x67))

    mark('perf_putc')
    mark('perf_uart_wait'); e(lw(29, 30, 4)); nop(); e(i(29, 29, 7, 1))
    bne(29, 0, 'perf_uart_wait'); e(s(20, 30, 2, 0)); e(i(0, 1, 0, 0, 0x67))

    # Minimal interrupt handler: post a request and return immediately. Keeping
    # UART formatting out of the trap context prevents corruption of live game
    # registers such as x28 (P1 HP).
    mark('irq_handler')
    store(23, IRQ_SAVE_X23); store(24, IRQ_SAVE_X24)
    li(23, 1); store(23, IRQ_REQUEST)
    load(24, IRQ_SAVE_X24); load(23, IRQ_SAVE_X23)
    e(0x30200073)  # mret

    for index, kind, a, b, funct3, target in fix:
        address = labels[target] * 4
        if kind == 'u':
            c[index] = u(a, (address + 0x800) >> 12)
        elif kind == 'i':
            high = ((address + 0x800) >> 12) << 12
            c[index] = i(a, a, 0, address - high)
        else:
            off = (labels[target] - index) * 4
            if kind == 'b' and not -4096 <= off <= 4094:
                raise ValueError(f'branch to {target} out of range: {off}')
            c[index] = br(a, b, funct3, off) if kind == 'b' else jal(1 if kind == 'c' else 0, off)
    return c


def main():
    words = build()
    if len(words) > 2048:
        raise ValueError(f'program too large: {len(words)} words')
    words += [0x00000013] * (2048 - len(words))
    out = Path(__file__).resolve().parents[1] / 'test_programs' / 'game_cpu_full.hex'
    out.write_text('\n'.join(f'{word:08X}' for word in words) + '\n', encoding='ascii')
    print(f'wrote {out} ({len(words)} words)')


if __name__ == '__main__':
    main()

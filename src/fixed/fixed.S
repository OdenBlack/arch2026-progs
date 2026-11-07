# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:

     li t1, 0                     # 初始化進行次數計數器為 0
    beq     a1, zero, .Lop1_done

# a0 : a, a1 : b
.op1_loop:

    and     t0, a0, a1             # t0 = a0 & a1
    slli    t0, t0, 1              # t0 左移 1 位，得到 carry

    xor     a0, a0, a1             # a0 = a0 ^ a1
    addi    a1, t0, 0              # a1 = t0

    addi    t1, t1, 1              # t1 加 1

    bne     a1, zero, .op1_loop

.Lop1_done:
    sw      t1, 0(a2)
    ret
    .size   op1_asm, .-op1_asm     # 告訴編譯器 op1_asm 函式有多大，單位是位元組

#   ---------------------

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

#   ---------------------

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2

op3_asm:
    and     t0, a0, a1
    andi    t0, t0, 1
    srli    a0, a0, 1
    srli    a1, a1, 1
    add     a1, a1, t0
    add     a0, a0, a1
    ret
.size   op3_asm, .-op3_asm

#   ---------------------

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2


q_mul_asm:
    # t3 = negative    
    # 如果正負號不一樣，兩者的 MSB 取 XOR 將會等於 1
    xor     t3, a0, a1

    # 讓 a, b 變成絕對值
    bge   a0, zero, is_b_negative
    sub     a0, zero, a0
    

is_b_negative:
    bge     a1, zero, prepare_lo_li
    sub     a1, zero, a1


prepare_lo_li:
    li      t0, 0       # mul_hi = 0
    li      t1, 0       # prod_lo = 0
    li      t2, 0       # prod_hi = 0
    beq     a1, zero, restore_symbol


q_mul_loop:    
    # if (ub & 1u)
    andi    t4, a1, 1
    beq     t4, zero, q_mul_loop_2

    # if 成立後之運算
    add     t1, t1, a0      
    sltu    t5, t1, a0      # 無號比較：新 prod_lo < 加數 a0 ?
    add     t2, t2, t0      # prod_hi += mul_hi
    add     t2, t2, t5      # prod_hi += (prod_lo <  old_lo)

    # if 內容結束，可進入迴圈的第 2 部分


q_mul_loop_2:
    srli    t4, a0, 31      # 暫存 mul_lo 原本的最高位
    slli    t0, t0, 1       #  (mul_hi << 1)
    or      t0, t0, t4      #  mul_hi
    
    # mul_lo <<= 1;
    slli    a0, a0, 1      #  mul_lo <<= 1;

    # ub >>= 1;
    srli    a1, a1, 1
    
    bne    a1, zero, q_mul_loop


# 還原乘積的正負號
restore_symbol:
    bge     t3, zero, round

    # -1 的立即數會被符號延伸成全為 1 的位元
    xori    t1, t1, -1      # 低半部逐位取反
    xori    t2, t2, -1      # 高半部逐位取反
    

    # 低半部 + 1，然後確認是否有進位傳到高半部
    add     t4, zero, t1  # 低半部尚未 + 1
    addi    t1, t1,   1
    bltu    t1, t4, ho_add_carry
    j       round

ho_add_carry:
    addi    t2, t2, 1

round:
    li      t4, 1
    slli    t4, t4, 19

    add     t5, zero, t1  # 低半部尚未加上補償值
    add     t1, t1, t4
    bltu    t1, t5, ho_add_carry_2
    j       round_2       # 沒有進位，跳過高半部加一

ho_add_carry_2:
    addi    t2, t2, 1

round_2:
    
    srli    t1, t1, 20
    slli    t2, t2, 12
    or     a0, t1, t2

    ret
    .size   q_mul_asm, .-q_mul_asm

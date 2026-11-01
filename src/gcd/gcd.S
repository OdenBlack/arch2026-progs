    .text
    .globl gcd_u32_asm
    .type gcd_u32_asm, @function

#   a0 預設為 a, a1 預設為 b
gcd_u32_asm:
    /* if (a == 0) return b;*/
    beq a0, zero, .Lreturn_b

    /* if (b == 0) return a;*/
    beq a1, zero, .Lreturn_a

    # 前往兩個輸入都不是零的處理區
    jal zero, .Lnonzero

.Lreturn_b:
    # 回傳值必須放在 a0
    addi a0, a1, 0

.Lreturn_a:
    # 返回呼叫者
    jalr zero, 0(ra)

.Lnonzero:
    # unsigned common_twos = 0;
    addi t0, zero, 0

.Lcommon_loop:
    # 判斷 ((a | b) & 1u)
    or   t1, a0, a1
    andi t1, t1, 1

    # 結果不等於零：至少一個是奇數
    bne t1, zero, .Lmain_loop

    # 兩個都是偶數：各除以 2
    srli a0, a0, 1
    srli a1, a1, 1

    # common_twos++
    addi t0, t0, 1

    # 回到迴圈開頭
    jal zero, .Lcommon_loop

.Lmain_loop:
    # 實作 C 版本的主迴圈
    # t0 = common_twos，t1 用於奇偶判斷
    beq  a0, zero, .Times_two_power
    beq  a1, zero, .Times_two_power

    # 三個if用3個helper
    andi  t1, a0, 1
    beq   t1, zero, a_even
    andi  t1, a1, 1
    beq   t1, zero, b_even
    bltu  a0, a1,   b_larger
    sub   a0, a0, a1
    j     .Lmain_loop

a_even:
    srli a0, a0, 1
    j    .Lmain_loop

b_even:
    srli a1, a1, 1
    j    .Lmain_loop

b_larger:
    sub  a1, a1, a0
    j    .Lmain_loop

.Times_two_power:
    # a 非零時，直接用 a0 作為結果。
    bne a0, zero, .Lrestore

    # a 為零時，改用 b。
    addi a0, a1, 0

.Lrestore:
    # a0 = gcd << common_twos
    sll a0, a0, t0

    # 返回呼叫者。
    jalr zero, 0(ra)

    .size gcd_u32_asm, .-gcd_u32_asm  /*提供函式大小資訊的組譯指示，不是 CPU 執行的指令*/

#   最後的 a0 為 gcd 輸出

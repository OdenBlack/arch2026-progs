# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    # a0：輸入編碼／回傳結果
    # t0：指數欄位
    # t1：比較常數／保留部分的最低位元
    # t2：捨入補償

    # exponent = (f32bits >> 23) & 0xFF
    srli    t0, a0, 23
    andi    t0, t0, 0xFF

    # NaN 與無限大直接取高 16 位，不進行捨入補償
    li      t1, 0xFF
    beq     t0, t1, .Lbf16_f32_pack

    # retained_lsb
    srli    t1, a0, 16
    andi    t1, t1, 1

    # rounding_bias 捨入補償
    # addi 的立即數範圍只有 −2048～2047
    # 只能把 0x7FFFu 存到 t2 中
    li     t2,  0x7FFF      # 0x7FFFu + retained_lsb
    add    t2, t2, t1

    # rounding_bias 加到 a0
    add     a0, a0, t2

.Lbf16_f32_pack:
    srli    a0, a0, 16
    ret

    .size   bf16_from_f32_asm, .-bf16_from_f32_asm


# ---------------------------------

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:

    # 1. 取出各資訊
    # a0 : a, a1 : b
    # t0 : sign_a, t1 : sign_b
    # t2 : exp_a, t3 : exp_b
    # t4 : frac_a, t5 : frac_b
    # t6 : result_sign

    srli    t0, a0, 15      # sign_a
    srli    t1, a1, 15      # sign_b

    srli    t2, a0, 7
    andi    t2, t2, 255     # exp_a
    srli    t3, a1, 7
    andi    t3, t3, 255     # exp_b

    andi    t4, a0, 127     # frac_a
    andi    t5, a1, 127     # frac_b

    xor     t6, t0, t1      # result_sign

    # 2. 依序處理 a、b 的 NaN、無限大, 以及零
    li      a4, 0xFF
    beq     t2, a4, a_nan_or_inf
    beq     t3, a4, b_nan_or_inf

    or      a0, t2, t4  #  a 為零，回傳符號相乘後的零
    beq     a0, zero, a_or_b_zero
    or      a0, t3, t5  #  b 為零，回傳符號相乘後的零
    beq     a0, zero, a_or_b_zero

    # 3. 將非零有限值整理成 (sig / 128) * 2^e
    # a0 : sig_a, a1 : sig_b
    # a2 : e_a, a3 : e_b

sig_and_e_of_a:
    # 處理 a
    ori     a0, t4, 0x80
    addi    a2, t2, -127
    bne     t2, zero, sig_and_e_of_b    # 若 a 的 exp 部分不為 0, 則使用正規數的部分處理
    add     a0, t4, zero
    li      a2, -126

sig_and_e_of_a_loop:
    slli    a0, a0, 1     # sig_a 持續左移，直到 sig_a 至少為 128
    addi    a2, a2, -1    # sig_a 左移, 指數減 1, 剛好抵銷
    li      a4, 0x80
    bltu    a0, a4, sig_and_e_of_a_loop

sig_and_e_of_b:
    # 處理 b
    ori     a1, t5, 0x80
    addi    a3, t3, -127
    bne     t3, zero, product_and_result_e   # 若 b 的 exp 部分不為 0, 則使用正規數的部分處理
    add     a1, t5, zero
    li      a3, -126

sig_and_e_of_b_loop:
    slli    a1, a1, 1   # sig_b 持續左移，直到 sig_b 至少為 128
    addi    a3, a3, -1  # sig_b 左移, 指數減 1, 剛好抵銷
    li      a4, 0x80
    blt     a1, a4, sig_and_e_of_b_loop

product_and_result_e:
    # 4. 有效數相乘，實際指數相加。
    # a0 : product = sig_a * sig_b，需要用位元運算代替乘法
    # a1 : result_e
    # bf16_mul_asm 中的 t0~t5 不會再用到，可以用來當臨時值的暫存器

    add     t0, a0, zero    # 移動 sig_a 到 t0
    add     t1, a1, zero    # 移動 sig_b 到 t1
    li      a0, 0           # product 初始值為 0
    add     a1, a2, a3      # 複寫 a1 = e_a + e_b

product_loop:
    # 被乘數 : t0，乘數 : t1
    # 判斷乘數 t1 是否為奇數
    # 若乘數最低位為 1，累加目前被乘數。
    # 每輪將被乘數左移一位、乘數右移一位，直到乘數為零。
    beq     t1, zero, bf16_mul_asm_2
    andi    t2, t1, 1
    beq     t2, zero, product_shift
    add     a0, a0, t0

product_shift:
    slli    t0, t0, 1
    srli    t1, t1, 1
    j       product_loop

bf16_mul_asm_2:
    # a0 : product, a1 : result_e
    # 若 1 <= product/16384 < 2, 不需調整。
    # 若 2 <= product/16384 < 4, 相乘後 sig 除以 2, 指數加 1。
    li      t0, 0x8000
    bgeu    a0, t0, divid_16384

    # 5. 轉回 BF16 表示法
    # a2 : result_sig = product >> 7
    # a3 : result_exp = result_e + 127
    # a4 : sign_bits
    srli    a2, a0, 7
    addi    a3, a1, 127
    slli    a4, t6, 15

    li      t0, 255
    bge     a3, t0, result_exp_larger_254

    # 如果過小, 轉成非正規化數，或帶符號的零
    bge     zero, a3, denormalize

    # 輸出一般正規化結果
    slli    a3, a3, 7
    or      a0, a4, a3
    andi    a2, a2, 0x7F
    or      a0, a0, a2
    j       bf16_mul_asm_done

a_nan_or_inf:
    # 如果 a 是 NAN, 直接回傳 a
    bne     t4, zero, bf16_mul_asm_done

    # 若 a 為無限大, b 為正零或負零, 回傳 NAN
    or      a0, t3, t5
    beq     a0, zero, a_inf_b_zero

    slli    t6, t6, 15
    or      a0, zero, t6
    li      t0, 0x7F80u
    or      a0, a0, t0
    j       bf16_mul_asm_done

a_inf_b_zero:
    li      a0, 0x7FC0
    j       bf16_mul_asm_done

b_nan_or_inf:
    # 如果 b 是 NAN, 直接回傳 b
    add     a0, zero, a1
    bne     t5, zero, bf16_mul_asm_done

    # 若 b 為無限大, a 為正零或負零, 回傳 NAN
    or      a0, t2, t4
    beq     a0, zero, b_inf_a_zero

    slli    t6, t6, 15
    or      a0, zero, t6
    li      t0, 0x7F80u
    or      a0, a0, t0
    j       bf16_mul_asm_done

b_inf_a_zero:
    li      a0, 0x7FC0
    j       bf16_mul_asm_done

a_or_b_zero:
    slli    a0, t6, 15
    j       bf16_mul_asm_done

divid_16384:
    srli    a0, a0, 1
    addi    a1, a1, 1
    j bf16_mul_asm_2

result_exp_larger_254:
    li      a0, 0x7F80
    or      a0, a0, a4
    j       bf16_mul_asm_done

denormalize:
    li      t0, -6
    blt     a3, t0, return_sign_bits

    # 配合測試：先移除隱含位元，再右移。
    andi    t0, a2, 0x7F
    li      t1, 1
    sub     t1, t1, a3
    srl     a2, t0, t1

    # 非正規化數的指數欄位為零。
    or      a0, a4, a2
    j       bf16_mul_asm_done

return_sign_bits:
    add     a0, zero, a4
    j       bf16_mul_asm_done

bf16_mul_asm_done:
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm


# ---------------------------------------

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2



bf16_sqrt_asm:
    # 1. 取出各資訊
    # a0：輸入／回傳結果
    # t0：符號欄位／臨時值
    # t1：指數欄位
    # t2：小數欄位
    # t3：臨時值
    # a1：有效數 sig
    # a2：實際指數 e／平方根指數 result_e

    srli    t0, a0, 15
    srli    t1, a0, 7
    andi    t1, t1, 0xFF
    andi    t2, a0, 0x7F

    # 2. 處理 a 的特殊值
    # 若 a 為正零或負零，回傳正零
    or      t3, t1, t2
    beq     t3, zero, .Lbf16_sqrt_zero

    # 若 a 為 NAN 或無限大，進入 .Lbf16_sqrt_special 處理
    li      t3, 0xFF
    beq     t1, t3, .Lbf16_sqrt_special

    # 已排除零、NaN 與無限大；負的非零有限值回傳 NaN
    li      t3, 0x1
    beq     t0, t3, .Lbf16_sqrt_nan

    # 若 a 為正的非正規化數，回傳正零
    beq     t1, zero, .Lbf16_sqrt_zero

    # 3. 取得正規化數的有效數與實際指數。
    # a1：有效數 sig
    # a2：實際指數 e
    ori     a1, t2, 0x80     # sig = frac | 0x80
    addi    a2, t1, -127

    # 4. 進行開根號
    # 先將奇數次方項化為偶數
    andi    t3, a2, 0x1
    beq     t3, zero, .Lbf16_sqrt_binary_search
    slli    a1, a1, 1
    addi    a2, a2, -1

.Lbf16_sqrt_binary_search:
    # a2: result_e : 平方根後指數項除以 2
    srai    a2, a2, 1        # result_e = e / 2，保留負數符號

    # 使用二分搜尋法搜尋 mid
    # a3：low = 90u
    # a4：high = 256u
    # a5：root = 0u
    # t1：mid
    # t2：square
    # t3, t4, t5：可當臨時值
    li      a3, 90
    li      a4, 256
    li      a5, 0

.Lbf16_sqrt_binary_search_loop:
    #  mid = low + ((high - low) >> 1)
    sub     t1, a4, a3
    srli    t1, t1, 1
    add     t1, t1, a3

    # square = (mid * mid) >> 7
    # 迴圈處理 mid * mid
    # 每次搜尋都重新計算 mid * mid
    li      t2, 0
    add     t3, t1, zero
    add     t4, t1, zero

.Lbf16_sqrt_product_loop:
    beq     t4, zero, .Lbf16_sqrt_binary_search_loop_2

    andi    t5, t4, 1
    beq     t5, zero, .Lbf16_sqrt_product_shift
    add     t2, t2, t3

.Lbf16_sqrt_product_shift:
    slli    t3, t3, 1
    srli    t4, t4, 1
    j       .Lbf16_sqrt_product_loop

.Lbf16_sqrt_binary_search_loop_2:
    # 計算完 (mid * mid) 要右移 7
    srli    t2, t2, 7

    ble     t2, a1, .Lbf16_sqrt_mid_qualified
    addi    a4, t1, -1
    ble     a3, a4, .Lbf16_sqrt_binary_search_loop
    j       .Lbf16_sqrt_normalize

.Lbf16_sqrt_mid_qualified:
    add     a5, t1, zero
    addi    a3, t1, 1
    ble     a3, a4, .Lbf16_sqrt_binary_search_loop

.Lbf16_sqrt_normalize:
    # a2 : result_exp
    # result_exp = result_e + 127
    addi    a2, a2, 127
    slli    a2, a2, 7
    andi    a5, a5, 0x7Fu
    or      a0, a2, a5
    j       .Lbf16_sqrt_return

.Lbf16_sqrt_special:
    # 指數已確定為 255：
    # 小數非零 → 原樣回傳 a0
    # 否則符號為 1 → 回傳 NaN
    # 否則 → 正無限大，原樣回傳 a0
    bne     t2, zero, .Lbf16_sqrt_return
    bne     t0, zero, .Lbf16_sqrt_nan
    j       .Lbf16_sqrt_return

.Lbf16_sqrt_zero:
    li      a0, 0
    ret

.Lbf16_sqrt_nan:
    li      a0, 0x7FC0
    ret

.Lbf16_sqrt_return:
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm

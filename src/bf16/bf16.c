#include "bf16.h"

uint16_t bf16_from_f32(uint32_t f32bits)
{
    /* 1. 從 f32 取出 exponent 的部分*/
    uint32_t exponent = (f32bits >> 23) & 0xFFu;  //  0xffu 最低八個位元皆為 1

    /* 2. 如果 exponent 全為 1, 代表 NaN 與無限大, 則直接回傳高 16 位 */
    if (exponent == 0xFFu) {
        return (uint16_t) (f32bits >> 16);
    }

    /* 3. 加上捨入補償，再取得高 16 位  */
    uint32_t retained_lsb =
        (f32bits >> 16) & 1u;  // 用高位元半部的 LSB 確認是否為偶數
    uint32_t rounding_bias =
        0x7FFFu + retained_lsb;  // 捨入補償 (根據奇偶性選擇 0x7FFF 或者 0x8000)

    return (uint16_t) ((f32bits + rounding_bias) >>
                       16);  // 加上捨入補償，然後捨棄掉低位元半部
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    /* 1. 取出各資訊 */
    uint16_t sign_a = a >> 15;
    uint32_t sign_b = b >> 15;

    uint32_t exp_a = (a >> 7) & 0xFFu;
    uint32_t exp_b = (b >> 7) & 0xFFu;

    uint32_t frac_a = a & 0x7Fu;
    uint32_t frac_b = b & 0x7Fu;

    uint32_t result_sign = sign_a ^ sign_b;  // 乘法後符號 =  sign_a xor sign_b

    /* 2. 依序處理 a、b 的 NaN、無限大, 以及零 */

    // a 是 NAN 或無限大
    if (exp_a == 0xFF) {
        // 如果 a 是 NAN, 直接回傳 a
        if (frac_a)
            return a;

        // 若 a 為無限大, b 為正零或負零, 回傳 NAN
        if (exp_b == 0u && frac_b == 0u)
            return 0x7FC0u;  // 回傳 0 11111111 1000000 的 NAN

        // 若 a 為無限大, b 為 NAN、正負無限大或非零有限值 ,
        // 回傳帶有乘積符號的無限大
        return (uint16_t) ((result_sign << 15) |
                           0x7F80u);  // 回傳 (s bit) 11111111 0000000 的無限大
    }

    // a 非 NAN 或無限大, 但是 b 是 NAN 或無限大
    if (exp_b == 0xFF) {
        // 如果 b 是 NAN, 直接回傳 b
        if (frac_b)
            return b;

        // b 為無限大, a 為正零或負零, 回傳 NAN
        if (exp_a == 0u && frac_a == 0u)
            return 0x7FC0u;  // 回傳 0 11111111 1000000 的 NAN

        // 若 b 為無限大, a 為非零有限值 , 回傳帶有乘積符號的無限大
        return (uint16_t) ((result_sign << 15) |
                           0x7F80u);  // 回傳 (s bit) 11111111 0000000 的無限大
    }

    // a 和 b 皆為有限值，但 a、b 其中有零，回傳符號相乘後的零
    if ((exp_a == 0u && frac_a == 0u) || (exp_b == 0u && frac_b == 0u)) {
        return (uint16_t) (result_sign << 15);
    }

    /* 3. 將非零有限值整理成 (sig / 128) * 2^e */

    // 對於正規化數 (exp_a != 0) : ((128 + frac_a) / 128) * 2^(exp_a - 127)
    // 對於非正規化數 (exp_a == 0) : (frac_a / 128) * 2^(-126)
    uint32_t sig_a;
    uint32_t sig_b;
    int32_t e_a;
    int32_t e_b;

    // 處理 a
    if (exp_a != 0u) {  // 若 a 的 exp 部分不為 0, 則使用正規數的部分處理
        sig_a = frac_a | 0x80u;
        e_a = (int32_t) exp_a - 127;
    } else {  // 若 a 的 exp 部分為0, 則使用非正規數的部分處理
        sig_a = frac_a;
        e_a = -126;

        while (sig_a < 0x80u) {
            sig_a <<= 1;  // sig_a 持續左移，直到 sig_a 至少為 128
            e_a--;        // sig_a 左移, 指數減 1, 剛好抵銷
        }
    }

    // 處理 b
    if (exp_b != 0u) {  // 若 b 的 exp 部分不為 0, 則使用正規數的部分處理
        sig_b = frac_b | 0x80u;
        e_b = (int32_t) exp_b - 127;
    } else {  // 若 b 的 exp 部分為0, 則使用非正規數的部分處理
        sig_b = frac_b;
        e_b = -126;

        while (sig_b < 0x80u) {
            sig_b <<= 1;  // sig_b 持續左移，直到 sig_b 至少為 128
            e_b--;        // sig_b 左移, 指數減 1, 剛好抵銷
        }
    }

    /* 4. 有效數相乘，實際指數相加。 */

    // 相乘後結果 : a * b = (sig_a * sig_b / 16384) * 2^(e_a + e_b)
    // sig_a、sig_b 都介於 128 ~ 255
    // __mulsi3 可支援 RV32I 的 32 位元乘法
    uint32_t product = sig_a * sig_b;
    int32_t result_e = e_a + e_b;

    // 由於 sig_a * sig_b 落於 16384 ~ 65025
    // 除以 16384 後落於 1 ~ 4
    // 若 1 <= product/16384 < 2, 不需調整。
    // 若 2 <= product/16384 < 4, 相乘後 sig 除以 2, 指數加 1。
    if (product >= 0x8000u) {
        product >>= 1;
        result_e++;
    }

    /* 5. 轉回 BF16 表示法 */

    // 加回偏移量
    int32_t result_exp = result_e + 127;     // 加回偏移量的候選指數
    uint32_t result_sig = product >> 7;      // 包含最高位 1 的八位元有效數
    uint32_t sign_bits = result_sign << 15;  // 移到 bit 15 的符號

    // 如果指數超過 254 ，回傳無限大
    if (result_exp >= 255) {
        return (uint16_t) (sign_bits | 0x7F80u);
    }

    /* 如果過小, 轉成非正規化數，或帶符號的零 */
    if (result_exp <= 0) {
        if (result_exp <
            -6) {  // 有效內容只有八位；需要右移至少八位時，截斷結果必定為零。
            return (uint16_t) sign_bits;
        }
        // 將有效數右移 1 - result_exp 位, 改用非正規化數固定的指數 -126,
        // 並截斷移出的低位元。 result_sig >>= (1 - result_exp);

        // 為配合作業測資，先移除隱含位元，再右移小數欄位。
        result_sig = (result_sig & 0x7Fu) >> (1 - result_exp);

        /* 指數欄位為 0, 只需組合符號與小數欄位。 */
        return (uint16_t) (sign_bits | result_sig);
    }

    /* 一般正規化結果。 */
    return (uint16_t) (sign_bits | ((uint32_t) result_exp << 7) |
                       (result_sig & 0x7Fu)  // 移除隱含的最高位 1
    );
}

uint16_t bf16_sqrt(uint16_t a)
{
    /* 1. 取出各資訊 */
    uint16_t sign_a = a >> 15;
    uint32_t exp_a = (a >> 7) & 0xFFu;
    uint32_t frac_a = a & 0x7Fu;


    /* 2. 處理 a 的特殊值 */

    // 若 a 為正零或負零，回傳正零
    if (exp_a == 0x0u && frac_a == 0x0u)
        return 0x0u;

    // 若 a 為 NAN 或無限大
    if (exp_a == 0xFF) {
        // 若 a 是 NAN, 直接回傳 a
        if (frac_a)
            return a;  // 無效，傳回 a

        /* 若 a 為負無限大，回傳 NaN。 */
        if (sign_a != 0u)
            return 0x7FC0u;

        // 已排除 a 是 NAN 以及負無限大，此時 a 為 正無限大，直接回傳 a
        return a;
    }

    // 已排除零、NaN 與無限大；負的非零有限值回傳 NaN。
    if (sign_a == 0x1u)
        return 0x7FC0u;

    // 若 a 為正的非正規化數，回傳正零
    if (exp_a == 0x0u)
        return 0x0u;

    /* 3. 取得正規化數的有效數與實際指數。 */
    //  ((128 + frac_a) / 128) * 2^(exp_a - 127)
    //  = (sig / 128) * 2^(e)
    uint32_t sig = frac_a | 0x80u;
    int32_t e = (int32_t) exp_a - 127;

    /* 4. 進行開根號 */

    // 先將奇數次方項化為偶數
    if ((e & 0x1u)) {
        sig <<= 1;
        e--;
    }

    /* 平方根後指數項除以 2 */
    int32_t result_e = e / 2;

    /* sig 介於 0+128 ~ (127+128) * 2 = 510 */
    /* 1 ≤ sig / 128 < 4 ，不會等於 4 */

    /* 透過以下方法尋找 sig 的平方根 */
    // root / 128 ≈ √(sig / 128)
    // 因此 (root * root) / 128 ≈ sig
    // 透過「將候選值平方」來判斷它是否合適，不需要直接呼叫平方根函式
    // 即尋找 mid, 使的(mid * mid) / 128 <= sig
    // 使用二分搜尋法搜尋 mid

    uint32_t low = 90u;
    uint32_t high = 256u;
    uint32_t root = 0u;

    while (low <= high) {
        uint32_t mid = low + ((high - low) >> 1);
        uint32_t square = (mid * mid) >> 7;

        if (square <= sig) {
            // mid 符合條件，記錄後繼續尋找更大的答案
            root = mid;  // 取最大符合值
            low = mid + 1u;
        } else {
            // mid 太大，讓 mid - 1 成為新的搜尋上界，然後繼續搜尋
            high = mid - 1u;
        }
    }

    /* 5. 返還成 BF16 */
    // 先將指數位從實際值轉回 BF16 表示法
    int32_t result_exp = result_e + 127;

    // 確認root範圍
    // 已知 (root * root) / 128 <= sig
    // 而 sig 介於 128 ~ 510
    // 因此 128 <= root <= 255
    // 因此 root 為 8 bit,  包含隱含的最高位 1
    // 需要去除隱含的最高位 1

    return (uint16_t) ((uint32_t) result_exp << 7 | (root & 0x7Fu));
}

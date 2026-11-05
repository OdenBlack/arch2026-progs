#include <stdint.h>
#define Q 20
typedef int32_t qfixed_t;

uint32_t op1(uint32_t a, uint32_t b, int *n)  // 位元加法 (a+b)
{
    *n = 0;  // 初始化進行次數計數器為 0

    while (b) {
        uint32_t carry = (a & b) << 1;  // 事先計算每一位的 carrier
        a = a ^ b;  // 算沒有進位的位元加法, 進位的問題已交由變數 carry 計算
        b = carry;  // 用 carrier 代替掉 b,做為下一論的 b

        ++(*n);  // 計數器 + 1
    }

    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{  // 位元減法 (a-b), 使用二補數 a - b = a + (~b + 1)，結果取低 32 位元
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{  // a 和 b 相加後除以 2, 再取 floor 函數，注意如果 a b 皆為奇數，各自捨去的
   // 0.5 合計為 1,因此補回 1
    return (a >> 1) + (b >> 1) + (a & b & 1);  // 先右移再加  可避免 overflow
}

qfixed_t q_mul(qfixed_t a, qfixed_t b)
{
    /* */
    /* 1. 記錄乘積的正負號，取得輸入的絕對值 */
    int negative = (a < 0) != (b < 0);

    uint32_t ua = (uint32_t) a;
    uint32_t ub = (uint32_t) b;

    if (a < 0)
        ua = 0u - ua;

    if (b < 0)
        ub = 0u - ub;


    /* 2. 以高、低兩個 32 位元進行位移加法乘法 */
    uint32_t mul_lo = ua;
    uint32_t mul_hi = 0;

    uint32_t prod_lo = 0;
    uint32_t prod_hi = 0;

    /*
    每次迴圈都做三件事：
    - 檢查乘數 ub 的最低位，若為 1, 就累加目前的被乘數。
    - 被乘數左移一位，代表乘以 2。
    - 乘數右移一位，準備檢查下一個位元。
    */

    while (ub != 0) {
        if (ub & 1u) {
            uint32_t old_lo = prod_lo;

            prod_lo += mul_lo;
            prod_hi +=
                mul_hi +
                (prod_lo <
                 old_lo);  // 加法進位: prod_lo < old_lo 判斷低 32
                           // 位元相加後是否回繞；如果有，就向高 32 位元加上 1
        }

        mul_hi =
            (mul_hi << 1) |
            (mul_lo >>
             31);  // `mul_lo >> 31`
                   // 取出低半部原本的最高位，補進高半部左移後的最低位。因此必須先更新
                   // mul_hi，再更新 mul_lo。
        mul_lo <<= 1;

        ub >>= 1;
    }

    /* 合併高、低兩半，交給後面的符號與捨入處理 */
    uint64_t product = ((uint64_t) prod_hi << 32) | prod_lo;

    /* 3. 還原乘積的正負號 */
    int64_t signed_product = (int64_t) product;

    if (negative)
        signed_product = -signed_product;

    /* 4. 捨入並轉回 Q11.20 */
    return (qfixed_t) ((signed_product + (INT64_C(1) << (Q - 1))) >> Q);
}
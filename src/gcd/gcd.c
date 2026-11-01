#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    /* 如果其中一個數字為 0, 直接回傳另一個數字*/
    if (a == 0)
        return b;

    if (b == 0)
        return a;

    /* 紀錄兩個數字有多少的因數 2 */
    unsigned common_twos = 0;

    while (((a | b) & 1u) == 0) {
        a >>= 1;
        b >>= 1;
        common_twos++;
    }

    while (a != 0 && b != 0) {
        if ((a & 1u) == 0u) {  // 看是不是偶數
            a >>= 1;           // 除以 2
            continue;
        }
        if ((b & 1u) == 0u) {  // 看是不是偶數
            b >>= 1;           // 除以 2
            continue;
        }
        if (a < b) {
            b = b - a;
            continue;
        }
        a = a - b;
    }

    // 判斷經過上述迴圈後，剩下的值要乘上 2 的 common_two 冪次
    uint32_t gcd = a;
    if (a == 0)
        gcd = b;
    return gcd << common_twos;
}
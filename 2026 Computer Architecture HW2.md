---
title: 2026 Computer Architecture HW2

---

---
title: 2026 Computer Architecture HW2

---

# 2026 Computer Architecture HW2

[toc]

## 1. Introduction

### 1-1. Requirement 
本測作業的目標為 : 在 rv32emu 的裸機環境中，完成 minirubik、 binary GCD 、 BFloat 16、邏輯運算的 C 語言與 RV32I 組合語言版本，並建立測試，以比較正確性、執行成本與程式大小。下表為本次作業的內容描述

|程式|來源|主要工作|
|:--:|:--:|:--:|
|minirubik|HW 1|將既有程式與測試移植到 rv32emu 裸機環境
|BFloat16|Quiz 1，Problem B|使用整數與位元操作處理數值表示及相關運算
|Binary GCD|Quiz 2，Problem A|使用位移與減法計算最大公因數|
|邏輯運算與 Q11.20|Quiz 3，Problem C |實作相關邏輯運算與定點數計算|

每個子部份的內容皆包含
* C 語言版本。
* RV32I 版本。
* 使用 micro-test 的測試。
* 獨立參考答案。
* 效能與程式大小比較。
* 演算法、驗證方法與最佳化原因的說明。

其中 RV32I 需要運行在 rv32_emu 之上，並且不能使用包括 RV32M 的硬體乘法/除法指令、RV32F 的浮點指令。

在裸機環境中，主要的編譯旗標需要包含如下。而由於裸機環境沒有一般作業系統提供的完整 C 執行環境，也不連結 libc 或 libgcc。程式需要的記憶體、字串、輸出及算術輔助函式，將需要自行建置，並通過提供的測試系統進行驗證
```
-march=rv32i_zicsr
-mabi=ilp32
-ffreestanding
```

### 1-2. Enviorement
* 作業系統 (使用 Ubuntu 進行程式建置，並透過 rv32emu 執行 RISC-V 程式) :
    * host 作業系統 : Windows 11 25H2
    * Linux 執行環境：WSL 2
    * Linux 發行版：Ubuntu 24.04.5 LTS
* 開發工具
    * RISC-V 交叉編譯器：GCC 15.2.0
    * 建置工具：GNU Make
    * 模擬器：rv32emu
    * 測試與分析工具：Python 3、sanitizer、cppcheck
    * 程式碼排版工具：clang-format 20.1.8
* 專案版本
    * 正式框架：sysprog21/arch2026-progs
    * github fork 連結：https://github.com/OdenBlack/arch2026-progs
    * rv32emu 使用版本：158b57e9eab99d59e01141cd0e477b06b44b8fe3

### 1-3. Performance Requirement
效能的測量要求須包含 :
* 使用相同輸入與計時區間。
* 排除初始化與輸出。
* 讓計算結果可被觀察，避免被編譯器刪除。
* 使用 64 位元計數器差值。
* 說明讀取計數器的額外成本。
* 以 -O2 為基準，實驗其他最佳化選項。
* 分別比較執行成本與程式大小。
* 程式大小比較排除共用測試框架。

## 2. Binary GCD
本文將 Binary GCD 設為第一個建置目標，首先講述其原理，然後針對 C 語言以及 RV32I 語言的關鍵程式片段進行講解，最後對 RV32I 語言版本進行優化，以求其相關效能 (如 cycles per call 等)優於 C 語言版本

### 2-1. Principle of Binary GCD
二進位最大公因數演算法(GCD)的核心建立於輾轉相除法，並配合位元運算來達成最大公因數的運算。尋找兩數 a、b 的最大公因數流程大致如下
1. 先判斷 a 與 b 分別是否為 0，若其中一個為 0，則立即回傳另一個數
2. a 與 b 皆為偶數時，同時除以 2，並記錄共同因數 2 的數量
3. 進行主迴圈，若為一奇一偶時，可將偶數除以 2 並重新進入主迴圈，此舉不改變最大公因數。兩數皆為奇數時，以較大的數減去較小的數。
4. 當其中一數為 0，跳出主迴圈，將另一數乘回先前取出的2的共同因數次方，所得即為最大公因數

核心的 C 程式碼可以參考如下，其中除以 2 的部分皆可以透過右移 1 bit 來達成，判斷奇偶的部分則是與 1 做 LSB 的 and 運算來判斷，
```C=
uint32_t binary_gcd_c(uint32_t a, uint32_t b)
{
    /* 如果其中一個數字為 0, 直接回傳另一個數字*/
    if (a == 0)
        return b;

    if (b == 0)
        return a;

    /* 紀錄兩個數字有多少的因數 2 */
    unsigned common_twos = 0;

    while(((a|b) & 1u) == 0){
        a >>= 1;
        b >>= 1;
        common_twos++;
    }
    
    while (a != 0 && b != 0){
        if ((a & 1u) == 0u){    // 看是不是偶數
            a >>= 1;            // 除以 2
            continue;
        }
        if ((b & 1u) == 0u){    // 看是不是偶數
            b >>= 1;            // 除以 2
            continue;
        }
        if (a < b){
            b = b - a;
            continue;
        }
        a = a - b;
        
    }

    // 判斷經過上述迴圈後，剩下的值要乘上 2 的 common_two 冪次 
    uint32_t gcd = a;
    if(a == 0) gcd = b;
    return gcd << common_twos;

}
```


RV32I 的部分，分為幾個主要的 function 與 helper，其中 a 的值存放於 a0，b 的值存放於 a1，輸出結果存放於 a1，並使用無號比較指令處理 uint32_t 的大小關係
* ```.Lreturn_b``` : 若 a 為 0，則將 a0 的值替換為 b 以便輸出
```assembly=
.Lreturn_b:
    # 回傳值必須放在 a0
    addi a0, a1, 0
```
* ```.Lreturn_a``` : 若 b 為 0，因 a0 原本已經存放 a 的值，直接跳轉回 caller 即可
```assembly=
.Lreturn_a:
    # 返回呼叫者
    jalr zero, 0(ra)
```
* ```.Lcommon_loop``` : 計算共同因數 2 的數量，其中 t0 記錄共同因數 2 的數量
```assembly=
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

```
* ```.Lmain_loop``` : 輾轉相除法的核心，helper 有 ```a_even```、```b_even```、```b_larger```，負責處理 a 或 b 為偶數時需除以 2 的動作，以及計算 b = b - a 的情況
```assembly=
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

```
*  ```Times_two_power``` : 將另一數乘回先前取出的2的共同因數次方，helper 為 ```.Lrestore```
```assembly=
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

```


### 2-2. Performance of Binary GCD algorithm before optimization

優化前的 RV32I 實作所在的 commit 為 723b448，存放於 `arch2026-progs/src/gcd/gcd.S` 中。我們首先針對這版本的 RV32I 實作進行四種編譯方式( O1、O2、O3、Os ) 進行效能測試，測試結果存放於 `arch2026-progs/mylogs/gcd-baseline`。四種編譯方式的意義如下

| 設定 | 編譯器最佳化方向 | 觀察目標 |
|:---:|:---:|:---:|
|`O1`| 啟用基本最佳化，兼顧編譯時間與執行效率 | 基本最佳化後，程式是否正確、執行成本多少 |
| `O2` | 啟用更全面的最佳化 | 是否能進一步降低執行成本 |
| `O3` | 在 O2 之上採用更多最佳化，可能增加程式大小 | 更積極的最佳化對這個演算法是否真的有效 |
| `Os` | 以縮小程式碼為主要方向 | 程式是否較小，以及執行成本如何變化 |

測試的目標有三個
1. 每個編譯版本都能正確計算
2. 每個版本都符合 C 與組語各自的單次指令預算
3. 量出四個 C 版本的成本，找出組語需要比較的最佳基準

---

__O1 編譯__ : 透過 O1 編譯設定所產生的結果進行測試，該測試包含了以下34種已註冊的測試函式，大致可以分為四大部分
| 類別 | 數量 | 測試對象 |
|---|---:|---|
| `rt_` | 11 | 共用執行功能，例如乘法、記憶體操作、輸出 |
| `utest_` | 6 | 測試框架本身 |
| `gcd_` | 17 | 我們寫的 C 與 RV32I GCD |
| 合計 | 34 | |

34 種具體的測試函式測試內容如下

| 編號 | 測試名稱 | 具體檢查內容 |
|:---:|:---:|:---:|
| 1 | `rt_mulsi3_small` | 測試軟體乘法函式 `__mulsi3`。窮舉兩個輸入皆為 0～127 的 **16,384 組配對**，與參考計算結果比較。 |
| 2 | `rt_mulsi3_edges` | 檢查乘法邊界，例如乘以 0、乘以 1、最大無號整數、最高位元，以及乘積超過 32 位元時保留低 32 位元的結果。 |
| 3 | `rt_mulsi3_random` | 使用固定種子產生 **1,024 組偽隨機輸入**，比較參考答案，並檢查 `a × b = b × a`。 |
| 4 | `rt_memcpy_memset` | 測試複製與填入 0～40 個位元組。檢查內容、回傳的目的指標，以及目標區域前後的保護值是否保持不變；另檢查 `memset` 只取填入值的低 8 位元。 |
| 5 | `rt_memmove` | 測試來源與目的範圍重疊時的搬移。以 −8～8 的位移測試兩個方向，也涵蓋同位置及長度為 0 的情況。 |
| 6 | `rt_memcmp_strlen` | 檢查記憶體比較的相等、大小關係、部分比較與零長度比較；確認位元組以無號值比較。另測試字串長度，包括遇到 `'\0'` 就停止。 |
| 7 | `rt_printf_integers` | 檢查整數格式化輸出，包括 32／64 位元、有號／無號、零、負數、極值，以及 \(10^0\)～\(10^{19}\) 的十進位表示。 |
| 8 | `rt_printf_other` | 檢查十六進位、字串、字元、百分比符號、指標，以及不含格式符號的一般文字。 |
| 9 | `rt_printf_truncation` | 檢查輸出緩衝區不足時是否正確截斷、保留結尾 `'\0'`、回傳完整預期長度，且不寫出指定範圍。也測試容量為 0 或 1。 |
| 10 | `rt_startup` | 確認未初始化的靜態資料已清零、有初值的資料正確載入，以及堆疊指標符合 **16 位元組對齊**。 |
| 11 | `rt_counters` | 執行一段迴圈，確認 `cycle` 和 `instret` 計數器會增加，並檢查增加量與單調性。 |

| 編號 | 測試名稱 | 具體檢查內容 |
|:---:|:---:|:---:|
| 12 | `utest_boolean` | 驗證 `ASSERT_TRUE`、`ASSERT_FALSE` 和 `FAIL()`。例如真值檢查接受 1 和 −5，但應拒絕 0。 |
| 13 | `utest_equality` | 驗證有號與無號整數的相等、不相等斷言，包含負值與 64 位元高位元設為 1 的數值。 |
| 14 | `utest_almost_equal` | 驗證整數差距是否在容許範圍內。例如 10 與 12 的容許差距為 2 時通過，10 與 13 則失敗；也測試交換順序與極值，避免差距計算溢位。 |
| 15 | `utest_pointers_memory` | 驗證指標相等／不相等、NULL／非 NULL，以及記憶體內容比較。包含只比較前幾個位元組和比較長度為 0。 |
| 16 | `utest_setup` | 確認測試開始前，框架確實執行註冊的 setup 函式。 |
| 17 | `utest_teardown` | 確認前一個測試結束後，框架確實執行註冊的 teardown 函式。 |

| 編號 | 測試名稱 | 具體檢查內容 |
|:---:|:---:|:---:|
| 18 | `gcd_c_cases` | 對 C 版執行 **45 組固定案例**，涵蓋零值、相等、互質、共同因數、32 位元邊界及 Fibonacci 等，與預先提供的答案比較。 |
| 19 | `gcd_asm_cases` | 對組語版執行相同的 45 組案例。 |
| 20 | `gcd_c_identities` | 對 C 版檢查 GCD 的基本性質，例如 `gcd(x, 0) = x`、`gcd(x, x) = x`、`gcd(x, 1) = 1`，使用多種位元模式。 |
| 21 | `gcd_asm_identities` | 對組語版檢查相同性質。 |
| 22 | `gcd_c_small_exhaustive` | 對 C 版窮舉兩個輸入皆為 0～255 的 **65,536 組配對**，逐一比對參考演算法。 |
| 23 | `gcd_asm_small_exhaustive` | 對組語版執行相同的 65,536 組配對。 |
| 24 | `gcd_c_powers_of_two` | 對 C 版測試所有 `gcd(2^i, 2^j)`，其中 `i, j` 為 0～31，共 **1,024 組**。 |
| 25 | `gcd_asm_powers_of_two` | 對組語版執行相同的 1,024 組測試。 |
| 26 | `gcd_c_shared_twos` | 對 C 版執行 **512 組**奇數再左移的輸入，檢查共同因數 2 是否正確移除與還原。 |
| 27 | `gcd_asm_shared_twos` | 對組語版執行相同的 512 組測試。 |
| 28 | `gcd_c_random` | 對 C 版執行 **2,048 組**不同位元長度的偽隨機輸入，檢查參考答案、交換性、整除性及除去 GCD 後是否互質。 |
| 29 | `gcd_asm_random` | 對組語版執行相同的隨機測試與性質檢查。 |
| 30 | `gcd_c_fibonacci` | 對 C 版測試 `F(0)`～`F(47)` 的所有配對，共 **2,304 組**，驗證 Fibonacci 的 GCD 性質。 |
| 31 | `gcd_asm_fibonacci` | 對組語版執行相同的 2,304 組測試。 |
| 32 | `gcd_c_perf` | 對 C 版量測 **12 組特別挑選的輸入＋256 組偽隨機輸入**，檢查答案，並確認最高量測成本不超過 **4,000**。 |
| 33 | `gcd_asm_perf` | 對組語版執行相同效能測試，但預算更嚴格，上限為 **1,500**。 |
| 34 | `gcd_asm_matches_c` | 使用另一組固定種子產生 **4,096 組輸入**，直接確認 C 與組語的回傳值一致。 |


接下來透過以下指令建置測試所需的 elf 檔並執行
```bash=
make build/gcd/O1/gcd.elf &&
third_party/rv32emu/build/rv32emu build/gcd/O1/gcd.elf 2>&1 | tee mylogs/gcd-baseline/O1.log
echo "Exit status: $?"
```
執行結果如下
![image](https://hackmd.io/_uploads/rkxeghS6Gg.png)

結果為 34 passed、0 failed，tests_rc 與程式退出狀態皆為 0。在底下的 `gcd_c_pref`、`gcd_asm_pref` 中的 `@@gcd worst` 代表本次選定測資中呼叫 cost 的最高值，分別為 594、739，各自的 budget 分別為 4000、1500。基於上述的結果，我們可以得知正確性與指令預算通過。而雖然 RV32I 實作的最高 cost 高於 C 實作的 cost，但在這一步不用要求 RV32I 比 C 快。最後，平均呼叫成本計算方式如下：

$$ \text{averge cost} = (\text{cycles} - \text{overhead}) \div n $$

|實作|cycles|overhead|n|平均成本／次|
|:---:|:---:|:---:|:---:|:---:|
|C（O1）|2446|102|16|146.5|
|RV32I（O1）|3091|99|16|187|

目前的通過結果表示 O1 版本通過 ELF 內的測試與指令預算檢查。是否符合組合語言與最佳 C 版本的效能比較條件，仍需完成 O2、O3、Os 測試，並由 driver 檢查。

---

__O2 編譯__ :  透過以下指令建置測試所需的 elf 檔並執行
```bash=
make build/gcd/O3/gcd.elf &&
third_party/rv32emu/build/rv32emu build/gcd/O3/gcd.elf 2>&1 | tee mylogs/gcd-baseline/O3.log
echo "Exit status: $?"
```

執行結果如下
![image](https://hackmd.io/_uploads/B1Nfa6rpzg.png)

平均呼叫成本如下
|實作|cycles|overhead|n|平均成本／次|
|:---:|:---:|:---:|:---:|:---:|
|C（O2）|1998|100|16|118.7|
|RV32I（O2）|3091|99|16|187.0|

結果為 34 passed、0 failed，tests_rc 與程式退出狀態皆為 0。正確性與指令預算通過，但 RV32I 實作的最高 cost 仍然高於 C 實作的 cost

---

__O3 編譯__ :  透過以下指令建置測試所需的 elf 檔並執行
```bash=
make build/gcd/O3/gcd.elf &&
third_party/rv32emu/build/rv32emu build/gcd/O3/gcd.elf 2>&1 | tee mylogs/gcd-baseline/O3.log
echo "Exit status: $?"
```

執行結果如下
![image](https://hackmd.io/_uploads/ByTS6praGe.png)

平均呼叫成本如下
|實作|cycles|overhead|n|平均成本／次|
|:---:|:---:|:---:|:---:|:---:|
|C（O3）|1983|50|16|120.8|
|RV32I（O3）|3074|50|16|189.0|

結果為 34 passed、0 failed，tests_rc 與程式退出狀態皆為 0。O3 的 C 平均成本略高於 O2 的 118.625，顯示更積極的最佳化設定不一定能改善此程式在目前量測方式下的表現。

---

__Os 編譯__ :  透過以下指令建置測試所需的 elf 檔並執行
```bash=
make build/gcd/O3/gcd.elf &&
third_party/rv32emu/build/rv32emu build/gcd/O3/gcd.elf 2>&1 | tee mylogs/gcd-baseline/O3.log
echo "Exit status: $?"
```

執行結果如下
![image](https://hackmd.io/_uploads/S15AkCrpzl.png)

平均呼叫成本如下
|實作|cycles|overhead|n|平均成本／次|
|:---:|:---:|:---:|:---:|:---:|
|C（O3）|2942|100|16|177.625|
|RV32I（O3）|3091|99|16|187.0|

結果為 34 passed、0 failed，tests_rc 與程式退出狀態皆為 0。Os 的 C 執行成本比 O2 高出許多，但現在還不能判斷它是否產生較小的程式。Os 以縮小程式碼為方向，實際大小仍需要另外量測

---

綜合上述四種編譯方式的效能結果如下

| 設定 | C cycles | C overhead | C 平均成本／次 | 組語 cycles | 組語 overhead | 組語平均成本／次 |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| O1 | 2446 | 102 | 146.5000 | 3091 | 99 | 187.0000 |
| O2 | 1998 | 100 | 118.6250 | 3091 | 99 | 187.0000 |
| O3 | 1983 | 50 | 120.8125 | 3074 | 50 | 189.0000 |
| Os | 2942 | 100 | 177.6250 | 3091 | 99 | 187.0000 |

在本次量測中，C 版本以 O2 的平均成本最低，O3 並未進一步改善；Os 的執行成本最高。程式大小尚需另外量測，不能只從執行成本判斷最佳化設定的整體效果。

手寫組語共用同一份實作，其量測成本可能因呼叫端等因素略有差異，不代表 GCC 對組語進行了不同等級的最佳化。

依目前框架的比較規則，組語平均成本不得超過最佳 C 平均成本加 2。本次對應門檻為：

$$118.625 + 2 = 120.625$$

組語目前仍超過此門檻。因此，雖然各設定的正確性與指令預算測試通過，組語效能仍需優化。上述成本反映目前 rv32emu 的客體指令計數，不直接代表真實硬體的執行時間。

---

__優化前的正式評分檢查__ : 透過以下指令進行 driver 的正式檢查，由於其於三個部分尚未完成，因此目前僅使用 ```DRIVER_ARGS="--prog gcd"``` 檢查 gcd 實作的部分

```bash=
set -o pipefail
make grade DRIVER_ARGS="--prog gcd" 2>&1 | tee mylogs/gcd-baseline/grade.log
echo "Exit status: $?"
```

執行結果如下
![image](https://hackmd.io/_uploads/B1OrM0raGg.png)

從上述結果可知，必要的共用檢查都通過，唯一失敗原因是 RV32I 效能不足 ( 最佳 C：118.625 cycles／call（O2）、允許上限：118.625 + 2 = 120.625、目前組語：187 cycles／call、加速比 : 0.63x )，其分數依框架規則計為 0。接下來會以 120.625 作為優化目標的最低基準

### 2-3 Optimize Binary GCD

優化將會分成幾個部分進行以下幾個部分進行 :

1. __主迴圈中的偶數處理__ : `.Lmain_loop` 中原本會先判斷 a 和 b 是否為 0，然後再判斷 a 和 b 是否為偶數，然後跳轉至對應的 helper `a_even` 與```b_even``` 執行除以 2 的動作。然而 helper 執行完後會直接執行 `j     .Lmain_loop` ，導致`.Lmain_loop` 中最初判斷 a 和 b 是否為 0 的指令被重複執行。

我們首先將對這個部分進行優化，優化實作與 O2 編譯效能如下。其中 O2 編譯效能中，相對原版，平均成本累計降低約 21.86%。
    
```assembly=
a_even:
    # 處理到變成奇數為止
    srli a0, a0, 1
    andi t1, a0, 1
    beq  t1, zero, a_even
    j     .Lmain_loop

b_even:
    # 處理到變成奇數為止
    srli a1, a1, 1
    andi t1, a1, 1
    beq  t1, zero, b_even
    j     .Lmain_loop
```

|版本|cycles|overhead|n|平均成本／次|
|:---:|:---:|:---:|:---:|:---:|
|原版|3091|99|16|187.0|
|改動 `a_even` 與 `b_even` 後|2437|99|16|146.1|

---
    
2. __利用相減結果的性質__ : 觀察原本的主迴圈實作如下，每次進行 a 與 b 的相減動作
後，迴圈每次都要重複執行判斷 a 與 b 是否為 0，以及 a 與 b 是否為偶數。然而，較大者減去較小者的結果必定是偶數。

```assembly=
.Lmain_loop:
    # 實作 C 版本的主迴圈
    # t0 = common_twos，t1 用於奇偶1
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
```

我們可以在相減的過程中，就直接跳轉到除以 2 的 helper，以減少重複判斷偶數的動作。為此，我們將 `.Lmain_loop` 額外切出 `.Lmain_loop_2`，讓迴圈實際跑在 `.Lmain_loop_2` 上，而 `.Lmain_loop` 僅作為一個迴圈入口。

此外，若兩數相等，相減結果為 0。若將 0 送進「右移直到成為奇數」的迴圈，便會形成無限迴圈，因為 0 右移後仍是 0。因此我們在 `.Lmain_loop_2` 第一行加入了 `beq   a0, a1, .Lrestore` 避免進入無限迴圈

詳細實作片段如下，其中我們改善了一些不必要的跳轉以及判斷奇偶性質的動作，以進一步減少 costs。

```assembly=
.Lmain_loop:
    # 實作 C 版本的主迴圈
    # t0 = common_twos，t1 用於奇偶1
    beq  a0, zero, .Times_two_power
    beq  a1, zero, .Times_two_power

    # 三個if用3個helper
    andi  t1, a0, 1
    beq   t1, zero, a_even
    andi  t1, a1, 1
    beq   t1, zero, b_even

.Lmain_loop_2:
    beq   a0, a1, .Lrestore     # 如果此時 a b 相同，一定要直接跳轉結果輸出，否則會無限迴圈
    bltu  a0, a1,   b_larger
    sub   a0, a0, a1            # 相減後的 a 一定為偶數，可以進到除以 2 的 helper

a_even:
    # 處理到變成奇數為止
    srli a0, a0, 1
    andi t1, a0, 1
    beq  t1, zero, a_even
    j     .Lmain_loop_2

b_even:
    # 處理到變成奇數為止
    srli a1, a1, 1
    andi t1, a1, 1
    beq  t1, zero, b_even
    j     .Lmain_loop_2

b_larger:
    sub  a1, a1, a0
    j    b_even     # 相減後一定為偶數，可以直接跳轉除以 2 的 helper
```

O2 編譯效能如下，可以看到在利用相減性質之後，平均 costs 顯著降低到了 92.4 平均成本／次，相較原版減少了約 50.60%

|版本|cycles|overhead|n|平均成本／次|指定效能測資中最高 costs|
|:---:|:---:|:---:|:---:|:---:|:---:|
|原版|3091|99|16|187.0|739|
|改動 `a_even` 與 `b_even` 後|2437|99|16|146.1|713|
|利用相減性質並簡化控制流程|1577|99|16|92.4|362|

使用 driver 進行測試後結果如下，加速比約為 1.28x，已達指定測試之通過門檻。
![image](https://hackmd.io/_uploads/Bkgd2l8pMe.png)

## 3. Logic Caculation and Q11.20 reprensation
第二部分建置的目標為 Logic Caculation and Q11.20，與 Binary gcd 相同，首先講述其原理，然後針對 C 語言以及 RV32I 語言的關鍵程式片段進行講解，最後對 RV32I 語言版本進行優化，以求其相關效能 (如 cycles per call 等)優於 C 語言版本

### 3-1. Logical Caculation

邏輯運算中共有三種動作
1. op1: 位元加法
2. op2: 位元減法
3. op3: 兩數相加除以2

__op1__: 計算 a + b，結果保留低 32 位元，並透過指標 n 回傳迴圈執行次數。加法可以拆成兩部分：
```
uint32_t carry = (a & b) << 1;
a = a ^ b;
b = carry;
```

* `a ^ b`：計算不含進位的加法結果。
* `a & b`：找出兩個輸入同時為 1、需要產生進位的位置。
* 左移一位：將進位送到下一個位元。重複處理直到進位 b 變成 0。

__op2__: op2 計算 a - b，並保留低 32 位元。由於運算元都是 uint32_t，當結果小於零時，會依無號整數規則回繞，如下。因此這邊可以使用 a - b 的方式計算。
```
0 - 1 → 0xFFFFFFFF
3 - 8 → 0xFFFFFFFB
```

__op3__: op3 計算兩個輸入完整數學和的平均值，再向下取整。因為 a + b 可能先發生 32 位元回繞，丟失最高位後再右移，就無法得到正確平均值。因此先各自除以 2，避免相加溢位；最後補回兩個奇數各自右移時，合計丟掉的那個 1。

---

### 3-2. Q11.20 reprensation and q_mul calculation (C Implementation)
__Q11.20__ : Q11.20 fixed-point 為沒有浮點數運算硬體的環境提供能用整數運算處理浮點數的能力。該算法將浮點數放大 $2^{20}$ 倍，因此程式可以用整數儲存浮點數。以 0.75 為例，$0.75 × 2^{20} = 786432$，因此 0.75 會以 786432 被表示。在 Q11.20 中，相鄰兩個可表示數值的距離固定為 $1 / 2^{20} ≈ 0.000000953674$。該表示法中的最小值、最大值、相鄰數值的間距可以被表示成如下

$$
\begin{gather*}
\text{Manimum} = -2^{31} \div 2^{20} = -2048 \\
\text{Manimum} = (2^{31} - 1) \div 2^{20}  ≈ 2047.999999046326 \\
\text{Interval} = 2^{-20} ≈ 0.00000095367431640625
\end{gather*}
$$

---

`q_mul` 則為透過 Q11.20 方法儲存的浮點數提供乘法，假設儲存整數為 A、B，實際數值為 x、y，則乘法如下進行：
$$
\begin{gather*}
x = A \div 2^{20} \\
y = B \div 2^{20} \\
x × y = (A × B) \div 2^{40} \\
R ≈ (x × y) × 2^{20}
  = (A × B) / 2^{20}
\end{gather*}
$$
其中 R 可視為 x * y 的相乘結果再提升 20 位元，若是以 A × B 計算，需要捨去低 20 位，才能回到 20 個小數位表示法。另外需注意，在 C 實作中，兩個 32 位元有號整數相乘，結果可能超出 32 位元，但可以放入 64 位元有號整數。必須在進行乘法前擴大運算元。概念上應是：

```c
int64_t product = (int64_t)a * b;
```

下面這種寫法不等價，因為運算過程為先算 a * b，再將 a * b 轉為 int64_t 的型態型態，溢位可能已經發生：

```c
int64_t product = (int64_t)(a * b);
```

若只將乘積右移 20 位，就會直接向下取整。因此在右移前，需要加上半個右移單位作為補償。一個結果儲存單位對應 $2^{20}$，所以半個單位是 $2^{19}$。而在捨入的問題中，捨入方向在一半以內恰好一半時朝向正無限大，小於一半則朝向負無限大。

---

### 3-3. Logical Caculation and q_mul calculation (C Implementation)

以下為 Logical Caculation 以及 q_mul 的實作片段

op1:

```C=
uint32_t op1(uint32_t a, uint32_t b, int *n)    // 位元加法 (a+b)
{
    *n  = 0;                            // 初始化進行次數計數器為 0
    
    while(b){
        uint32_t  carry = (a & b) << 1; // 事先計算每一位的 carrier
        a = a ^ b;                      // 算沒有進位的位元加法, 進位的問題已交由變數 carry 計算
        b = carry;                      // 用 carrier 代替掉 b,做為下一論的 b 

        ++(*n);                         // 計數器 + 1
    }
    
    return a;
}
```

op2:

```C=
uint32_t op2(uint32_t a, uint32_t b)    //位元減法 (a-b), 使用二補數 a - b = a + (~b + 1)，結果取低 32 位元
{           
    int n;
    return op1(a, op1((~b), 1, &n), &n);
}
```

op3:

```C=
uint32_t op3(uint32_t a, uint32_t b)    // a 和 b 相加後除以 2, 再取 floor 函數，注意如果 a b 皆為奇數，各自捨去的 0.5 合計為 1,因此補回 1
{           
    return (a >> 1) + (b >> 1) + (a & b & 1);   // 先右移再加  可避免 overflow
}
```

q_mul:
```C=
qfixed_t q_mul(qfixed_t a , qfixed_t b)
{
    return (qfixed_t) (((qbuf_t) a * b + (1 <<(Q-1))) >> Q );
}
```

但在上述 `q_mul` 的實作中，我們在編譯時將會面臨到以下錯誤訊息:

```bash=
  CC    build/fixed/O2/c-fixed.o
  LD    build/fixed/O2/impl.o
  LD    build/fixed/O2/fixed.elf
riscv-none-elf-ld: build/fixed/O2/impl.o: in function `q_mul':
/home/odenblack/computer-architecture/arch2026-progs/src/fixed/fixed.c:35:(.text+0x98): undefined reference to `__muldi3'
make: *** [Makefile:147: build/fixed/O2/fixed.elf] Error 1
```


可以看到錯誤訊息顯示 " undefined reference to \`__muldi3\`"。由於 Makefile 直接使用 riscv-none-elf-ld，將指定的物件檔連結起來，其中沒有把 libgcc 加入其中，因此在連結時無法找到 `__muldi3`，`__muldi3` 與 `__mulsi3` 的差別如下

| 函式 | 目前用途 | 共用執行期 |
|:---:|:---:|:---:|
| `__mulsi3` | 32 位元整數乘法，保留 32 位元結果 | 有提供 |
| `__muldi3` | 64 位元整數乘法，保留 64 位元結果 | 沒有提供 |

因此後續我們需要針對此部分進行改寫。

---

`q_mul` 可以大致分為四個步驟
1. 先記錄兩個乘數 a, b 的正負號
2. 將被乘數與乘數分成高32位元與低32位元，並使用位移與加法計算乘積，
    - 檢查乘數 ub 的最低位，若為 1, 就累加目前的被乘數
    - 被乘數左移一位，代表乘以 2
    - 乘數右移一位，準備檢查下一個位元
3. 還原乘積的正負號 
4. 捨入並轉回 Q11.20

實作片段如下

```C=
qfixed_t q_mul(qfixed_t a , qfixed_t b)
{
    /* 1. 記錄乘積的正負號，取得輸入的絕對值 */
    int negative = (a < 0) != (b < 0);

    uint32_t ua = (uint32_t)a;
    uint32_t ub = (uint32_t)b;

    if (a < 0)
        ua = 0u - ua;

    if (b < 0)
        ub = 0u - ub;
    
    
    /* 2. 以高、低兩個 32 位元進行位移加法乘法 */
    uint32_t mul_lo = ua;   // 目前被乘數的低 32 位元
    uint32_t mul_hi = 0;    // 目前被乘數的高 32 位元

    uint32_t prod_lo = 0;   // 累積乘積的低 32 位元
    uint32_t prod_hi = 0;   // 累積乘積的高 32 位元


    while (ub != 0) {
        if (ub & 1u) {
            uint32_t old_lo = prod_lo;

            prod_lo += mul_lo;
            prod_hi += mul_hi + (prod_lo < old_lo); //加法進位: prod_lo < old_lo 判斷低 32 位元相加後是否回繞；如果有，就向高 32 位元加上 1
        }

        mul_hi = (mul_hi << 1) | (mul_lo >> 31); // `mul_lo >> 31` 取出低半部原本的最高位，補進高半部左移後的最低位。因此必須先更新 mul_hi, 再更新 mul_lo。
        mul_lo <<= 1;

        ub >>= 1; // 將乘數右移，準備檢查下一位
    }

    /* 合併高、低兩半，交給後面的符號與捨入處理 */
    uint64_t product = ((uint64_t)prod_hi << 32) | prod_lo;

    /* 3. 還原乘積的正負號 */
    int64_t signed_product = (int64_t)product;

    if (negative)
        signed_product = -signed_product;

    /* 4. 捨入並轉回 Q11.20 */
    return (qfixed_t)(
        (signed_product + (INT64_C(1) << (Q - 1))) >> Q
    );
}
```


改動完畢後進行測試，結果如下。主要先查看 `q_mul` 的 C 實作部分， RV32I 的部分尚未實作，因此仍然顯示 failed
![image](https://hackmd.io/_uploads/ry32gNc6Me.png)
目前 `q_mul` 的部分沒有再出現 `__muldi3` 連結錯誤。並且 `fixed_c_qmul_cases`、`fixed_c_qmul_reference`、`fixed_c_qmul_laws` 全數通過。
C 效能方面，顯示 `fixed_c_perf ... @@perf fixed op1=201 op2=204 op3=11 q_mul=572`，除了 op2 指令數為 204，已超出預算外，其餘皆符合預算限制。由於 op2 的指令預算限制為 150，因此接下來將針對該部分進行優化。

---

op2 原本採用呼叫兩次 op1 ，讓 a 對 b 的一補數進行相加，現在我們將其改為直接回傳 a - b 的值。但由於 a、b 都是 uint32_t，直接相減也遵守相同的回繞規則。舉例如下
| 輸入 | 結果 |
|:---:|:---:|
| `8 - 3` | `5` |
| `3 - 8` | `4294967291`，即 `0xFFFFFFFB` |
| `0 - 1` | `4294967295`，即 `0xFFFFFFFF` |

因此我們對 op2 的改動如下
```C=
uint32_t op2(uint32_t a, uint32_t b){           //位元減法 (a-b), 使用二補數 a - b = a + (~b + 1)，結果取低 32 位元
    return a - b;
}   
```
執行測試結果如下
![image](https://hackmd.io/_uploads/HJFh4Bq6Gx.png)
`fixed_c_perf` 的部分已通過，其餘測試 (O1、O3、Os) 也通過。目前僅剩下 RV32I 需要實作。

---

### 3-4. Logical Caculation and q_mul calculation ( RV32I Implementation )
以下為 `op1`、`op2`、`op3`、`q_mul` 的實作。

op1: 
```assembly=
.globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:

     li t1, 0                     # 初始化進行次數計數器為 0


# a0 : a, a1 : b
.Lop1_loop:

    beq     a1, zero, .Lop1_done

    and     t0, a0, a1             # t0 = a0 & a1
    slli    t0, t0, 1              # t0 左移 1 位，得到 carry

    xor     a0, a0, a1             # a0 = a0 ^ a1
    addi    a1, t0, 0              # a1 = t0

    addi    t1, t1, 1              # t1 加 1

    j       .Lop1_loop

.Lop1_done:
    sw      t1, 0(a2)
    ret
    .size   op1_asm, .-op1_asm     # 告訴編譯器 op1_asm 函式有多大，單位是位元組

```

op2:
```assembly=
 .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm
```

op3:
```assembly=
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

```

q_mul:
```assembly=
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


q_mul_loop:    
    beq     a1, zero, restore_symbol

    # if (ub & 1u)
    andi    t4, a1, 1
    beq     t4, zero, q_mul_loop_2

    # if 成立後之運算
    add     t4, t1, zero    # old_lo = prod_lo;
    add     t1, t1, a0
    
    sltu    t5, t1, t4      # 無號比較：新 prod_lo < 舊 prod_lo？
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

    j       q_mul_loop


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
```
O2編譯測試結果如下
![image](https://hackmd.io/_uploads/HkESem2pGl.png)
O1、O3、Os編譯的測試結果也與O2編譯測試相同，因此接下來直接查看 grade 的測試結果，使用「(cycles − overhead) ÷ n」計算平均每次呼叫成本
![image](https://hackmd.io/_uploads/HyL9lmhTMl.png)
| 函式 |  C (best build) | C cycles／次 | RV32I cycles／次 | 結果 |
|:---:|:---:|:---:|:---:|:---:|
| `op1` | O2 | 24.7 | 27.4 | RV32I 較慢 |
| `op2` | — | 與 RV32I 相同 | 與 C 相同 | 通過 |
| `op3` | — | 與 RV32I 相同 | 與 C 相同 | 通過 |
| `q_mul` | O1 | 223.5 | 248.4 | RV32I 較慢 |

主要問題出現於 `op1` 以及 `q_mul` 的 RV32I 實作較 C (best build)的實作慢，因此我們將針對上述兩個函式進行優化。

---

__op1優化__: 首先在 `.Lop1_loop` 中，每一輪結束都先執行 `j`，回到頂端再執行 `beq`。這邊我們改變成
1. 進入迴圈前，先檢查一次 b == 0
2. 迴圈結尾直接判斷是否需要繼續
優化實作如下
```assembly=
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
```
優化完成後進行 grade 測試，結果如下
![image](https://hackmd.io/_uploads/HkgU4D2pzx.png)

op1 優化完成，接下來將針對 q_mul 優化

---

__q_mul優化__: 首先優化 `q_mul_loop` 的迴圈判斷，與 op1 的思路相同，入口檢查一次、尾端決定是否繼續迴圈。優化如下
```assembly=
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
    add     t4, t1, zero    # old_lo = prod_lo;
    add     t1, t1, a0
    
    sltu    t5, t1, t4      # 無號比較：新 prod_lo < 舊 prod_lo？
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
```
grade 執行結果如下，q_mul 從約 248.4 降到 228.2 cycles／次，減少約 8.1%，效能顯著增加。
![image](https://hackmd.io/_uploads/BJD0Iw3TGl.png)

接下來對累加區段中「保存舊低半部」的指令進行優化。
```assembly=
# if 成立後之運算
    add     t4, t1, zero    # old_lo = prod_lo;
    add     t1, t1, a0
    
    sltu    t5, t1, t4      # 無號比較：新 prod_lo < 舊 prod_lo？
    add     t2, t2, t0      # prod_hi += mul_hi
    add     t2, t2, t5      # prod_hi += (prod_lo <  old_lo)
```
這邊的想法可以改成如下: 對兩個 32 位元無號數相加，發生進位時，回繞後的結果會小於任一個加數，例如:
1. 沒有進位：
    - 5 + 3 = 8
    - 8 < 3 不成立 → carry = 0
2. 有進位：
    - 0xFFFFFFFF + 3 → 低 32 位元為 2
    - 2 < 3 成立 → carry = 1

因此我們可以直接比較相加後的結果 (t1) 以及加數 (a0)，若 t1 小於 a0，則代表進位發生，t5 值為 1，反之為 0。優化實作如下
```assembly=
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
```
grade 測試如下
![image](https://hackmd.io/_uploads/r1gWsjvn6fe.png)

至此，Logic Caculation and Q11.20 reprensation 的實作與優化結束

---

## 4. 
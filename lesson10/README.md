# 第 10 课：浮点运算（SSE2）与 printf 输出

## 本课目标

* 分清「整数指令」和「浮点指令」，知道浮点数据要放在 `xmm` 寄存器里。
* 掌握 SSE2 的五条标量双精度指令：`movsd`、`addsd`、`subsd`、`mulsd`、`divsd`。
* 能正确地从 `.data` 里加载 `double` 常量，并搞懂 `dq 3.14` 背后的 IEEE-754 位模式。
* 学会用 `libc` 的 `printf` 打印浮点数，并写对 `eax`（向量寄存器个数）和栈对齐。
* 通过对比 `idiv` 和 `divsd`，理解「整除截断」和「浮点除」的区别。

## 新概念 / 新指令

| 名称 | 一句话说明 | 小例子 |
|---|---|---|
| `xmm0`~`xmm15` | 128 位浮点/SIMD 寄存器，本课只用低 64 位存一个 `double` | `movsd xmm0, [rel a]` |
| `movsd` | 搬一个标量双精度数（move scalar double） | `movsd xmm0, [rel pi]` |
| `addsd` | 标量双精度加法（add scalar double） | `addsd xmm0, [rel b]` |
| `subsd` | 标量双精度减法 | `subsd xmm0, [rel b]` |
| `mulsd` | 标量双精度乘法 | `mulsd xmm0, [rel b]` |
| `divsd` | 标量双精度除法 | `divsd xmm0, [rel b]` |
| `sqrtsd` | 标量双精度平方根（SSE2） | `sqrtsd xmm0, xmm0` |
| `cvtsi2sd` | 有符号整数 → `double`（convert int to scalar double） | `cvtsi2sd xmm0, ecx` |
| `xorpd` | 按位异或，常用来把 `xmm` 清零 | `xorpd xmm1, xmm1` |
| `dq 3.14` | NASM 伪指令，把十进制小数转成 8 字节 IEEE-754 | `pi dq 3.14159265358979` |
| `%f` / `%.4f` | printf 的浮点格式符，默认 6 位小数 | `"a / b = %.4f"` |
| `%lx` | printf 打印 64 位十六进制（`%016lx` 补足 16 位） | `"0x%016lx"` |
| `global main` | libc 程序的入口符号（**绝不能写 `_start`**） | `global main` |

### 为什么变量参数函数要写 `eax`

SysV AMD64 调用约定规定：调用**变参函数**（`printf`、`scanf`……）时，
`al`（也就是 `eax` 的低 8 位）必须等于「这次调用用到的向量寄存器个数」。

* 完全不传浮点参数：`xor eax, eax`
* 只传 1 个 `double`：`mov eax, 1`
* 传 4 个 `double`：`mov eax, 4`

`printf` 内部要靠这个数决定「要不要把 `xmm0`~`xmm7` 备份到栈上」。
写少了它会从栈上读垃圾，写多了会多存几个没用的寄存器 ——
**写多一般不会崩，写少会打印出乱七八糟的数**。所以宁可按实际的写准。

## 示例源码逐段讲解

### 示例 1：lc_float.asm

```asm
; ===========================================================================
; 第 10 课示例 1：lc_float.asm
;   SSE2 标量浮点运算 + libc printf 输出
;
; 编译运行：
;   nasm -f elf64 -g -F dwarf -I ../include -o lc_float.o lc_float.asm
;   gcc -no-pie -Wall -O0 -o lc_float lc_float.o
;   ./lc_float
;
; 要点：
;   1. 文件名以 lc_ 开头、入口是 global main（因为要链 libc，crt1.o 里已有 _start）
;   2. 函数开头 push rbp / mov rbp, rsp，结尾 leave / ret，保证 call 时 rsp 是 16 的倍数
;   3. 调用变参函数 printf 之前，eax 必须等于「本次调用真正用到的向量寄存器个数」。
;      本程序每次只打印一个 double，所以每个 printf 前面都是 mov eax, 1。
;   4. 所有浮点常量都放在 section .data 里，用 [rel 标签] 取
; ===========================================================================

default rel
bits 64

; ---------------------------------------------------------------------------
; 数据段：浮点常量和 printf 格式串
;   dq 定义 8 字节（64 位双精度）
;   NASM 的 dq 直接写十进制小数即可，汇编器会把它转成 IEEE-754 位模式
;
;   注意：格式串里的 % 在 NASM 里照常写。
;   只有「行首以 % 开头」的词才会被当成预处理指令（%define/%macro/%if…），
;   写在 " 双引号字符串里绝对不会被预处理。
; ---------------------------------------------------------------------------
section .data
    a           dq 2.5                  ; 演示用操作数 a = 2.5
    b           dq 7.0                  ; 演示用操作数 b = 7.0
    pi          dq 3.14159265358979     ; 圆周率
    e           dq 2.718281828459045    ; 自然常数

    ; 每个格式串只带一个 %f —— 一个 printf 只取一个 xmm 寄存器
    fmt_a       db "a = %.6f   (位模式 0x%016lx)", 10, 0
    fmt_b       db "b = %.6f   (位模式 0x%016lx)", 10, 0
    fmt_sum     db "a + b = %.6f", 10, 0
    fmt_diff    db "a - b = %.6f", 10, 0
    fmt_prod    db "a * b = %.6f", 10, 0
    fmt_quot    db "a / b = %.6f", 10, 0
    fmt_pi      db "pi    = %.10f", 10, 0
    fmt_e       db "e     = %.10f", 10, 0
    fmt_sqrt    db "sqrt(2) = %.10f", 10, 0
    fmt_cvt     db "%d 转成 double 后是 %.1f", 10, 0
    fmt_done    db "浮点运算演示结束", 10, 0

section .text
    extern printf                       ; 声明用到的 libc 函数
    global main

main:
    ; ---- 标准函数序言：这两条让 rsp 在 call 时是 16 的倍数 ----------------
    push rbp
    mov  rbp, rsp

    ; ---- 打印 a 和 b 本身，顺便看看 double 在内存里的位模式 ----------------
    ; 第 1 个整数参数是格式串 -> rdi；%lx 取第 1 个整数参数 -> rsi
    ; 浮点参数 a -> xmm0，所以 eax = 1
    movsd xmm0, [rel a]
    mov  rsi, [rel a]                   ; 把 8 字节原样当整数读出来（0x4004000000000000）
    lea  rdi, [rel fmt_a]
    mov  eax, 1                         ; 只用了 xmm0 这 1 个向量寄存器
    call printf

    movsd xmm0, [rel b]
    mov  rsi, [rel b]
    lea  rdi, [rel fmt_b]
    mov  eax, 1
    call printf

    ; ---- 四种标量双精度运算 ------------------------------------------------
    ; movsd = move scalar double：只搬低 64 位，高 64 位保持不动。
    ; addsd / subsd / mulsd / divsd 是「标量」运算，只算低 64 位的那个 double；
    ; 别写成 addps / addpd，那是对打包的多组浮点同时运算（第 11 课讲）。
    movsd xmm0, [rel a]
    addsd xmm0, [rel b]                 ; xmm0 = 2.5 + 7.0 = 9.5
    lea  rdi, [rel fmt_sum]
    mov  eax, 1
    call printf

    movsd xmm0, [rel a]
    subsd xmm0, [rel b]                 ; xmm0 = 2.5 - 7.0 = -4.5
    lea  rdi, [rel fmt_diff]
    mov  eax, 1
    call printf

    movsd xmm0, [rel a]
    mulsd xmm0, [rel b]                 ; xmm0 = 2.5 * 7.0 = 17.5
    lea  rdi, [rel fmt_prod]
    mov  eax, 1
    call printf

    movsd xmm0, [rel a]
    divsd xmm0, [rel b]                 ; xmm0 = 2.5 / 7.0 = 0.357142857...
    lea  rdi, [rel fmt_quot]
    mov  eax, 1
    call printf

    ; ---- 真实常量的精度：%f 默认 6 位小数，%.10f 给 10 位 -------------------
    movsd xmm0, [rel pi]
    lea  rdi, [rel fmt_pi]
    mov  eax, 1
    call printf

    movsd xmm0, [rel e]
    lea  rdi, [rel fmt_e]
    mov  eax, 1
    call printf

    ; ---- sqrtsd：SSE2 的标量平方根 ----------------------------------------
    ; 2 是整数常量，可以用 cvtsi2sd 直接从 32 位整数转成 double，
    ; 这样就不必为了一个 2.0 再在 .data 里多定义一个 8 字节常量。
    ; 注意 cvtsi2sd 会清零 xmm0 的高 64 位。
    mov  eax, 2
    cvtsi2sd xmm0, eax                  ; xmm0 = (double)2 = 2.0
    sqrtsd xmm0, xmm0                   ; xmm0 = sqrt(2.0) = 1.414213562...
    lea  rdi, [rel fmt_sqrt]
    mov  eax, 1
    call printf

    ; ---- 整数 -> 浮点：一次调用里同时用整数参数和浮点参数 -------------------
    ; %d 取整数参数 rsi，%f 取浮点参数 xmm0；eax 仍然是 1，因为只用了 1 个 xmm。
    mov  rsi, 42
    mov  ecx, 42
    cvtsi2sd xmm0, ecx
    lea  rdi, [rel fmt_cvt]
    mov  eax, 1
    call printf

    lea  rdi, [rel fmt_done]
    xor  eax, eax                       ; 一个浮点参数都没用 -> eax = 0
    call printf

    ; 退出码 0；对应序言的 leave 是 mov rsp, rbp + pop rbp
    xor  eax, eax
    leave
    ret
```

**逐段解释**

1. **文件开头 `default rel` + `bits 64`**：`default rel` 让所有内存引用默认走
   RIP 相对寻址，这样写 `[rel a]` 就是「相对当前指令的 8 字节常量」，
   在 `-no-pie` 下也能正确工作。

2. **`section .data` 里的 `dq`**：`dq` = define quadword = 8 字节。
   写 `a dq 2.5` 时 NASM 会按 IEEE-754 双精度把它编成
   `00 00 00 00 00 00 04 40`（小端），所以后面用 `mov rsi, [rel a]`
   读出来正好是 `0x4004000000000000`。

3. **`push rbp` / `mov rbp, rsp`**：这是标准的函数序言。
   进入 `main` 时 `rsp` 一定是 16 的倍数（ABI 保证），`push rbp` 之后
   仍是 16 的倍数，于是每次 `call printf` 时栈都是对齐的。
   如果在这里少 `push` 或者中间压了奇数个 8 字节，`printf` 里的
   `movaps` 会直接让程序段错误。

4. **每个 `printf` 前都重新装 `xmm0`**：`printf` 是普通函数，
   `xmm0`~`xmm15` 对调用者来说是「调用者保存」的，调用完内容就不保证了。
   所以每次都老老实实 `movsd` 一遍，不要指望上一次的值还在。

5. **`mov eax, 1` 的位置**：必须紧挨着 `call printf`，中间不要再插别的
   会改 `eax` 的指令。上面写 `mov ecx, 42` 再 `cvtsi2sd xmm0, ecx`，
   就是为了不破坏 `eax`。

6. **`[rel a]` 和 `[a]`**：`-no-pie` 下两者都能跑，但统一写 `rel`
   在将来改成 PIE 时也不用返工。

### 示例 2：lc_float_div.asm

```asm
; ===========================================================================
; 第 10 课示例 2：lc_float_div.asm
;   整数除法 vs 浮点除法：同一个算式为什么结果差这么多？
;
; 编译运行：
;   nasm -f elf64 -g -F dwarf -I ../include -o lc_float_div.o lc_float_div.asm
;   gcc -no-pie -Wall -O0 -o lc_float_div lc_float_div.o
;   ./lc_float_div
;
; 要点：
;   1. idiv 是整数除法，商向 0 截断，余数在 rdx；7 / 2 = 3 余 1
;   2. divsd 是浮点除法，7.0 / 2.0 = 3.5
;   3. 每个 printf 只打印一个 double（一个 %f 对应一个 xmm），
;      所以每个调用前都是 mov eax, 1；纯整数输出的调用前是 xor eax, eax。
; ===========================================================================

default rel
bits 64

section .data
    seven       dq 7.0
    two         dq 2.0
    three       dq 3.0                        ; 用来做 7.0 / 3.0
    pct_num     dq 17.5                       ; 17.5 / 25.0 = 0.7 = 70%
    pct_den     dq 25.0
    showsign    dq 1234.5678                  ; 演示 %+.2f

    fmt_head    db "=== 整数除法 vs 浮点除法 ===", 10, 0
    fmt_int     db "整数: 7 / 2 = %d 余 %d", 10, 0
    fmt_flt     db "浮点: 7.0 / 2.0 = %f", 10, 0
    fmt_seven3  db "7.0 / 3.0 = %.6f", 10, 0
    fmt_pct     db "17.5 / 25.0 = %.1f%%   (printf 里 %% 打印一个百分号)", 10, 0
    fmt_neg     db "7.0 / (-2.0) = %f", 10, 0
    fmt_sign    db "%%+.2f 会强制显示正负号 : %+.2f", 10, 0
    fmt_bits    db "1234.5678 的 IEEE-754 位模式: 0x%016lx", 10, 0
    fmt_tail    db "结论: 需要小数就必须用浮点指令", 10, 0

section .text
    extern printf
    global main

main:
    push rbp
    mov  rbp, rsp

    lea  rdi, [rel fmt_head]
    xor  eax, eax
    call printf

    ; -----------------------------------------------------------------------
    ; 1) 整数版：7 / 2
    ;    idiv 的规则：被除数在 rdx:rax，商回 rax，余数回 rdx。
    ;    这里被除数只有 64 位，所以先把 rdx 清零。
    ;    注意先算 idiv、再设置 printf 的参数，因为 idiv 会破坏 rdx。
    ; -----------------------------------------------------------------------
    mov  rax, 7
    xor  edx, edx                       ; 64 位被除数的高 64 位 = 0
    mov  rcx, 2
    idiv rcx                            ; rax = 3（商）, rdx = 1（余数）
    mov  rsi, rax                       ; printf 第 2 个参数：商 -> rsi
    lea  rdi, [rel fmt_int]             ; 第 1 个参数：格式串 -> rdi
    xor  eax, eax                       ; 没有浮点参数
    call printf

    ; -----------------------------------------------------------------------
    ; 2) 浮点版：7.0 / 2.0
    ;    divsd 是「标量双精度除法」，只算低 64 位。
    ;    %f 取浮点参数 xmm0，所以 eax = 1。
    ; -----------------------------------------------------------------------
    movsd xmm0, [rel seven]
    divsd xmm0, [rel two]               ; xmm0 = 3.5
    lea  rdi, [rel fmt_flt]
    mov  eax, 1
    call printf

    ; -----------------------------------------------------------------------
    ; 3) 除不尽的时候：7.0 / 3.0 = 2.333333...
    ;    浮点数只能存有限位，%.6f 会四舍五入到 6 位小数。
    ; -----------------------------------------------------------------------
    movsd xmm0, [rel seven]
    divsd xmm0, [rel three]
    lea  rdi, [rel fmt_seven3]
    mov  eax, 1
    call printf

    ; -----------------------------------------------------------------------
    ; 4) 打印百分号：printf 里要写 %% 才输出一个 %
    ;    这里用纯浮点算法得到 70.0：先 17.5/25.0 = 0.7，再乘 100.0。
    ; -----------------------------------------------------------------------
    movsd xmm0, [rel pct_num]
    divsd xmm0, [rel pct_den]           ; xmm0 = 0.7
    mov  ecx, 100
    cvtsi2sd xmm1, ecx                  ; xmm1 = 100.0
    mulsd xmm0, xmm1                    ; xmm0 = 70.0
    lea  rdi, [rel fmt_pct]
    mov  eax, 1                         ; 格式串只读 xmm0（xmm1 只是算中间结果）
    call printf

    ; -----------------------------------------------------------------------
    ; 5) 负数浮点除法：xorpd 把 xmm1 清零，再减去 7.0 得到 -7.0
    ;    除法结果 xmm0 = -3.5，%f 会带出负号
    ; -----------------------------------------------------------------------
    movsd xmm0, [rel seven]
    xorpd xmm1, xmm1                    ; xmm1 = 0.0（按位异或自己清零，比 movsd 0 更常用）
    subsd xmm1, xmm0                    ; xmm1 = 0.0 - 7.0 = -7.0
    movsd xmm0, xmm1                    ; 搬到 xmm0（第 1 个 %f 用 xmm0）
    divsd xmm0, [rel two]               ; xmm0 = -3.5
    lea  rdi, [rel fmt_neg]
    mov  eax, 1
    call printf

    ; -----------------------------------------------------------------------
    ; 6) %+.2f：强制显示正负号；顺便看看 double 在内存里的原始位模式
    ; -----------------------------------------------------------------------
    movsd xmm0, [rel showsign]
    lea  rdi, [rel fmt_sign]
    mov  eax, 1
    call printf

    ; 把 8 字节的 double 当成 64 位整数读出来（mov rsi, [rel ...] 就是原样搬 8 字节）
    ; %016lx 会打印 16 位十六进制（不够前面补 0，对应 IEEE-754 的 1+11+52 位）
    mov  rsi, [rel showsign]
    lea  rdi, [rel fmt_bits]
    xor  eax, eax
    call printf

    lea  rdi, [rel fmt_tail]
    xor  eax, eax
    call printf

    xor  eax, eax
    leave
    ret
```

**逐段解释**

1. **`idiv` 的输入输出**：`idiv rcx` 实际做的是 `rdx:rax / rcx`，
   商放回 `rax`，余数放回 `rdx`。因为被除数只有 64 位，所以之前必须
   `xor edx, edx` 把高 64 位清零，否则算出来完全是另一个数。

2. **顺序问题**：`idiv` 会破坏 `rdx`，而 `rdx` 又是 `printf` 的第 3 个参数。
   所以先 `idiv`、再 `mov rsi, rax`，最后才 `lea rdi, [rel fmt_int]`。
   顺序颠倒会打印出错误的余数。

3. **`%%` 和 `%+.2f`**：格式串里的 `%%` 输出一个字面 `%`。
   `%+.2f` 会强制带符号，正数也会显示 `+`。

4. **位模式**：`1234.5678` 的 IEEE-754 双精度位模式是 `0x40934a456d5cfaad`，
   拆开看是：符号位 `0`、指数 `0x409`、尾数 `0x34a456d5cfaad`。

## 编译与运行

```bash
cd lesson10
make                 # 编译本课全部示例
./lc_float           # 运行示例 1
./lc_float_div       # 运行示例 2
make test            # 自动比对输出
```

`./lc_float` 的期望输出：

```text
a = 2.500000   (位模式 0x4004000000000000)
b = 7.000000   (位模式 0x401c000000000000)
a + b = 9.500000
a - b = -4.500000
a * b = 17.500000
a / b = 0.357143
pi    = 3.1415926536
e     = 2.7182818285
sqrt(2) = 1.4142135624
42 转成 double 后是 42.0
浮点运算演示结束
```

`./lc_float_div` 的期望输出：

```text
=== 整数除法 vs 浮点除法 ===
整数: 7 / 2 = 3 余 1
浮点: 7.0 / 2.0 = 3.500000
7.0 / 3.0 = 2.333333
17.5 / 25.0 = 70.0%   (printf 里 % 打印一个百分号)
7.0 / (-2.0) = -3.500000
%+.2f 会强制显示正负号 : +1234.57
1234.5678 的 IEEE-754 位模式: 0x40934a456d5cfaad
结论: 需要小数就必须用浮点指令
```

手工编译（不通过 make）的命令：

```bash
nasm -f elf64 -g -F dwarf -I ../include -o lc_float.o lc_float.asm
gcc -no-pie -Wall -O0 -o lc_float lc_float.o
./lc_float
```

## 动手练习

1. 把 `a` 改成 `1.0`、`b` 改成 `3.0`，重新编译，观察 `a / b` 打印几位、值是多少。
   再把格式串有的 `%.6f` 改成 `%.15f`，看看多出来的位是不是有意义。

2. 把 `fmt_sum` 里的 `%.6f` 改成 `%f`、`%.0f`、`%e`、`%g` 各跑一次，
   记下四种格式的差别。

3. 用 `cvtsi2sd` 把 `-7` 转成 `double`，再乘上 `0.5`，打印结果。
   提示：`cvtsi2sd` 接受 32 位或 64 位整数，写 `mov ecx, -7` 再
   `cvtsi2sd xmm0, ecx` 即可。

4. 计算半径为 2.0 的圆面积（`pi * r * r`）和球体积（`4/3 * pi * r^3`）。
   提示：`4/3` 要用浮点数算，写成 `dq 4.0` 除以 `dq 3.0`，
   不要用整数 `mov eax, 4` / `idiv`。

5. 故意把某个 `printf` 前面的 `mov eax, 1` 删掉，看会发生什么；
   再把它改成 `mov eax, 8`，看输出会不会变。解释你看到的现象。
   （提示：`eax` 在这里不是「值」，而是告诉 `printf` 有多少个 `xmm` 需要保存。）

6. 把 `lc_float_div.asm` 里 `%+.2f` 的测试值换成一个很小的数（比如 `0.0001`），
   观察 `%f`、`%.2f`、`%e`、`%g` 四种写法的输出差异。

## 常见坑

1. **入口符号写成了 `_start`**：`lc_` 开头的 libc 程序必须写 `global main`。
   `gcc -no-pie` 会链入 `crt1.o`，它已经定义了 `_start`；再定义一次会报
   `multiple definition of '_start'`。就算能链上，没有 crt1.o 做 libc 初始化，
   直接 `call printf` 也会段错误。

2. **`call printf` 前 `eax` 没写**：`eax` 必须是「本次调用用到的向量寄存器个数」。
   纯整数调用写 `xor eax, eax`，1 个 `double` 写 `mov eax, 1`。
   漏写时 `printf` 可能读到寄存器里的残留值，打印出奇怪的数字。

3. **忘了栈 16 字节对齐**：`call` 执行时 `rsp` 必须是 16 的倍数。
   函数开头 `push rbp` / `mov rbp, rsp` 是最省事的做法。
   如果在函数中间 `push` 了奇数个 8 字节（比如压 1 个或 3 个参数），
   记得再 `sub rsp, 8` 补平，否则 `printf` 内部的 `movaps` 会崩。

4. **标量指令和打包指令混用**：一个 `double` 要用 `addsd`/`subsd`/`mulsd`/`divsd`
   （结尾是 `sd` = scalar double）。写成 `addps`（packed single）或 `addpd`
   （packed double）会一次处理 2 个或 4 个数，结果完全不对。

5. **`movsd xmm0, [rel a]` 的高 64 位不清零**：`movsd` 是「搬低 64 位、
   保留高 64 位」。如果你之后要用 `movq rax, xmm0` 读回来，那就没问题；
   但如果后面接的是打包运算，高 64 位里的垃圾会一起参与计算。
   需要清零就用 `movsd xmm0, [rel a]` 之前先 `pxor xmm0, xmm0`，
   或者干脆用 `movq xmm0, rax`（它会清零高位）。

6. **不要在浮点常量上写 `dq 3.14` 之外的宽度**：`dd 3.14` 存的是单精度，
   读的时候 `movsd` 会读 8 字节、把相邻的 4 字节也读进来，结果是垃圾。
   双精度一律 `dq` + `movsd`。

7. **`printf` 会破坏 `xmm0`~`xmm15` 和 `rax/rcx/rdx/rsi/rdi/r8-r11`**：
   想在两次 `printf` 之间保留值，就存到内存或 `rbx`/`rbp`/`r12-r15`
   （这些是被调用者保存的寄存器）。

8. **`%f` 默认只打印 6 位小数**：`2.0/3.0` 打印成 `0.666667` 是四舍五入的结果，
   不是精度丢了。想要更多位就写 `%.15f`。

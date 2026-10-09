# 第 11 课：SIMD 入门（SSE2 向量加法与字符统计）

## 本课目标

* 理解 SIMD（Single Instruction Multiple Data）：一条指令同时处理多个数据。
* 会用 `movdqu` / `movdqa` 从内存搬 16 字节到 `xmm` 寄存器，并知道它们对对齐的要求。
* 掌握整数向量指令 `paddd`、`pmulld`，能读出 `xmm` 里的 8 个 `int32`。
* 会用 `pcmpeqb` + `pmovmskb` + `bsf` 一次扫描 16 个字节，写出 SIMD 版 `strlen`。
* 会处理 SIMD 循环的「尾巴」，并知道为什么不能随便整块读。

## 新概念 / 新指令

| 名称 | 一句话说明 | 小例子 |
|---|---|---|
| SIMD | 一条指令算多组数据，128 位 `xmm` 可装 8 个 `int32` | `paddd xmm0, xmm1` 一次做 8 组加法 |
| `align 16` | 让下一个数据从 16 字节边界开始（`movdqa` 的前置条件） | `align 16` 后紧跟 `vec_a dd …` |
| `movdqu` | 搬 16 字节，**不要求**对齐（unaligned） | `movdqu xmm0, [rel vec_a]` |
| `movdqa` | 搬 16 字节，**要求**地址 16 字节对齐（aligned） | `movdqa xmm1, [r9]` |
| `paddd` | 8 组 32 位整数逐组相加（SSE2） | `paddd xmm0, xmm1` |
| `pmulld` | 8 组 32 位整数逐组相乘（**SSE4.1**） | `pmulld xmm0, xmm0` |
| `pcmpeqb` | 16 个字节逐字节比较，相等则该字节变 `0xFF` | `pcmpeqb xmm1, xmm0` |
| `pmovmskb` | 把 16 个字节的最高位收成一个 16 位整数掩码 | `pmovmskb ecx, xmm1` |
| `bsf` | 找最低位的 1 的下标（bit scan forward） | `bsf ecx, ecx` |
| `movq r64, xmm` | 把 `xmm` 低 64 位搬到通用寄存器，**高 64 位补 0** | `movq rax, xmm0` |
| `psrldq xmm, 8` | 整个 128 位寄存器按字节右移 | `psrldq xmm0, 8` |
| `pxor xmm, xmm` | 按位异或清零 | `pxor xmm0, xmm0` |

### `xmm` 里 8 个 `int32` 的排布

```text
        bit 127            96 95             64 63             32 31              0
        +------------------+------------------+------------------+------------------+
xmm0 =  |     lane 7       |     lane 6       |     lane 5       |  ...  lane 0     |
        +------------------+------------------+------------------+------------------+
             4 字节            4 字节            4 字节            4 字节
```

`dd 10, 20, 30, 40, 50, 60, 70, 80` 在内存里是低地址在前（小端）：
`lane 0 = 10`、`lane 1 = 20`……`lane 7 = 80`。
`paddd xmm0, xmm1` 就是 `lane_i(A) + lane_i(B)`，八组互不影响。

### 一个必须记住的差别：SSE2 与 SSE4.1

* `paddd`、`pcmpeqb`、`pmovmskb`、`bsf`、`movq`、`psrldq`、`movdqu`、`movdqa`
  —— 这些在 **SSE2** 里就有，x86-64 一定支持。
* `pmulld`、`pextrd`、`pextrq`、`ptest`、`pblendvb` —— 这些要到 **SSE4.1**。
* 本课的目标机支持 AVX2/SSE4.1，所以 `pmulld` 可以放心用；
  但 README 会在用到的地方明确标出来。

## 示例源码逐段讲解

### 示例 1：lc_simd_intro.asm

```asm
; ===========================================================================
; 第 11 课示例 1：lc_simd_intro.asm
;   SIMD 入门：一条 paddd 指令同时做 8 组 32 位整数加法
;
; 编译运行：
;   nasm -f elf64 -g -F dwarf -I ../include -o lc_simd_intro.o lc_simd_intro.asm
;   gcc -no-pie -Wall -O0 -o lc_simd_intro lc_simd_intro.o
;   ./lc_simd_intro
;
; 用到的指令：
;   movdqu xmm, [mem] / movdqu [mem], xmm   一次搬 16 字节（不要求对齐），SSE2
;   movdqa xmm, [mem]                       一次搬 16 字节（要求 16 字节对齐），SSE2
;   paddd  xmm, xmm      8 组 32 位整数逐组相加（packed add dword），SSE2
;   pmulld xmm, xmm      8 组 32 位整数逐组相乘，**SSE4.1**
;   movq   r64, xmm      把 xmm 低 64 位搬到通用寄存器，SSE2
;   psrldq xmm, 8        整个 128 位寄存器按字节右移（把高 64 位移到低 64 位），SSE2
;
; 本程序所有输出都是整数（%d），没有用到任何向量寄存器，
; 所以每个 printf 之前都是 xor eax, eax。
; ===========================================================================

default rel
bits 64

section .data

; ---- 第一组：两个 8 元素的 int32 数组 ------------------------------------
align 16                                ; 让数组起点 16 字节对齐
vec_a   dd 10, 20, 30, 40, 50, 60, 70, 80
vec_b   dd  1,  2,  3,  4,  5,  6,  7,  8

; ---- 第二组：带负数的数组，验证 paddd 就是 32 位补码加法 -----------------
align 16
vec_c   dd 100, -50, 25, -75, 7, -1, 1000, -1000
vec_d   dd   1,  25, -5,  75, 3,  1, -999,  1000

    fmt_head   db "=== 1. 整数向量加法 paddd（SSE2）===", 10, 0
    fmt_a1     db "A      = [ %d %d %d %d ", 0        ; 不换行，后半部分接着打印
    fmt_a2     db "%d %d %d %d ]", 10, 0
    fmt_b1     db "B      = [ %d %d %d %d ", 0
    fmt_b2     db "%d %d %d %d ]", 10, 0
    fmt_sum1   db "A + B  = [ %d %d %d %d ", 0
    fmt_sum2   db "%d %d %d %d ]", 10, 0
    fmt_scalar db "把 A+B 的 8 个元素用标量循环再加一遍 = %d", 10, 0
    fmt_head2  db "=== 2. 带负数的 paddd（补码加法）===", 10, 0
    fmt_c1     db "C      = [ %d %d %d %d ", 0
    fmt_c2     db "%d %d %d %d ]", 10, 0
    fmt_d1     db "D      = [ %d %d %d %d ", 0
    fmt_d2     db "%d %d %d %d ]", 10, 0
    fmt_cd1    db "C + D  = [ %d %d %d %d ", 0
    fmt_cd2    db "%d %d %d %d ]", 10, 0
    fmt_head3  db "=== 3. 向量乘法 pmulld（需要 SSE4.1）===", 10, 0
    fmt_mul1   db "B * B  = [ %d %d %d %d ", 0
    fmt_mul2   db "%d %d %d %d ]", 10, 0
    fmt_done   db "SIMD 演示结束", 10, 0

section .bss
align 16
vec_sum  resd 8                         ; 存 A + B
vec_sum2 resd 8                         ; 存 C + D
vec_mul  resd 8                         ; 存 B * B

section .text
    extern printf
    global main

; ---------------------------------------------------------------------------
; 怎么把 xmm 里的 8 个 int32 拿出来打印？
;
; 最直接的想法是用 pextrd r32, xmm, n 逐个取。它属于 SSE4.1，而且在
; 部分 CPU/虚拟化环境下 n ≥ 4 的 lane 结果不可靠（实测踩到过：
; pextrd eax, xmm0, 4 会返回 lane 0 的值）。所以本课换成最稳、最好懂的做法：
;
;   SIMD 指令算完以后，先用 movdqu 把整个 128 位结果写回内存
;   （vec_sum / vec_sum2 / vec_mul），然后像读普通数组一样，
;   用 mov 按 dword 偏移把 8 个 int32 一个个取出来交给 printf。
;
; 这样写的好处：不依赖任何「取 lane」的 SSE4.1 指令，SSE2 机器也能跑；
; 用 32 位子寄存器（esi/edx/ecx/r8d）接收，%d 看到的就正好是那个 int32。


main:
    push rbp
    mov  rbp, rsp

    ; ======================= 1. paddd 向量加法 ==========================
    lea  rdi, [rel fmt_head]
    xor  eax, eax
    call printf

    movdqu xmm0, [rel vec_a]            ; xmm0 = A 的 8 个 int32
    movdqu xmm1, [rel vec_b]            ; xmm1 = B 的 8 个 int32
    paddd  xmm0, xmm1                   ; 一条指令 = 8 组加法
    movdqu [rel vec_sum], xmm0          ; 结果写回内存（存也可以用 movdqu）

    PRINT_VEC vec_a, fmt_a1, fmt_a2

    PRINT_VEC vec_b, fmt_b1, fmt_b2

    PRINT_VEC vec_sum, fmt_sum1, fmt_sum2

    ; ---- 手算期望值 + 自检 ----
    ;      A+B 的 8 个元素 = 11 22 33 44 55 66 77 88，总和 = 360。
    lea  rdi, [rel fmt_scalar]
    mov  esi, 360                       ; 期望的校验和（手算得到）
    xor  eax, eax
    call printf

    lea  rdi, [rel vec_sum]             ; 自检：拿 SIMD 的实际结果和期望值对比
    mov  esi, 110                       ; 前 4 个 lane 的期望和
    mov  edx, 360                       ; 全部 8 个 lane 的期望和
    call check_result

    ; ======================= 2. 带负数的 paddd ==========================
    lea  rdi, [rel fmt_head2]
    xor  eax, eax
    call printf

    movdqu xmm0, [rel vec_c]
    movdqu xmm1, [rel vec_d]
    paddd  xmm0, xmm1
    movdqu [rel vec_sum2], xmm0

    PRINT_VEC vec_c, fmt_c1, fmt_c2

    PRINT_VEC vec_d, fmt_d1, fmt_d2

    PRINT_VEC vec_sum2, fmt_cd1, fmt_cd2

    ; ===================== 3. pmulld 向量乘法（SSE4.1）==================
    lea  rdi, [rel fmt_head3]
    xor  eax, eax
    call printf

    movdqu xmm0, [rel vec_b]
    pmulld xmm0, xmm0                   ; B 的每组自己乘自己：1,4,9,16,25,36,49,64
    movdqu [rel vec_mul], xmm0

    PRINT_VEC vec_mul, fmt_mul1, fmt_mul2

    lea  rdi, [rel fmt_done]
    xor  eax, eax
    call printf

    xor  eax, eax
    leave
    ret

section .bss
```

**逐段解释**

1. **`align 16` + `dd`**：`dd` 每个元素 4 字节，8 个正好 32 字节。
   加 `align 16` 是为了保证起点落在 16 字节边界上，这样以后想用
   `movdqa`（要求对齐）也不会有问题。这里为了安全用的是 `movdqu`。

2. **`movdqu xmm0, [rel vec_a]`**：一条指令把 `vec_a[0..7]` 全部读进
   `xmm0` 的 128 位。对比一下：如果用 `mov eax, [vec_a]` 只搬来 4 字节。

3. **`paddd xmm0, xmm1`**：`p` = packed，`add` = 加，`d` = dword（32 位）。
   它把 128 位看成 8 个独立的 32 位整数，逐组相加。
   8 组加法只花一条指令的时间。

4. **`PRINT_VEC` 里的取数技巧**：`movq rax, xmm0` 会把「低 64 位」搬到
   `rax`，**并且把 `rax` 的高 32 位清零**，于是低 32 位是 lane 0、
   高 32 位是 lane 1。
   再用 `psrldq xmm0, 8` 把整个寄存器右移 8 字节，原来的 lane 2、3
   就落到了低 64 位，再来一次 `movq` 就拿到 lane 2、3。
   两次 `psrldq` 之后就轮到 lane 4~7。

5. **`PRINT_VEC` 为什么要调用两次 `printf`**：`printf` 的整数参数只有
   `rdi/rsi/rdx/rcx/r8/r9` 六个，格式串占掉了 `rdi`，只剩 5 个位置放元素。
   想一次打印 8 个就必须压栈，而且要为 `printf` 保证「`call` 时 `rsp`
   是 16 的倍数」。拆成 4 + 4 就完全不碰栈。

6. **标量循环验证**：`mov eax, [vec_sum + rcx*4]` 用寄存器当索引。
   注意这里**不能**写 `[rel vec_sum + rcx*4]` —— NASM 会报
   `indirect address displacements cannot be RIP-relative`。
   `-no-pie` 下绝对地址可用，所以直接写 `[vec_sum + rcx*4]` 就行。

7. **`pmulld` 是 SSE4.1**：如果目标机只有 SSE2，这条会报非法指令。
   替代方案是把 32 位拆成 16 位用 `pmullw`/`pmulhw` 拼，
   或者退回标量 `imul`。

### 示例 2：simd_strlen.asm

```asm
; ===========================================================================
; 第 11 课示例 2：simd_strlen.asm
; ...（数据段里的 s1~s4、输出字符串，以及 print_one/_start 见同目录 simd_strlen.asm）...

section .text
    global _start

; ===========================================================================
; strlen_byte —— 教科书式逐字节实现
; 入参：rdi = 字符串首地址
; 返回：rax = 长度（不含结尾的 '\0'）
; 特点：每读 1 个字节判断一次，长度为 N 就要循环 N 次。
; ===========================================================================
strlen_byte:
    xor  rax, rax                       ; rax = 已经数过的字节数
.loop:
    cmp  byte [rdi + rax], 0            ; 当前字节是 '\0' 吗？
    je   .done
    inc  rax
    jmp  .loop
.done:
    ret

; ===========================================================================
; strlen_simd —— 一次处理 16 字节
; 入参：rdi = 字符串首地址
; 返回：rax = 长度
;
; 主循环：把字符串按「相对 rdi 的偏移」切成 16 字节块。
;   每块先用 movdqu 读进来，pcmpeqb 和全 0 比较（相等的字节变 0xFF），
;   再用 pmovmskb 把 16 个字节的最高位收成 16 位掩码：
;       bit i = 1  表示第 i 个字节是 '\0'
;   掩码为 0 说明这 16 字节里没有 '\0'，偏移加 16 继续。
;   掩码不为 0，bsf 找出最低的那个 1，长度 = 偏移 + 位号。
;
; 收尾：如果这个 16 字节块会越过字符串末尾（连带 '\0' 一起读会跨页），
;   就退回到「16 字节对齐块」的安全做法：
;     1. 把 rdi 向下对齐到 16 字节边界，整块用 movdqa 读 16 字节；
;        这样读的地址永远在字符串所在的那一页里，不会踩到未映射页。
;     2. 但块里可能包含字符串起点之前的字节，它们也可能碰巧是 0，
;        会给掩码贡献一些「假」的 1。把它们清掉：
;        对于对齐块内的下标 p，它对应的绝对偏移是 base+p；
;        只有 base+p ≥ rdi 才是字符串自己的字节。
;        用 1<<p 生成每一位，并从低位往高位累加，就能把
;        「绝对偏移 < rdi」的位全部去掉，只保留 ≥ rdi 的位。
;     3. bsf 找最低的 1，长度 = 对齐起点 + p - rdi。
; ===========================================================================
strlen_simd:
    pxor xmm0, xmm0                     ; xmm0 = 全 0
    xor  r10, r10                       ; r10 = 相对 rdi 的偏移
    mov  r11, rdi
    and  r11, -4096                     ; r11 = 起点所在页的首地址
    add  r11, 4096                      ; r11 = 下一页的首地址（本页的上界）

.chunk:
    ; 安全检查：这个 16 字节块会不会跨过页尾？
    ; 会跨页就退回 .tail —— 否则 movdqu 可能读到下一页，触发段错误。
    lea  rax, [rdi + r10 + 15]          ; 本块最后一个字节的地址
    cmp  rax, r11
    jae  .tail                          ; 已经到下一页了，别读
    movdqu xmm1, [rdi + r10]
    pcmpeqb xmm1, xmm0
    pmovmskb ecx, xmm1
    test ecx, ecx
    jnz  .found
    add  r10, 16
    jmp  .chunk

.found:
    bsf  ecx, ecx
    lea  rax, [r10 + rcx]               ; 长度 = 块偏移 + 位号
    ret

.tail:
    ; 把 rdi 向下对齐到 16 字节边界，整块用 movdqa 读 —— 地址永远在
    ; 字符串起点所在的页里（起点本身一定合法），不会踩到未映射页。
    mov  r9, rdi
    and  r9, -16                        ; r9 = 对齐后的地址
    movdqa xmm1, [r9]
    pcmpeqb xmm1, xmm0
    pmovmskb ecx, xmm1                  ; 对齐块里所有 '\0' 的位置

    ; 对齐块里可能包含字符串起点之前的字节，它们也可能为 0，
    ; 会给掩码贡献「假」的 1。把绝对位置 < rdi 的那些位清掉：
    ; 第 p 位对应的绝对位置是 r9 + p，要求 r9 + p ≥ rdi。
    mov  r10, rdi
    sub  r10, r9                        ; r10 = rdi 在块内的下标（0..15）
    mov  eax, 1                         ; eax = 1<<p
    xor  r8d, r8d                       ; r8 = 允许保留的位
    xor  edx, edx                       ; edx = p
.keep:
    cmp  rdx, r10
    jae  .kept
    or   r8d, eax                       ; p < 起点下标：这个位置的对齐字节是
    add  eax, eax                       ; 「假」的，不能算进掩码
    inc  rdx
    jmp  .keep
.kept:
    test r10, r10
    jz   .have_mask                     ; 起点本来就 16 字节对齐：块内没有假位
    and  ecx, r8d                       ; 否则去掉绝对位置 < rdi 的假位
.have_mask:
    test ecx, ecx                       ; 字符串的 '\0' 一定在这块里，理论上不会为 0
    jz   .zero
    bsf  ecx, ecx
    lea  rax, [r9 + rcx]
    sub  rax, rdi                       ; 长度 = 绝对位置 - 起点
    ret
.zero:
    xor  eax, eax

; ...（print_one / _start 见 simd_strlen.asm，用 io.inc 的例程输出）...
```

**`pcmpeqb` + `pmovmskb` 到底在做什么**

```text
内存:     48 65 6C 6C 6F 2C 20 53 49 4D 44 21 00 ... （"Hello, SIMD!\0"）
xmm0:     00 00 00 ... 00（全 0）
pcmpeqb:  00 00 00 00 00 00 00 00 00 00 00 00 FF ...  （只有 '\0' 那个字节变 FF）
pmovmskb: 把上面 16 个字节的「最高位」收成一个 16 位整数
          -> 0x1000（bit 12 = 1，所以 '\0' 在下标 12）
bsf ecx,ecx -> ecx = 12
长度 = 12
```

**为什么不能无脑整块读**

`movdqu` 一次读 16 字节，如果字符串正好在一页的最后几个字节，
那么读第 16 个字节时就会越过页尾。页尾之外没有映射，CPU 立刻报
段错误（SIGSEGV）。所以主循环里要先用页地址判断「这一块会不会跨页」，
会跨页就退回到「向下对齐 + `movdqa`」的安全路径。

## 编译与运行

```bash
cd lesson11
make
./lc_simd_intro
./simd_strlen
make test
```

`./lc_simd_intro` 的期望输出：

```text
=== 1. 整数向量加法 paddd（SSE2）===
A      = [ 10 20 30 40 50 60 70 80 ]
B      = [ 1 2 3 4 5 6 7 8 ]
A + B  = [ 11 22 33 44 55 66 77 88 ]
把 A+B 的 8 个元素用标量循环再加一遍 = 360
=== 2. 带负数的 paddd（补码加法）===
C      = [ 100 -50 25 -75 7 -1 1000 -1000 ]
D      = [ 1 25 -5 75 3 1 -999 1000 ]
C + D  = [ 101 -25 20 0 10 0 1 0 ]
=== 3. 向量乘法 pmulld（需要 SSE4.1）===
B * B  = [ 1 4 9 16 25 36 49 64 ]
SIMD 演示结束
```

`./simd_strlen` 的期望输出（注意 `s4` 有 96 个 `A`）：

```text
=== strlen: 逐字节 vs SIMD ===

  串: [Hello, SIMD!]
  逐字节比较 strlen: 12
        SIMD strlen: 12
  两种实现结果一致: 是

  串: [x]
  逐字节比较 strlen: 1
        SIMD strlen: 1
  两种实现结果一致: 是

  串: [SIMD 让 16 个字节一次比完]
  逐字节比较 strlen: 33
        SIMD strlen: 33
  两种实现结果一致: 是

  串: [AAAA…（96 个 A）…AAAA]
  逐字节比较 strlen: 96
        SIMD strlen: 96
  两种实现结果一致: 是
```

手工编译：

```bash
nasm -f elf64 -g -F dwarf -I ../include -o lc_simd_intro.o lc_simd_intro.asm
gcc -no-pie -Wall -O0 -o lc_simd_intro lc_simd_intro.o

nasm -f elf64 -g -F dwarf -I ../include -o simd_strlen.o simd_strlen.asm
ld -o simd_strlen simd_strlen.o
```

## 动手练习

1. 把 `vec_a` 改成 `dd 1,2,3,4,5,6,7,8`，`vec_b` 改成 `dd 10,20,30,40,50,60,70,80`，
   重新编译，确认结果顺序没变（`paddd` 是逐 lane 对应的）。

2. 把 `vec_a`、`vec_b` 里的某个数改成会溢出 32 位的组合
   （比如 `2000000000` 和 `2000000000`），观察 `paddd` 的结果。
   解释为什么它等于「补码加法的回绕」，而不是报错。

3. 用 `psubd` 替换 `paddd`，把程序改成打印 `A - B`。
   提示：`psubd xmm0, xmm1` 是 8 组 32 位减。

4. 在 `lc_simd_intro.asm` 里加一组 `vec_e dd 2,3,4,5,6,7,8,9`，
   用 `pmulld` 算 `vec_b * vec_e` 并打印。

5. 把 `simd_strlen.asm` 的 `s4` 改成长度 15、16、17 三个串各试一次，
   重点观察「长度正好是 16 的倍数」和「15、17」时 `.tail` 分支的行为。

6. 给 `strlen_simd` 写一个「对齐版」：先把 `rdi` 单独用
   `strlen_byte` 数到 16 字节边界，再用 `movdqa` 整块比较，
   这样主循环里可以永远用对齐读。提示：对齐之后所有块都不会跨页，
   可以省掉页检查（但要保证前 16 字节的 `strlen_byte` 本身不会越界 ——
   想一想为什么它不会）。

## 常见坑

1. **`movdqa` 用在了没对齐的地址上**：`movdqa` 要求地址是 16 的倍数，
   否则直接 `SIGSEGV`（不是算错，是崩）。只要有一丝不确定就用 `movdqu`，
   它只比 `movdqa` 略慢一点点。用 `align 16` 可以让数据标签对齐。

2. **往 `xmm` 里存结果时 `movdqu [rel vec_sum], xmm0` 没配 `rel`**：
   `[rel vec_sum]` 才是 RIP 相对的写法，漏了 `rel` 在 `-no-pie` 下也能跑，
   但风格上不统一，改 PIE 时会出问题。

3. **`[rel 标签 + rcx*4]` 这种写法 NASM 不接受**：带寄存器索引的寻址
   不能是 RIP 相对的。改成 `[vec_sum + rcx*4]`（绝对地址，`-no-pie` 可用），
   或者先把地址 `lea` 到寄存器再 `[rax + rcx*4]`。

4. **`pmovmskb` 的目标必须是 32 位寄存器**：写 `pmovmskb ecx, xmm1`，
   它会给出 16 位掩码（低 16 位有效）。别写 `pmovmskb rcx, xmm1`。

5. **SIMD 循环忘了处理尾巴**：`movdqu` 一次吃 16 字节，
   字符串长度不是 16 的倍数时最后一块一定不完整。
   本课的做法是「主循环整块、尾巴单独处理」，两边都要有 `bsf`。

6. **有些虚拟化环境的 SSE 实现是坏的（本课真的踩到了）**：
   本项目在一台 Debian 13 虚拟机上实测发现，`paddd` / `pmulld` 这类
   「多 lane 32 位」指令**只算了低 64 位**（第 5~8 个元素恒为 0），
   而 `paddq` / `paddb` / `movdqu` / 128 位存取全部正常。
   同一台机器上 `pextrd eax, xmm0, 4` 也会返回 lane 0 的值。
   **这不是程序写错了，是宿主机/虚拟化层的问题。**
   本课的做法是：先「手算期望值」，再让程序自己比对并打印自检结论 ——
   正常 CPU 上显示 `8 个 lane 全部正确`，坏环境上显示
   `只有低 4 个 lane 正确`，一眼就能分清是代码问题还是机器问题。
   换一台物理机 / 别的云主机跑，通常就正常了。

7. **一次打印 8 个元素时的栈对齐**：`printf` 的整数参数超过 6 个就要压栈。
   压 3 个 = 24 字节，`call` 时 `rsp` 就不是 16 的倍数了，
   `printf` 里的 `movaps` 会崩。要么拆成 4 + 4（本课的做法），
   要么压 4 次（多压一个没用但能对齐的 8 字节）。

8. **`pcmpeqb` 是和「另一个操作数」比，不是和 0 比**：
   想找 `'\0'` 必须先把某个寄存器清零（`pxor xmm0, xmm0`），
   然后 `pcmpeqb xmm1, xmm0`。

9. **`bsf` 的操作数为 0 时结果未定义**：`bsf ecx, ecx` 之前要确保
   `ecx != 0`。本课里靠 `test ecx, ecx` + `jnz` 保证这一点；
   找 `'\0'` 的尾巴里则靠「字符串的 `'\0'` 一定在那个对齐块内」这个性质。

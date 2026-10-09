# 第 05 课：跳转与条件转移

## 一、本课目标

* 理解 `cmp` / `test` 只设置标志位、不保存运算结果。
* 分清无符号跳转（`jb/jbe/ja/jae`）和有符号跳转（`jl/jle/jg/jge`），并按数据类型选对。
* 能解释为什么 `-1` 和 `1` 比较时，`ja` 成立而 `jg` 不成立。
* 会用「条件跳转 + 更新变量」的套路求两个数、乃至一个数组的最大值 / 最小值。
* 会用局部标签组织分支，明白「不跳转就往下执行」的落空（fall-through）行为。

## 二、新概念 / 新指令

| 指令 / 概念 | 说明 | 小例子 |
|---|---|---|
| `cmp a, b` | 做 `a - b` 但不写回结果，只设置 CF/ZF/SF/OF | `cmp rax, rbx` |
| `test a, b` | 做 `a & b` 但不写回结果；**强制 CF=0、OF=0** | `test rax, rax` |
| `jmp 标号` | 无条件跳转 | `jmp .done` |
| `je` / `jz` | ZF=1（相等 / 结果为零） | `je .equal` |
| `jne` / `jnz` | ZF=0 | `jne .loop` |
| `jl` `jle` `jg` `jge` | **有符号**小于 / 小于等于 / 大于 / 大于等于 | `jle .keep` |
| `jb` `jbe` `ja` `jae` | **无符号**小于 / 小于等于 / 大于 / 大于等于 | `jbe .keep` |
| `js` / `jns` | SF=1 / SF=0（结果的符号位） | `jns .not_neg` |
| `jc` / `jnc` | CF=1 / CF=0（进位、借位） | `jc .carry` |
| 局部标签 `.foo` | 作用域挂在最近的非局部标签下 | `jl .yes1` |
| 落空（fall-through） | 条件不成立时不跳，继续执行下一条指令 | 见 3.1 |

### 条件转移完整对照表

| 指令 | 含义 | 跳转条件 | 名字来源 |
|---|---|---|---|
| `je` / `jz` | 相等 / 为零 | ZF=1 | equal / zero |
| `jne` / `jnz` | 不等 / 非零 | ZF=0 | not equal |
| `jl` / `jnge` | 有符号 a < b | SF ≠ OF | less |
| `jle` / `jng` | 有符号 a ≤ b | ZF=1 或 SF ≠ OF | less or equal |
| `jg` / `jnle` | 有符号 a > b | ZF=0 且 SF = OF | greater |
| `jge` / `jnl` | 有符号 a ≥ b | SF = OF | greater or equal |
| `jb` / `jnae` / `jc` | 无符号 a < b | CF=1（借位） | below |
| `jbe` / `jna` | 无符号 a ≤ b | CF=1 或 ZF=1 | below or equal |
| `ja` / `jnbe` | 无符号 a > b | CF=0 且 ZF=0 | above |
| `jae` / `jnb` / `jnc` | 无符号 a ≥ b | CF=0 | above or equal |

（表中 a、b 指 `cmp a, b` 里的两个操作数。）

### 为什么 `-1` 用 `ja` 和 `jg` 结果相反

CPU 只有一套标志位，它**不知道**你心里把操作数当有符号还是无符号；「有符号/无符号」是靠
你选的跳转指令来体现的。`-1` 的 64 位补码是全 1：

```text
-1  =  0xffffffffffffffff  =  1111 1111 ... 1111 1111
        有符号视角：-1
        无符号视角：18446744073709551615
```

拿它和 `1` 比较：

```text
有符号：-1 < 1        → jl 成立，jg 不成立
无符号：0xff..ff > 1  → ja 成立，jb 不成立
```

原因在两条指令检查的标志位不同：

* 有符号比较用 **SF 和 OF**。`cmp a, b` 做的是 `a - b`，如果减法溢出（OF=1），结果的符号位
  就不再代表真实的大小关系，所以判定式写成 `SF ≠ OF` 才正确（`jl` 就是查这个）。
* 无符号比较只用 **CF 和 ZF**。减法借位时 CF=1 就表示「不够减」，即 `a < b`（`jb` 查 CF=1），
  `a > b` 则是「没有借位且不相等」（`ja` 查 CF=0 且 ZF=0）。

结论：**处理有符号数据（可能为负的下标、温差、账户余额……）一律用 `jl/jle/jg/jge`；
处理地址、长度、索引这类无符号量用 `jb/jbe/ja/jae`。** 选错是汇编里最常见的逻辑 bug 之一，
而且程序不会崩，只会悄悄走错分支。

## 三、示例源码逐段讲解

### 3.1 cmpjmp.asm —— 八组对照实验

```asm
; ===========================================================================
; cmpjmp.asm —— cmp 与条件转移（conditional jump）
;
; 关键点：同一对操作数，用「有符号」还是「无符号」的跳转指令，结果可能相反。
;
;   cmp a, b   实际做 a - b，但不保存结果，只设置标志位：
;       ZF=1  → a == b
;       CF=1  → 无符号角度 a < b（减法发生了借位）
;       有符号的大小关系由 SF 和 OF 共同决定（相等时还要看 ZF）
;
;   无符号用：jb(below) / jbe / ja(above) / jae
;   有符号用：jl(less)  / jle / jg(greater) / jge
;   相等用  ：je / jne（有符号无符号都一样）
;
; 纯系统调用程序：入口 _start。运行：  make && ./cmpjmp
; ===========================================================================
default rel

section .data
    t1 db "cmp   1, 2     : jl    -> "
    l1 equ $ - t1
    t2 db "cmp  -1, 1     : jl    -> "
    l2 equ $ - t2
    t3 db "cmp  -1, 1     : jg    -> "
    l3 equ $ - t3
    t4 db "cmp  -1, 1     : ja    -> "
    l4 equ $ - t4
    t5 db "cmp  -1, 1     : jb    -> "
    l5 equ $ - t5
    t6 db "cmp   5, 5     : je    -> "
    l6 equ $ - t6
    t7 db "cmp   3, 5     : jge   -> "
    l7 equ $ - t7
    t8 db "test  0, 0     : jz    -> "
    l8 equ $ - t8

    ; 判定结论；末尾直接带换行，省掉一次 io_newline
    s_yes db "taken", 10
    l_yes equ $ - s_yes
    s_no  db "not taken", 10
    l_no  equ $ - s_no

section .text
    global _start
%include "io.inc"

_start:
; ---- 测试 1：cmp 1, 2 → 1-2 借位 CF=1、SF=1，有符号 jl「小于」成立 ----
    lea  rsi, [rel t1]
    mov  rdx, l1
    call io_print
    mov  rax, 1
    mov  rbx, 2
    cmp  rax, rbx
    jl   .yes1
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr1
.yes1:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr1:
    call io_print

; ---- 测试 2：cmp -1, 1 → 有符号看：-1 < 1 成立（SF=1、OF=0 → jl 成立） ----
    lea  rsi, [rel t2]
    mov  rdx, l2
    call io_print
    mov  rax, -1
    mov  rbx, 1
    cmp  rax, rbx
    jl   .yes2
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr2
.yes2:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr2:
    call io_print

; ---- 测试 3：同样的 cmp -1, 1 换成 jg（有符号「大于」）→ 不成立 ----
    lea  rsi, [rel t3]
    mov  rdx, l3
    call io_print
    mov  rax, -1
    mov  rbx, 1
    cmp  rax, rbx
    jg   .yes3
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr3
.yes3:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr3:
    call io_print

; ---- 测试 4：★重点★ 同样的 cmp -1, 1 换成 ja（无符号「大于」）→ 成立！
;           无符号把 -1 看成 0xffffffffffffffff = 18446744073709551615，
;           它当然比 1「大」。ja 的条件是 CF=0 且 ZF=0 ----
    lea  rsi, [rel t4]
    mov  rdx, l4
    call io_print
    mov  rax, -1
    mov  rbx, 1
    cmp  rax, rbx
    ja   .yes4
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr4
.yes4:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr4:
    call io_print

; ---- 测试 5：同样的 cmp -1, 1 换成 jb（无符号「小于」）→ 不成立。
;           这就是为什么处理负数数组、负数下标时必须用 jl/jge ----
    lea  rsi, [rel t5]
    mov  rdx, l5
    call io_print
    mov  rax, -1
    mov  rbx, 1
    cmp  rax, rbx
    jb   .yes5
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr5
.yes5:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr5:
    call io_print

; ---- 测试 6：cmp 5, 5 → ZF=1，je 成立 ----
    lea  rsi, [rel t6]
    mov  rdx, l6
    call io_print
    mov  rax, 5
    mov  rbx, 5
    cmp  rax, rbx
    je   .yes6
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr6
.yes6:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr6:
    call io_print

; ---- 测试 7：cmp 3, 5 → jge（有符号「大于等于」）不成立 ----
    lea  rsi, [rel t7]
    mov  rdx, l7
    call io_print
    mov  rax, 3
    mov  rbx, 5
    cmp  rax, rbx
    jge  .yes7
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr7
.yes7:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr7:
    call io_print

; ---- 测试 8：test rax, rax 是「和 0 比较」的标准写法。test 不写回结果，
;           还会强制 CF=0、OF=0，所以之后只能用 jz/jnz/jl/js 之类看 ZF/SF ----
    lea  rsi, [rel t8]
    mov  rdx, l8
    call io_print
    xor  eax, eax                   ; rax = 0
    test rax, rax
    jz   .yes8
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr8
.yes8:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr8:
    call io_print

; ---- 结束进程 ----
    xor  edi, edi
    call io_exit
```

每个测试都是同一个骨架，以测试 1 为例：

```asm
    mov  rax, 1
    mov  rbx, 2
    cmp  rax, rbx        ; 设置标志位
    jl   .yes1           ; 条件成立 → 跳到 .yes1
    lea  rsi, [rel s_no] ; 条件不成立 → 顺序执行这里（落空）
    mov  rdx, l_no
    jmp  .pr1            ; 必须跳过「成立」分支的打印，否则会打印两次
.yes1:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr1:
    call io_print         ; 两个分支在这里汇合
```

这里有两个新手必踩的点：

1. **不成立时必须走「落空」路径**：`jl` 不跳，CPU 就继续执行下一条指令。所以两条分支的代码
   要按「一个跳走、另一个落空」来排布。
2. **`jmp .pr1` 不能省**：如果没有它，不成立时打印完 `not taken` 会继续往下执行 `.yes1`
   的代码，把 `taken` 也打印一遍（即所谓「贯穿」）。

八组实验的结论一览：

| # | 指令 | 跳转指令 | 结果 | 关键原因 |
|---|---|---|---|---|
| 1 | `cmp 1, 2` | `jl` | taken | 1 < 2，有符号无符号都成立 |
| 2 | `cmp -1, 1` | `jl` | taken | 有符号：-1 < 1 |
| 3 | `cmp -1, 1` | `jg` | not taken | 有符号：-1 不大于 1 |
| 4 | `cmp -1, 1` | `ja` | **taken** | 无符号：0xffffffffffffffff > 1 |
| 5 | `cmp -1, 1` | `jb` | not taken | 无符号：0xffffffffffffffff 不小于 1 |
| 6 | `cmp 5, 5` | `je` | taken | ZF=1 |
| 7 | `cmp 3, 5` | `jge` | not taken | 有符号：3 不 ≥ 5 |
| 8 | `xor eax,eax` + `test rax, rax` | `jz` | taken | `test` 结果为 0 → ZF=1 |

第 4、5 组就是本课的重点结论：**同一对操作数，换个跳转指令结论就反过来。**

第 8 组演示了 `test rax, rax` —— 这是「判断寄存器是不是 0」的标准写法，
比 `cmp rax, 0` 更短。第 04 课讲过 `test` 会强制 CF=OF=0，所以 `test` 之后
**不能**用 `jb/jae/ja` 判断无符号大小（`jb` 永远不成立）。

### 3.2 minmax.asm —— 求最大值、最小值

```asm
; ===========================================================================
; minmax.asm —— 用条件跳转求最大值/最小值
;
;   第一部分：两个数的最大值。同样的两个数分别用「有符号」和「无符号」比较，
;             结果完全不同 —— 这就是 jg 和 ja 的区别。
;   第二部分：遍历 .data 里的 qword 数组，一边打印一边找最大/最小。
;
; 循环的写法下一课（第 06 课）细讲，这里先看懂「比较 → 条件跳转 → 更新」
; 这个三步套路即可。
;
; 纯系统调用程序：入口 _start。运行： make && ./minmax
; ===========================================================================
default rel

section .data
    arr     dq 17, -5, 42, -100, 0, 33, -7
    arr_len equ ($ - arr) / 8       ; 元素个数 = 总字节数 / 每个 qword 8 字节

    t_smax  db "max_signed(-7, 3)   = "
    l_smax  equ $ - t_smax
    t_umax  db "max_unsigned(-7, 3) = "
    l_umax  equ $ - t_umax
    t_udec  db "  (unsigned: "
    l_udec  equ $ - t_udec
    t_udone db ")"
    l_udone equ $ - t_udone

    t_arr   db "array               = ["
    l_arr   equ $ - t_arr
    t_arr_e db "]", 10                 ; ']' 加换行（.data 里还没 include io.inc，
    l_arr_e equ $ - t_arr_e           ;  所以换行写数字 10，不能写 LF 符号）

    t_max   db "max                 = "
    l_max   equ $ - t_max
    t_min   db "min                 = "
    l_min   equ $ - t_min

    s_comma db ", "
    l_comma equ $ - s_comma

section .text
    global _start
%include "io.inc"

_start:
; ---------------------------------------------------------------------------
; 1) 有符号比较：求 max(-7, 3)
;    套路：先假设第一个数是最大值，再拿第二个数跟它比，更大就替换
;    jle = 有符号「小于等于」：3 <= max 就不用替换
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_smax]
    mov  rdx, l_smax
    call io_print

    mov  rax, -7
    mov  rbx, 3
    mov  r12, rax                   ; 假设 max = -7
    cmp  rbx, r12                   ; 3 和 -7 比
    jle  .s_keep                    ; ★ 有符号比较：3 <= -7 不成立，所以不跳
    mov  r12, rbx                   ; max = 3
.s_keep:
    mov  rdi, r12
    call io_print_int
    call io_newline

; ---------------------------------------------------------------------------
; 2) 无符号比较：同样两个数，-7 被当成 0xfffffffffffffff9
;    jbe = 无符号「小于等于」：3 <= 0xff..f9 成立 → 跳过去，不替换
;    结果 max 是那个「巨大的负数」，打印出来是 0xfffffffffffffff9
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_umax]
    mov  rdx, l_umax
    call io_print

    mov  rax, -7
    mov  rbx, 3
    mov  r12, rax                   ; 假设 max = 0xfffffffffffffff9
    cmp  rbx, r12
    jbe  .u_keep                    ; ★ 无符号比较：3 <= 0xff..f9 成立
    mov  r12, rbx
.u_keep:
    mov  rdi, r12
    call io_print_hex               ; 0xfffffffffffffff9
    lea  rsi, [rel t_udec]
    mov  rdx, l_udec
    call io_print
    mov  rdi, r12
    call io_print_uint              ; 18446744073709551609
    lea  rsi, [rel t_udone]
    mov  rdx, l_udone
    call io_print
    call io_newline

; ---------------------------------------------------------------------------
; 3) 数组：一边打印元素，一边找最大值和最小值
;    寄存器分工（都不能用 rcx/rdx/rax，因为 io 例程会破坏它们）：
;      rbx = 数组首地址（lea rbx, [rel arr]）
;      rbp = 下标 i
;      r12 = 当前最大值    r13 = 当前最小值
;      r14 = 当前元素 —— 元素先放进 r14，再调用 io_print_int，
;            否则打印本身就把 rax 里的元素值冲掉了
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_arr]
    mov  rdx, l_arr
    call io_print

    lea  rbx, [rel arr]             ; rbx → arr[0]
    mov  r12, [rbx]                 ; max 先取 arr[0]
    mov  r13, [rbx]                 ; min 先取 arr[0]
    xor  rbp, rbp                   ; i = 0

.loop:
    cmp  rbp, arr_len
    jge  .loop_done                 ; i >= arr_len 就结束

    mov  r14, [rbx + rbp*8]         ; r14 = arr[i]（下标寻址：基址 + 下标*8）

    cmp  r14, r12
    jle  .no_max                    ; 有符号比较：arr[i] <= max 就不更新
    mov  r12, r14
.no_max:
    cmp  r14, r13
    jge  .no_min                    ; 有符号比较：arr[i] >= min 就不更新
    mov  r13, r14
.no_min:

    mov  rdi, r14                   ; 打印这个元素
    call io_print_int
    inc  rbp                        ; i++
    cmp  rbp, arr_len
    jge  .loop_done                 ; 最后一个元素后面不加逗号
    lea  rsi, [rel s_comma]
    mov  rdx, l_comma
    call io_print
    jmp  .loop

.loop_done:
    lea  rsi, [rel t_arr_e]
    mov  rdx, l_arr_e
    call io_print                   ; 打印 "]" 和换行

; ---------------------------------------------------------------------------
; 4) 打印最大值和最小值
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_max]
    mov  rdx, l_max
    call io_print
    mov  rdi, r12
    call io_print_int
    call io_newline

    lea  rsi, [rel t_min]
    mov  rdx, l_min
    call io_print
    mov  rdi, r13
    call io_print_int
    call io_newline

; ---------------------------------------------------------------------------
; 结束进程
; ---------------------------------------------------------------------------
    xor  edi, edi
    call io_exit
```

**第一部分：两个数的最大值，两种解释。**
套路是「先假设其中一个就是答案，再拿另一个来挑战它」：

```asm
    mov  r12, rax        ; 假设 max = -7
    cmp  rbx, r12        ; 3 和 -7 比
    jle  .s_keep         ; 有符号：3 <= -7 不成立 → 不跳，说明该换
    mov  r12, rbx        ; max = 3
.s_keep:
```

同样的两个数换成 `jbe`（无符号 ≤）后，`3 <= 0xfffffffffffffff9` 成立，于是保持 `-7` 不变，
打印出来是 `0xfffffffffffffff9`（十进制 18446744073709551609）。
同一份数据、同一个比较，只换了一个助记符，答案就从 `3` 变成「巨大的正数」。

**第二部分：数组遍历。**
先看数组是怎么定义的：

```asm
    arr     dq 17, -5, 42, -100, 0, 33, -7
    arr_len equ ($ - arr) / 8       ; 元素个数 = 总字节数 / 每个 qword 8 字节
```

`$` 表示「当前位置」，`$ - arr` 就是数组占用的字节数，再除以每个元素 8 字节，得到元素个数。
这个算式在汇编期就求出来了，不占任何运行时间。

遍历的核心是这一行寻址：

```asm
    mov  r14, [rbx + rbp*8]     ; rbx = 数组首地址，rbp = 下标
```

x86-64 的寻址格式是 `[基址 + 变址*比例 + 偏移]`，比例只能是 1、2、4、8，
正好用来访问不同宽度的数组（`dq` 用 8，`dd` 用 4，`dw` 用 2，`db` 用 1）。
**注意下标是「元素下标」而不是字节偏移** —— 乘 8 这一步由 CPU 的地址生成单元免费完成。

循环体的三件事：更新最大值、更新最小值、打印当前元素。这里有一个值得记住的细节：

```asm
    mov  r14, [rbx + rbp*8]     ; 元素先存进 r14
    ...
    mov  rdi, r14
    call io_print_int           ; 打印会破坏 rax/rcx/rdx
```

如果直接把元素放在 `rax` 里去打印，打印完 `rax` 里的元素值就没了。**循环里所有要跨过
`io.inc` 调用继续用的值，都要放进 `rbx/rbp/r12-r15`**：这几个寄存器是「被调用者保存」的，
`io.inc` 的例程保证不动它们（第 06 课会专门讲这条规则的由来）。

数组结果：`max = 42`、`min = -100`。

## 四、编译与运行

```bash
cd lesson05
make
./cmpjmp
./minmax
make test
```

`./cmpjmp` 的真实输出：

```text
cmp   1, 2     : jl    -> taken
cmp  -1, 1     : jl    -> taken
cmp  -1, 1     : jg    -> not taken
cmp  -1, 1     : ja    -> taken
cmp  -1, 1     : jb    -> not taken
cmp   5, 5     : je    -> taken
cmp   3, 5     : jge   -> not taken
test  0, 0     : jz    -> taken
```

`./minmax` 的真实输出：

```text
max_signed(-7, 3)   = 3
max_unsigned(-7, 3) = 0xfffffffffffffff9  (unsigned: 18446744073709551609)
array               = [17, -5, 42, -100, 0, 33, -7]
max                 = 42
min                 = -100
```

## 五、动手练习

1. 把 `cmpjmp.asm` 里测试 2～5 的 `-1` 改成 `-100`，先预测 `jl/jg/ja/jb` 的成立情况，再运行验证。
2. 新增一个测试：`cmp -1, -2`，分别用 `jl` 和 `jb`，解释为什么两个结果不一样。
3. 把 `minmax.asm` 第一部分的有符号比较改写成「用 `jg` 判断谁更大」的写法（和现在的 `jle`
   写法逻辑等价，但方向相反），确认输出不变。
4. 在 `minmax.asm` 的数组遍历里，额外求出最大值所在的**下标**（最大值有多个时取第一个），
   并打印出来。
5. 判断一个年份是不是闰年：能被 4 整除且不能被 100 整除，或者能被 400 整除。
   用 `div`/`idiv` 取余数 + `test`/`jz` 组合实现，闰年打印 `leap`。

练习 4 提示：再去申请一个寄存器当下标记录（`r15` 是空闲的），比较出「更大」之后再更新它；
注意 `io` 调用会破坏 `rax/rcx/rdx`，所以下标要放在 `r15` 这样的寄存器里。

练习 5 提示：`div` 之前记得 `xor rdx, rdx`；判余数是否为 0 可以直接 `test rdx, rdx` + `jz`，
不需要再 `cmp rdx, 0`。多个条件组合时，用「不满足就跳到下一个检查」的链式结构最清晰。

## 六、常见坑

1. **有符号数据用无符号跳转**：负数一旦被当成大整数，`jb/ja` 的结论就全反了。
   看到数组、余额、温度这类可能有负的值，就用 `jl/jg/jle/jge`。
2. **`cmp a, b` 的方向**：它算 `a - b`，所以「a 小于 b」要写 `jl`（less 指 a less than b），
   把两个操作数写反是经典错误。
3. **忘了 `jmp` 造成贯穿**：条件成立分支执行完必须用 `jmp` 跳过不成立分支的代码，
   否则两个分支都会执行。本课每个测试都用 `.pr1` 这样的汇合点解决。
4. **`test` 之后用 `jb/ja`**：`test` 强制 CF=OF=0，`jb`（CF=1）永远不成立；`ja`（CF=0 且 ZF=0）
   在非零时永远成立 —— 这不是「比较大小」，只是误用。
5. **边界检查建议用无符号的 `jb/jae`**：`cmp rbp, arr_len` + `jae .out_of_range` 这种写法会把
   「下标为负」的 bug 一起挡在门外（-1 在无符号视角下是天文数字，必然 ≥ 长度）；
   如果误用有符号的 `jge`，-1 会被认为「小于长度」而放行，程序就去访问数组前面的内存了。
6. **局部标签的作用域**：以 `.` 开头的标签归属最近的非局部标签。`_start` 下面的 `.yes1`
   和别的非局部标签下面的 `.yes1` 是两个不同的符号，所以可以放心重名，但也别跨段乱引用。
7. **`jmp` 不能跳进另一个函数的中间**（第 07 课讲函数后尤其要注意），
   跳转只改变 `rip`，不会帮你布置栈帧。

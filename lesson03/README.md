# 第 03 课：数据定义、db/dw/dd/dq、字符串与长度

## 一、本课目标

- 会用 `db`/`dw`/`dd`/`dq` 按 1/2/4/8 字节定义数据，并说清每个宽度能装多大的数。
- 会用 `equ` 定义汇编期常量，并用 `$ - 标签` 自动算出数据长度（知道结尾的 0 要额外减掉）。
- 会用 `times` 批量重复数据，理解字符串在内存里就是"一串字节 + 一个结尾 0"。
- 看懂小端序（little-endian）：为什么 `dd 0x89abcdef` 在内存里是 `ef cd ab 89`。
- 自己写一个循环数出字符串长度，不依赖任何库函数。

## 二、新概念 / 新指令

### 2.1 四个"d 指令"的宽度

| 指令 | 全称 | 宽度 | 能表示的整数范围（无符号 / 有符号） |
|---|---|---|---|
| `db` | Define Byte | 1 字节 | 0 ~ 255 / -128 ~ 127 |
| `dw` | Define **Word** | 2 字节 | 0 ~ 65535 / -32768 ~ 32767 |
| `dd` | Define **Double**word | 4 字节 | 0 ~ 4294967295 / -2147483648 ~ 2147483647 |
| `dq` | Define **Quad**word | 8 字节 | 0 ~ 18446744073709551615 / 约 ±9.2×10¹⁸ |

⚠️ x86 里的 `word` 是 **16 位（2 字节）**，不是 32 位。`dword` 才是 32 位。这个命名来自 16 位时代，改不了了。

### 2.2 本课新指令与新概念

| 概念 / 指令 | 一句话说明 | 小例子 |
|---|---|---|
| `db 0x41, 'C', 10` | 一个字节一个字节地摆数据；数字、字符、字符串可以混写 | `db 0x41, 0x42, 'C', 10` |
| `db "abc", 0` | 字符串**不会**自动补结尾 0，要自己写 | `str1 db "abc", 0` |
| `times N 数据` | 把**整个**数据语句重复 N 次 | `stars times 8 db 0x2a` |
| `equ` | 汇编期常量，不占内存，用一次替换一次 | `Q1_LEN equ q1_end - q1` |
| `$` | 当前位置的地址（汇编期求值） | `str1_len equ $ - str1 - 1` |
| `标签:` | 标签就是"当前位置"的名字，两个标签相减得到字节数 | `q1_end:` |
| `byte [rel x]` | 把内存操作数当 1 字节 | `movzx rdi, byte [rel b1]` |
| `word [rel x]` | 当 2 字节 | `movzx rdi, word [rel w1]` |
| `dword [rel x]` | 当 4 字节 | `movsxd rdi, dword [rel d1]` |
| `qword [rel x]` | 当 8 字节 | `mov qword [rel b], 1` |
| `movsxd rdi, dword [rel d1]` | 把 4 字节**按有符号**扩展到 64 位 | `movsxd rdi, dword [rel d1]` |
| `cmp byte [rdi], 0` | 比较内存里的一个字节和 0（只改标志位，不改数据） | `cmp byte [rdi], 0` |
| `je 标签` | 相等就跳过去（`cmp` 之后用） | `je .done` |
| `jmp 标签` | 无条件跳转 | `jmp .loop` |
| `inc rax` | 加 1 | `inc rax` |
| 小端序 | 多字节整数在内存里**低位字节在前** | `dd 0x89abcdef` → `ef cd ab 89` |

> `cmp`/`je`/`jmp` 这些跳转指令第 05、06 课会专门讲。本课 `strlen.asm` 先用一下，属于"提前见个面"，这里只解释它在这段代码里的作用。

## 三、示例源码逐段讲解

### 3.1 data.asm —— 把各种数据定义摆一遍

```asm
; ===========================================================================
; data.asm —— 第 03 课：数据定义 db / dw / dd / dq / equ / times
;
;   db = Define Byte      （1 字节）
;   dw = Define Word      （2 字节，注意 x86 里 "word" 是 2 字节不是 4 字节）
;   dd = Define Doubleword（4 字节）
;   dq = Define Quadword  （8 字节）
;   equ  = 汇编期常量，不占内存
;   times = 把同一份数据重复 N 次
;
; 构建/运行：
;   make && ./data
; ===========================================================================

default rel

section .data
    banner      db  "=== 第 03 课：数据定义 db/dw/dd/dq/equ/times ===", 10
    banner_len  equ $ - banner

    ; ---- db：一个字节一个字节地摆 ----
    b1      db  0x41, 0x42, 'C', 10     ; 'A' 'B' 'C' 换行（0x41 == 65 == 'A'）
    b1_len  equ $ - b1                  ; = 4（含那个换行）

    ; ---- dw：2 字节 ----
    w1      dw  0x1234

    ; ---- dd：4 字节 ----
    d1      dd  0x89abcdef

    ; ---- dq：8 字节 ----
    q1      dq  0x1122334455667788
q1_end:                                 ; 紧跟在 q1 后面，用来算大小
    Q1_LEN  equ q1_end - q1             ; = 8

    ; ---- 字符串 + 结尾 0，长度用 equ 算出来 ----
    str1        db  "abc", 0
    str1_len    equ $ - str1 - 1        ; = 3（不减 1 会把结尾的 0 也算进去）

    ; ---- times：重复 ----
    stars   times 8 db 0x2a             ; 8 个 '*'（0x2a == 42 == '*'）
    pair    times 3 db "ab"             ; "ab" 重复 3 次 = "ababab"（6 字节）

    ; ---- 下面都是输出用的小标签 ----
    t_db    db  "[db   ] b1 的 4 个字节原样输出   : "
    t_db_len equ $ - t_db
    t_db0   db  "[db   ] b1[0] 当数字看           = "
    t_db0_len equ $ - t_db0
    t_dw    db  "[dw   ] w1（2 字节）             = "
    t_dw_len equ $ - t_dw
    t_dd    db  "[dd   ] d1（4 字节，mov edi 读） = "
    t_dd_len equ $ - t_dd
    t_dd2   db  "[dd   ] d1 当有符号 32 位看      = "
    t_dd2_len equ $ - t_dd2
    t_dq    db  "[dq   ] q1（8 字节）             = "
    t_dq_len equ $ - t_dq
    t_equ   db  "[equ  ] Q1_LEN = q1_end - q1     = "
    t_equ_len equ $ - t_equ
    t_str   db  "[str  ] str1 的内容              = "
    t_str_len equ $ - t_str
    t_str2  db  "  长度 = "
    t_str2_len equ $ - t_str2
    t_tm1   db  "[times] stars = 8 个 0x2a        = "
    t_tm1_len equ $ - t_tm1
    t_tm2   db  '[times] pair   = 3 组 "ab"       = '  ; NASM 没有 "" 转义，改用单引号
    t_tm2_len equ $ - t_tm2

section .text
    global _start
    %include "io.inc"

_start:
    lea     rsi, [rel banner]
    mov     rdx, banner_len
    call    io_print

    ; ---------------- db：原样输出 4 个字节 ----------------
    lea     rsi, [rel t_db]
    mov     rdx, t_db_len
    call    io_print
    lea     rsi, [rel b1]
    mov     rdx, b1_len
    call    io_print                    ; 输出 "ABC" 加上 b1 里自带的换行

    ; db 的字节也能当数字用
    lea     rsi, [rel t_db0]
    mov     rdx, t_db0_len
    call    io_print
    movzx   rdi, byte [rel b1]          ; 只取 1 个字节，零扩展成 64 位
    call    io_print_int                ; 65
    call    io_newline

    ; ---------------- dw ----------------
    lea     rsi, [rel t_dw]
    mov     rdx, t_dw_len
    call    io_print
    movzx   rdi, word [rel w1]          ; 取 2 个字节
    call    io_print_hex                ; 0x1234
    call    io_newline

    ; ---------------- dd ----------------
    lea     rsi, [rel t_dd]
    mov     rdx, t_dd_len
    call    io_print
    mov     edi, [rel d1]               ; 读 4 字节到 edi，高 32 位自动补 0
    call    io_print_hex                ; 0x89abcdef
    call    io_newline

    ; 同样 4 字节，按"有符号"扩展到 64 位就是另一个数
    lea     rsi, [rel t_dd2]
    mov     rdx, t_dd2_len
    call    io_print
    movsxd  rdi, dword [rel d1]         ; 符号扩展
    call    io_print_int                ; -1985229329
    call    io_newline

    ; ---------------- dq ----------------
    lea     rsi, [rel t_dq]
    mov     rdx, t_dq_len
    call    io_print
    mov     rdi, [rel q1]               ; 读 8 字节
    call    io_print_hex                ; 0x1122334455667788
    call    io_newline

    ; ---------------- equ：汇编期常量，不占内存 ----------------
    lea     rsi, [rel t_equ]
    mov     rdx, t_equ_len
    call    io_print
    mov     rdi, Q1_LEN                 ; 汇编时就被替换成 8
    call    io_print_int                ; 8
    call    io_newline

    ; ---------------- 字符串与它的长度 ----------------
    lea     rsi, [rel t_str]
    mov     rdx, t_str_len
    call    io_print
    lea     rsi, [rel str1]
    mov     rdx, str1_len
    call    io_print                    ; abc
    lea     rsi, [rel t_str2]
    mov     rdx, t_str2_len
    call    io_print
    mov     rdi, str1_len
    call    io_print_int                ; 3
    call    io_newline

    ; ---------------- times ----------------
    lea     rsi, [rel t_tm1]
    mov     rdx, t_tm1_len
    call    io_print
    lea     rsi, [rel stars]
    mov     edx, 8
    call    io_print                    ; ********
    call    io_newline

    lea     rsi, [rel t_tm2]
    mov     rdx, t_tm2_len
    call    io_print
    lea     rsi, [rel pair]
    mov     edx, 6
    call    io_print                    ; ababab
    call    io_newline

    xor     edi, edi
    call    io_exit
```
**`db`：逐字节摆放**

```asm
    b1      db  0x41, 0x42, 'C', 10     ; 'A' 'B' 'C' 换行（0x41 == 65 == 'A'）
    b1_len  equ $ - b1                  ; = 4（含那个换行）
```

`db` 后面可以跟一串用逗号分开的项。`0x41` 就是十进制 65，也就是字符 `'A'`——**在汇编里数字和字符没有本质区别**，都是一个字节。`'C'` 和 `0x43` 完全等价。

`b1_len equ $ - b1` 在这里等于 4（`41 42 43 0a` 四个字节）。因为这段数据自带换行，程序里直接 `io_print` 这 4 个字节就会输出 `ABC` 并换行，**不需要**再调用 `io_newline`。

**`dw` / `dd` / `dq`**

```asm
    w1      dw  0x1234
    d1      dd  0x89abcdef
    q1      dq  0x1122334455667788
q1_end:                                 ; 紧跟在 q1 后面，用来算大小
    Q1_LEN  equ q1_end - q1             ; = 8
```

一个数占几个字节由指令决定。`q1_end:` 这个标签什么数据都不占，它的值就是"紧跟在 `q1` 后面"这个地址，所以 `q1_end - q1` 正好是 `q1` 的字节数 8。这是汇编里算"某个东西占多大"的标准手法。

**字符串与长度**

```asm
    str1        db  "abc", 0
    str1_len    equ $ - str1 - 1        ; = 3（不减 1 会把结尾的 0 也算进去）
```

C 语言的字符串以 `'\0'`（一个 0 字节）结尾，这是个**约定**，不是语言特性。汇编里你想按这个约定走，就得自己补 `, 0`。于是"有效长度"就变成 `总数 - 1`。如果写成 `equ $ - str1` 会得到 4，打印出来末尾会多一个不可见字节（NUL），在终端上看不出差别，但比较字符串时就会出错。

**`times`：重复**

```asm
    stars   times 8 db 0x2a             ; 8 个 '*'（0x2a == 42 == '*'）
    pair    times 3 db "ab"             ; "ab" 重复 3 次 = "ababab"（6 字节）
```

`times N 语句` 把**整个数据语句**重复 N 次。注意 `times 3 db "ab"` 重复的是 `db "ab"` 这一整条，所以得到 6 个字节 `61 62 61 62 61 62`，而不是"ab 三遍里的第一遍"之类。`times` 后面也可以跟指令（比如 `times 4 nop`），第 12 课会再遇到。

**程序里读取这些数据**

```asm
    movzx   rdi, byte [rel b1]          ; 只取 1 个字节，零扩展成 64 位
    call    io_print_int                ; 65
    ...
    movzx   rdi, word [rel w1]          ; 取 2 个字节
    call    io_print_hex                ; 0x1234
    ...
    mov     edi, [rel d1]               ; 读 4 字节到 edi，高 32 位自动补 0
    call    io_print_hex                ; 0x89abcdef
    ...
    movsxd  rdi, dword [rel d1]         ; 符号扩展
    call    io_print_int                ; -1985229329
    ...
    mov     rdi, [rel q1]               ; 读 8 字节
    call    io_print_hex                ; 0x1122334455667788
```

这四段放在一起看，正好说明"宽度"有多重要：

- `movzx rdi, byte [rel b1]`：取 1 字节 `0x41`，**零扩展**成 `0x0000000000000041`，打印 65。
- `movzx rdi, word [rel w1]`：取 2 字节 `0x1234`。
- `mov edi, [rel d1]`：读 4 字节进 `edi`。因为是写 32 位寄存器，`rdi` 高 32 位自动清零，于是得到 `0x0000000089abcdef`，打印 `0x89abcdef`。
- `movsxd rdi, dword [rel d1]`：同样读 4 字节，但按**有符号**扩展到 64 位：最高位是 1，所以填的全是 1，得到 `0xffffffff89abcdef` = **-1985229329**。

同样 4 个字节，一个被解释成 2309737967，一个被解释成 -1985229329。这就是"位模式 + 解释方式"的第二次登场（第 02 课讲过 `io_print_int` 和 `io_print_uint` 的区别）。

**`equ` 不占内存**

```asm
    mov     rdi, Q1_LEN                 ; 汇编时就被替换成 8
```

`equ` 定义的东西叫"汇编期常量"，它**不是内存里的数据**，只是在汇编阶段做文本替换。所以 `mov rdi, Q1_LEN` 编译出来就是 `mov rdi, 8`。这也意味着 `Q1_LEN` 不能取地址、不能 `lea`。

**输出里的一个坑（真实踩过）**

```asm
    t_tm2   db  '[times] pair   = 3 组 "ab"       = '  ; NASM 没有 "" 转义，改用单引号
```

NASM 的字符串**没有** `""` 这种转义写法。`db "3 组 ""ab"" = "` 会报：

```text
error: comma expected after operand, got `ab'
```

要在字符串里放双引号，就用单引号把整个字符串包起来（单引号字符串里双引号是普通字符，反之亦然）。

### 3.2 strlen.asm —— 自己写循环数长度

```asm
; ===========================================================================
; strlen.asm —— 第 03 课：自己写循环数字符串长度（完全不碰 libc）
;
; C 里一句 strlen(s) 背后就是一个循环：从字符串开头一个字节一个字节往后看，
; 遇到结尾的 0 就停下，走过的字节数就是长度。这里把它写成汇编。
;
; 输出格式：字符串 [原文] 长度 = N
;
; 构建/运行：
;   make && ./strlen
; ===========================================================================

default rel

section .data
    banner      db  "=== 第 03 课：自己数长度 my_strlen ===", 10
    banner_len  equ $ - banner

    p_pre       db  "字符串 ["
    p_pre_len   equ $ - p_pre
    p_mid       db  "] 长度 = "
    p_mid_len   equ $ - p_mid

    ; 四个测试样本：普通串、空串、带连字符的串、含中文的串
    s1      db  "Hello", 0
    s2      db  0                       ; 空字符串 == 只有一个结尾 0
    s3      db  "x86-64 assembly", 0
    s4      db  "长度是按字节数的，不是按字符", 0

section .text
    global _start
    %include "io.inc"

_start:
    lea     rsi, [rel banner]
    mov     rdx, banner_len
    call    io_print

    lea     rdi, [rel s1]               ; 参数：字符串地址
    call    show_len

    lea     rdi, [rel s2]
    call    show_len

    lea     rdi, [rel s3]
    call    show_len

    lea     rdi, [rel s4]
    call    show_len

    xor     edi, edi
    call    io_exit

; ---------------------------------------------------------------------------
; show_len —— 打印一行「字符串 [原文] 长度 = N」
; 入参：rdi = 以 0 结尾的字符串地址
; ---------------------------------------------------------------------------
show_len:
    push    r12                         ; io.inc 保证 rbx/rbp/r12-r15 不被破坏，
    push    r13                         ; 所以用它俩把数据带过若干次 io_* 调用
    mov     r13, rdi                    ; r13 = 字符串首地址

    call    my_strlen                   ; 返回长度在 rax
    mov     r12, rax                    ; r12 = 长度

    lea     rsi, [rel p_pre]
    mov     rdx, p_pre_len
    call    io_print                    ; 「字符串 [」

    mov     rsi, r13                    ; 原文首地址
    mov     rdx, r12                    ; 原文长度（正是刚刚数出来的）
    call    io_print                    ; 输出原文

    lea     rsi, [rel p_mid]
    mov     rdx, p_mid_len
    call    io_print                    ; 「] 长度 = 」

    mov     rdi, r12
    call    io_print_int                ; 输出长度

    call    io_newline

    pop     r13
    pop     r12
    ret

; ---------------------------------------------------------------------------
; my_strlen —— 数到第一个 0 为止，返回"不含结尾 0"的长度
; 入参：rdi = 字符串地址        返回：rax = 长度
; 只使用 rax / rdi，不碰其它寄存器
; ---------------------------------------------------------------------------
my_strlen:
    xor     eax, eax                    ; rax = 0，长度计数器（xor 同时清掉高 32 位）
.loop:
    cmp     byte [rdi], 0               ; 看 rdi 指向的那个字节是不是 0
    je      .done                       ; 是 0 → 数完了
    inc     rax                         ; 长度 + 1
    inc     rdi                         ; 指针往后挪一个字节
    jmp     .loop                       ; 回到循环开头继续看
.done:
    ret                                 ; 长度在 rax 里返回
```
C 里一句 `strlen(s)` 背后就是一个循环：从开头一个字节一个字节往后看，遇到结尾的 0 就停下，走过的字节数就是长度。这里把它写出来。

**主程序：对四个样本逐个调用**

```asm
    lea     rdi, [rel s1]               ; 参数：字符串地址
    call    show_len
    ...
```

`rdi` 是参数寄存器（和 C 调用约定一致）。四个样本特意选了四种情况：普通串、空串、带连字符的串、含中文的串。

**`show_len`：打印「字符串 [原文] 长度 = N」**

```asm
show_len:
    push    r12                         ; io.inc 保证 rbx/rbp/r12-r15 不被破坏，
    push    r13                         ; 所以用它俩把数据带过若干次 io_* 调用
    mov     r13, rdi                    ; r13 = 字符串首地址

    call    my_strlen                   ; 返回长度在 rax
    mov     r12, rax                    ; r12 = 长度
```

这里的关键是**把数据搬进"安全的"寄存器**。原因：

- `rdi` 在 `call my_strlen` 之后已经被改掉了（`my_strlen` 会一路 `inc rdi`）；
- `rax` 里虽然有长度，但接下来每一次 `call io_print*` 都会改写 `rax`（`io.inc` 明确只保证 `rbx/rbp/r12-r15` 不变）。

所以：指针进 `r13`、长度进 `r12`，之后就能放心地连续调用输出函数。`push r12` / `push r13` / 最后 `pop` 是为了**本函数自己不破坏别人的 r12/r13**——这是"被调用者保存"约定的实践（第 07 课会系统讲）。

输出顺序也值得注意：先打印长度**恰好用得上我们刚数出来的长度**，一次性把原文打出来：

```asm
    mov     rsi, r13                    ; 原文首地址
    mov     rdx, r12                    ; 原文长度（正是刚刚数出来的）
    call    io_print                    ; 输出原文
```

**`my_strlen`：循环本体**

```asm
my_strlen:
    xor     eax, eax                    ; rax = 0，长度计数器（xor 同时清掉高 32 位）
.loop:
    cmp     byte [rdi], 0               ; 看 rdi 指向的那个字节是不是 0
    je      .done                       ; 是 0 → 数完了
    inc     rax                         ; 长度 + 1
    inc     rdi                         ; 指针往后挪一个字节
    jmp     .loop                       ; 回到循环开头继续看
.done:
    ret                                 ; 长度在 rax 里返回
```

逐行说：

- `xor eax, eax`：把计数器清零。用 32 位写法是因为它顺带清零高 32 位（第 02 课），等价于 `mov rax, 0` 但更短。
- `cmp byte [rdi], 0`：把 `rdi` 指向的**那个字节**和 0 比较。必须写尺寸 `byte`，因为内存操作数没有别的线索告诉汇编器要读几个字节。`cmp` 只设置标志位，不改内存内容。
- `je .done`：上一条比较"相等"就跳走。`.done` 这种以点开头的标签叫**局部标签**，它的作用域是上一个非点开头的标签（这里是 `my_strlen`），所以别的函数里也可以有 `.loop`、`.done`，不会撞名。
- `inc rax` / `inc rdi`：长度加一、指针后移。
- `jmp .loop`：无条件回到循环开头。
- `ret`：返回，结果放在 `rax`。

**空字符串为什么也对**：`s2 db 0` 的第一个字节就是 0，`cmp` 立刻就相等，于是 `rax` 保持 0，长度为 0。程序里随后用 `io_print` 打印长度为 0 的字符串，`write(fd, buf, 0)` 写 0 字节——不报错，也什么都不输出，所以输出是 `字符串 [] 长度 = 0`。

**为什么中文那行是 42**：`my_strlen` 数的是**字节数**，不是字符数。UTF-8 里一个常用汉字占 3 字节：

```text
长度是按字节数的，不是按字符
└──────── 8 个汉字 ────────┘└，┘└─ 5 个汉字 ─┘
   8 × 3 = 24 字节        +3   + 5 × 3 = 15 字节   ⇒ 共 42 字节
```

所以 `strlen`（包括 C 的 `strlen`）对 UTF-8 中文返回的永远是字节数。要数字符得用"数非续接字节"之类的算法，那是后面的话题。

## 四、编译与运行

```bash
cd lesson03
make
./data
./strlen
```

`data` 的真实输出（共 11 行）：

```text
=== 第 03 课：数据定义 db/dw/dd/dq/equ/times ===
[db   ] b1 的 4 个字节原样输出   : ABC
[db   ] b1[0] 当数字看           = 65
[dw   ] w1（2 字节）             = 0x1234
[dd   ] d1（4 字节，mov edi 读） = 0x89abcdef
[dd   ] d1 当有符号 32 位看      = -1985229329
[dq   ] q1（8 字节）             = 0x1122334455667788
[equ  ] Q1_LEN = q1_end - q1     = 8
[str  ] str1 的内容              = abc  长度 = 3
[times] stars = 8 个 0x2a        = ********
[times] pair   = 3 组 "ab"       = ababab
```

`strlen` 的真实输出（共 5 行）：

```text
=== 第 03 课：自己数长度 my_strlen ===
字符串 [Hello] 长度 = 5
字符串 [] 长度 = 0
字符串 [x86-64 assembly] 长度 = 15
字符串 [长度是按字节数的，不是按字符] 长度 = 42
```

本课的 `test.sh` 对两个程序都做"先比行数、再要求每一行原样出现"的整段比对，等价于逐字节一致，所以输出里连空格对齐都是被检查的。

### 4.1 看符号地址

```bash
nm lesson03/data | grep -E ' (b1|w1|d1|q1|str1|stars|pair)$'
```

已实测结果：

```text
0000000000402038 d b1
000000000040203c d w1
000000000040203e d d1
0000000000402042 d q1
000000000040204a d str1
000000000040204e d stars
0000000000402056 d pair
```

小写 `d` 表示这些符号都在 `.data` 段。地址也可以反推出每个数据占几字节：`b1` 在 `0x402038`、`w1` 在 `0x40203c`，差 4 —— 正是 `b1` 的 4 个字节；`w1`(0x40203c) → `d1`(0x40203e) 差 2，正是 `dw` 的 2 字节；`d1`(0x40203e) → `q1`(0x402042) 差 4，正是 `dd`。**宽度不是概念，是内存里真实的间隔。**

### 4.2 看原始字节，理解小端序

```bash
objdump -s -j .data lesson03/data
```

`.data` 里前面一大段是输出用的标签字符串，真正有意思的是这几行（实测输出）：

```text
 402030 6d657320 3d3d3d0a 4142430a 3412efcd  mes ===.ABC.4...
 402040 ab898877 66554433 22116162 63002a2a  ...wfUD3".abc.**
 402050 2a2a2a2a 2a2a6162 61626162 5b646220  ******ababab[db 
```

把字节和我们的定义对起来：

| 标签 | 地址 | 内存里的原始字节 | 对应的值 / 内容 |
|---|---|---|---|
| `b1` | `0x402038` | `41 42 43 0a` | `"ABC"` + 换行 |
| `w1` | `0x40203c` | `34 12` | `0x1234` |
| `d1` | `0x40203e` | `ef cd ab 89` | `0x89abcdef` |
| `q1` | `0x402042` | `88 77 66 55 44 33 22 11` | `0x1122334455667788` |
| `str1` | `0x40204a` | `61 62 63 00` | `"abc"` + 结尾 0 |
| `stars` | `0x40204e` | `2a` × 8 | `"********"` |
| `pair` | `0x402056` | `61 62 61 62 61 62` | `"ababab"` |

看出规律了吗：`0x89abcdef` 存成 `ef cd ab 89`——**最低位字节排在最低地址**，这就是小端序（little-endian）。x86-64 是小端机器。所以你写 `db 0x12, 0x34` 再当成 `word` 读，得到的是 `0x3412` 而不是 `0x1234`——这是手写协议/文件格式时最容易翻车的地方。

## 五、动手练习

1. 在 `data.asm` 的 `.data` 里加 `dw 0x1234, 0x5678`，用 `movzx rdi, word [rel 标签]` 和 `movzx rdi, word [rel 标签 + 2]` 分别读出来打印，确认"数组"就是连续排布的数据。

2. 把 `w1 dw 0x1234` 改成 `dw 0x12, 0x34`，然后用 `movzx rdi, word [rel w1]` 读出来。预测结果是多少，再运行验证，解释为什么。

3. 给 `b1` 后面加一个 `b1_end:` 标签，用 `b1_end - b1` 把长度换成 `equ` 写法，和原来的 `b1_len` 对比是否一致。

4. 把 `str1_len equ $ - str1 - 1` 的 `- 1` 去掉，重新编译运行。屏幕上看得出区别吗？用 `./data | od -c | head` 看看多出来的是什么字节。

5. 在 `strlen.asm` 里加第 5 个样本：一个只含 1 个汉字的字符串（比如 `"中"`），先预测长度再运行验证。
   （提示：UTF-8 里一个常用汉字占 3 字节，所以答案不是 1。）

6. **只给思路**：把 `my_strlen` 改成"数到结尾 0 为止，但把结尾 0 也算进长度"，返回值会整体变大多少？在 `ret` 之前加一条 `inc rax` 能不能做到？

## 六、常见坑

1. **`$ - 标签` 把结尾的 0 也算进去**。`db "abc", 0` 的长度是 4，不是 3。要当 C 字符串用就写 `equ $ - 标签 - 1`。反过来，如果数据**没有**结尾 0（比如 `b1` 那种自带换行的），就不要减。

2. **字符串长度是字节数，不是字符数**。本课实测：`"长度是按字节数的，不是按字符"` 是 14 个字符、**42** 字节。用 `io_print` 打印时给的 `rdx` 必须是字节数，否则会截断或多打。

3. **`dw` 不是 4 字节**。x86 的 `word` = 16 位 = 2 字节，`dword` 才是 4 字节。混了就会读错相邻的数据。

4. **忘了写尺寸**。`mov [rel b_num], 0x2a`、`cmp [rdi], 0`、`inc [rel x]` 这类"内存 + 立即数，两边都没说明宽度"的写法，NASM 会直接报 `operation size not specified`。要写 `mov qword [rel b_num], 0x2a`、`cmp byte [rdi], 0`。

5. **`mov edi, [rel d1]` 与 `movsxd rdi, dword [rel d1]` 搞混**。前者零扩展（`0x89abcdef` → 2309737967），后者符号扩展（→ -1985229329）。读 4 字节时如果这个数可能是负数，就必须用 `movsxd`。

6. **NASM 字符串不能像 C 那样用 `""` 转义**。`db "他叫""小明"""` 会报 `error: comma expected after operand`。要么用单引号包住含双引号的字符串，要么用 `, 34,` 直接写 ASCII 码（34 就是双引号）。

7. **`db` 不会自动补结尾 0**。写 `db "abc"` 得到的是 3 个字节，后面紧跟着的就是**下一条数据定义**的字节。把它当字符串交给任何按 0 结尾的函数（包括自己写的 `my_strlen`），它会一路读下去直到碰上某个 0 —— 结果往往是把后面所有数据都打印出来。

8. **`equ` 和内存混淆**。`equ` 只是汇编期常量，不能取地址：`lea rsi, [rel Q1_LEN]` 是错的。要能取地址就得用 `dq`/`dd` 之类真的分配内存。

9. **`times` 重复的是整条语句**。`times 3 db "ab"` 得到 6 字节 `"ababab"`；如果你以为它只重复第一个字节，算长度就会错。

10. **小端序**。往文件里写多字节数值（第 09 课写文件、第 15 课做工具时会遇到）必须记住 x86 是低位在前。自己拼字节时（`db 0x12, 0x34`）和用 `dw 0x1234` 得到的顺序是**相反的**。

11. **`my_strlen` 会破坏 `rdi`**。它一路 `inc rdi`，返回时 `rdi` 已经指向字符串末尾。需要原指针就在调用前备份到 `r13` 之类的地方——`strlen.asm` 的 `show_len` 正是这么做的。这是"函数破坏了哪些寄存器"必须心里有数的典型例子。

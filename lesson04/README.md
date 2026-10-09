# 第 04 课：算术与逻辑指令、标志位

## 一、本课目标

* 会用 `add/sub/imul/div/idiv/inc/dec/neg`，并说清每条指令会改哪些标志位。
* 记住 `div/idiv` 的被除数是 **rdx:rax（128 位）**，学会用 `xor rdx,rdx` 和 `cqo` 做准备。
* 认识 `rflags` 里的 ZF/CF/SF/OF 四位，会用 `pushfq` 和 `setcc` 把它们读出来。
* 会用 `and/or/xor/not/shl/shr/sar`，包括把移位次数放进 `cl` 的写法。
* 知道调用 `io.inc` 例程之后哪些寄存器还能信得过、哪些必须自己先保护。

## 二、新概念 / 新指令

| 指令 / 概念 | 说明 | 小例子 |
|---|---|---|
| `add dst, src` | `dst += src`，按结果设置 CF/OF/SF/ZF/AF/PF | `add rax, [rel val_b]` |
| `sub dst, src` | `dst -= src`，无符号不够减时 CF=1（借位） | `sub rax, 27` |
| `imul dst, src` | 有符号乘法，只保留低 64 位；溢出时 CF=OF=1 | `imul rax, rbx` |
| `imul src`（单操作数） | `rdx:rax = rax × src`，完整的 128 位乘积 | `imul rbx` |
| `div src` | 无符号除法：`rdx:rax ÷ src`，商→rax，余数→rdx | `div rbx` |
| `idiv src` | 有符号版 `div`，商向零取整，余数符号跟被除数一致 | `idiv rbx` |
| `cqo` | 把 rax 的符号位扩展到 rdx（`idiv` 前的固定动作） | `cqo` |
| `inc` / `dec` | 加一 / 减一；改 ZF/SF/OF，但**不碰 CF** | `inc rax` |
| `neg` | 取相反数，等于 `0 - x`，也等于 `not x` 再 `+1` | `neg rax` |
| `and` / `or` / `xor` | 按位与 / 或 / 异或；三者都会清 CF、OF | `and rax, 0xffff` |
| `not` | 按位取反；**不改任何标志位** | `not rax` |
| `shl` / `shr` | 逻辑左移 / 右移，空出来的位补 0 | `shl rax, 4` |
| `sar` | 算术右移，空出来的高位补符号位 | `sar rax, 2` |
| 移位次数 | 只能是立即数或 **cl**；64 位下只取 cl 的低 6 位 | `shl rax, cl` |
| `pushfq` | 把完整的 rflags 压栈（它自己不改标志位） | `pushfq` / `pop rbx` |
| `setcc r/m8` | 按某个标志位写 0 或 1，**只写 1 字节** | `setz r12b` |
| `movzx` | 零扩展：把 1 字节安全地搬进 64 位寄存器 | `movzx edi, r12b` |
| `xor eax, eax` | 寄存器清零惯用法（短、且不依赖旧值） | `xor eax, eax` |
| `equ` | 编译期常量表达式，不占内存 | `l_add equ $ - t_add` |

### 标志位速查

rflags 是 64 位寄存器，低 16 位是经典的 8086 标志位。本课只关心这四位：

| 标志 | 位 | 含义 | 典型设置者 |
|---|---|---|---|
| CF | bit 0 | 进位 / 借位（**无符号**溢出） | add/sub/neg/shl/shr/sar |
| ZF | bit 6 | 结果是否为 0 | 几乎所有算术逻辑指令 |
| SF | bit 7 | 结果的最高位（1 表示「看成有符号时是负数」） | 同上 |
| OF | bit 11 | 有符号溢出（正+正=负、负+负=正） | add/sub/imul/shl |

一句话记住用法：**无符号看 CF，有符号看 SF/OF，判零看 ZF。** 第 05 课的条件转移就是按这个规则工作的。

## 三、示例源码逐段讲解

### 3.1 arith.asm —— 加减乘除

```asm
; ===========================================================================
; arith.asm —— 算术指令：add / sub / imul / div / idiv / inc / dec / neg
;
; 纯系统调用程序：入口 _start，nasm + ld 直接链接，不依赖 libc。
; 运行：  make && ./arith
;
; 重点：div / idiv 的被除数是 rdx:rax（128 位）。做 64 位除法之前，
;       无符号要 xor rdx,rdx，有符号要 cqo —— 忘了就是本文件最后一段的下场。
; ===========================================================================
default rel

section .data
    val_a   dq 15                   ; 用内存里的两个数做算术，顺便复习 [rel 标号]
    val_b   dq 27

    ; 提示文字；长度一律用 equ $ - 标号 算出来，不手数
    t_add    db "add:     15 + 27               = "
    l_add    equ $ - t_add
    t_sub    db "sub:     15 - 27               = "
    l_sub    equ $ - t_sub
    t_mul    db "imul:    15 * 27               = "
    l_mul    equ $ - t_mul
    t_bigmul db "imul:    1000000 * 1000000     = "
    l_bigmul equ $ - t_bigmul
    t_mul128 db "imul:    (2^32)*(2^32) rdx:rax = "
    l_mul128 equ $ - t_mul128
    t_colon  db ":"
    l_colon  equ $ - t_colon
    t_div    db "div:     100 / 7               = "
    l_div    equ $ - t_div
    t_rem    db "  rem "
    l_rem    equ $ - t_rem
    t_idiv   db "idiv:    -100 / 7              = "
    l_idiv   equ $ - t_idiv
    t_inc    db "inc:     41 + 1                = "
    l_inc    equ $ - t_inc
    t_dec    db "dec:     42 - 1                = "
    l_dec    equ $ - t_dec
    t_neg    db "neg:     -(5)                  = "
    l_neg    equ $ - t_neg
    t_hi     db "div:     2^64 / 10             = "
    l_hi     equ $ - t_hi
    t_bug    db "div:     100 / 7 (rdx=1)       = "
    l_bug    equ $ - t_bug

section .text
    global _start
%include "io.inc"                   ; 只能在 .text 里、_start 之前 include 一次

_start:
; ---- 1) add：内存操作数直接参与运算，宽度由 dq 决定 ----
    lea  rsi, [rel t_add]
    mov  rdx, l_add
    call io_print
    mov  rax, [rel val_a]
    add  rax, [rel val_b]           ; 15 + 27 = 42
    mov  rdi, rax
    call io_print_int
    call io_newline

; ---- 2) sub：15 - 27 得到负数的补码 0xfffffffffffffff4 ----
    lea  rsi, [rel t_sub]
    mov  rdx, l_sub
    call io_print
    mov  rax, [rel val_a]
    sub  rax, [rel val_b]           ; = -12
    mov  rdi, rax
    call io_print_int
    call io_newline

; ---- 3) imul：两个操作数的写法只保留低 64 位乘积，rdx 不变 ----
    lea  rsi, [rel t_mul]
    mov  rdx, l_mul
    call io_print
    mov  rax, [rel val_a]
    mov  rbx, [rel val_b]
    imul rax, rbx                   ; 15 * 27 = 405
    mov  rdi, rax
    call io_print_int
    call io_newline

    lea  rsi, [rel t_bigmul]
    mov  rdx, l_bigmul
    call io_print
    mov  rax, 1000000
    mov  rbx, 1000000
    imul rax, rbx                   ; 10^12，64 位放得下
    mov  rdi, rax
    call io_print_int
    call io_newline

; 一个操作数的 imul：rdx:rax = rax * 操作数（完整 128 位乘积）
    lea  rsi, [rel t_mul128]
    mov  rdx, l_mul128
    call io_print
    mov  rax, 0x100000000           ; 2^32
    mov  rbx, 0x100000000
    imul rbx                        ; 2^32 * 2^32 = 2^64 → rdx=1, rax=0
    mov  r12, rax                   ; 低位先搬走：后面 io 例程会破坏 rdx
    mov  r13, rdx                   ; 高位（r12/r13 不会被 io 例程破坏）
    mov  rdi, r13
    call io_print_uint
    lea  rsi, [rel t_colon]
    mov  rdx, l_colon
    call io_print
    mov  rdi, r12
    call io_print_uint
    call io_newline

; ---- 4) div：无符号除法。商在 rax、余数在 rdx，做 64 位除法前必须清 rdx ----
    lea  rsi, [rel t_div]
    mov  rdx, l_div
    call io_print
    mov  rax, 100
    xor  rdx, rdx                   ; ★ 被除数高 64 位清 0，否则商完全不对
    mov  rbx, 7
    div  rbx                        ; rax = 14（商），rdx = 2（余数）
    mov  r12, rdx                   ; 余数先搬走：io_print_int 会破坏 rdx
    mov  rdi, rax
    call io_print_int
    lea  rsi, [rel t_rem]
    mov  rdx, l_rem
    call io_print
    mov  rdi, r12
    call io_print_int
    call io_newline

; ---- 5) idiv：有符号除法，除法前用 cqo 把 rax 的符号位扩展到 rdx ----
    lea  rsi, [rel t_idiv]
    mov  rdx, l_idiv
    call io_print
    mov  rax, -100
    cqo                             ; ★ rdx:rax = 符号扩展后的 -100
    mov  rbx, 7
    idiv rbx                        ; rax = -14，rdx = -2（余数符号跟被除数）
    mov  r12, rdx
    mov  rdi, rax
    call io_print_int
    lea  rsi, [rel t_rem]
    mov  rdx, l_rem
    call io_print
    mov  rdi, r12
    call io_print_int
    call io_newline

; ---- 6) inc / dec：加一 / 减一，会改 ZF/SF/OF，但不碰 CF ----
    lea  rsi, [rel t_inc]
    mov  rdx, l_inc
    call io_print
    mov  rax, 41
    inc  rax                        ; 42
    mov  rdi, rax
    call io_print_int
    call io_newline

    lea  rsi, [rel t_dec]
    mov  rdx, l_dec
    call io_print
    mov  rax, 42
    dec  rax                        ; 41
    mov  rdi, rax
    call io_print_int
    call io_newline

; ---- 7) neg：取相反数，等价于 0 - x，也等价于 not x 再 +1 ----
    lea  rsi, [rel t_neg]
    mov  rdx, l_neg
    call io_print
    mov  rax, 5
    neg  rax                        ; -5
    mov  rdi, rax
    call io_print_int
    call io_newline

; ---- 8) 证明 rdx 就是「被除数的高 64 位」：rdx=1 时算的是 2^64 / 10 ----
    lea  rsi, [rel t_hi]
    mov  rdx, l_hi
    call io_print
    xor  eax, eax                   ; 低 64 位 = 0
    mov  rdx, 1                     ; 高 64 位 = 1 → 被除数 = 2^64
    mov  rbx, 10
    div  rbx
    mov  r12, rdx
    mov  rdi, rax
    call io_print_uint              ; 商 1844674407370955161
    lea  rsi, [rel t_rem]
    mov  rdx, l_rem
    call io_print
    mov  rdi, r12
    call io_print_uint              ; 余 6
    call io_newline

; ---- 9) 反面教材：忘了清 rdx（这里故意留成 1，保证输出可复现）。
;         真实 bug 里 rdx 是上次除法的余数或别的残留值，症状是「商大得离谱」 ----
    lea  rsi, [rel t_bug]
    mov  rdx, l_bug
    call io_print
    mov  rax, 100
    mov  rdx, 1                     ; ← 忘了清零！被除数变成 2^64 + 100
    mov  rbx, 7
    div  rbx                        ; 商 2635249153387078816，余 4
    mov  r12, rdx
    mov  rdi, rax
    call io_print_uint
    lea  rsi, [rel t_rem]
    mov  rdx, l_rem
    call io_print
    mov  rdi, r12
    call io_print_uint
    call io_newline

; ---- 结束进程：io_exit 内部是 mov rax,60 / syscall，不返回 ----
    xor  edi, edi
    call io_exit
```

**`add` / `sub`：内存操作数可以直接参与运算。**
`val_a`、`val_b` 是 `dq` 定义的 64 位量，所以 `add rax, [rel val_b]` 的源操作数是 64 位内存，
和 64 位的 `rax` 宽度一致。写汇编时**每一对操作数宽度必须匹配**：
如果 `val_b` 是 `dd`，就必须写 `add eax, [rel val_b]`（32 位版本），
或者 `movsx/movzx` 扩展后再算。另外注意：任何写 32 位寄存器的指令都会把高 32 位清零，
`add eax, ebx` 的结果不是「只改低 32 位」而是「rax 的高 32 位变 0」。

**`imul` 的两种形式。**
两个操作数的 `imul rax, rbx` 只保留低 64 位乘积，结果放 `rax`；乘积超出 64 位时不报错，
只是把 CF/OF 置 1 提醒你「高位丢了」。
一个操作数的 `imul rbx` 则把完整的 128 位乘积放到 `rdx:rax` 里：
例子中 `2^32 × 2^32 = 2^64`，低 64 位是 0、高 64 位是 1，所以打印出 `1:0`。
这里先把 `rax`、`rdx` 分别搬到 `r12`、`r13` 再打印 —— 因为后面要提醒你：
`io.inc` 的数字打印例程内部要用 `rdx` 做除法或中转，会把 `rdx` 冲掉。

**`div` 和那个必修的 `xor rdx, rdx`。**
`div rbx` 算的是 `(rdx:rax) ÷ rbx`，也就是把 `rdx` 和 `rax` 拼成一个 128 位被除数，
商写回 `rax`、余数写回 `rdx`。我们只想算 64 位除法，所以要先把高 64 位清零：

```asm
    mov  rax, 100
    xor  rdx, rdx        ; 必须！否则被除数变成 2^64×rdx + 100
    mov  rbx, 7
    div  rbx             ; rax = 14, rdx = 2
```

漏写这一行的后果在本文件第 8、9 段里都实际演了一遍：

* `rdx = 1` 时被除数是 `2^64`，`2^64 / 10 = 1844674407370955161 余 6`；
* 本该是 `100 / 7 = 14 余 2`，`rdx` 残留 1 时算出来是 `2635249153387078816 余 4`。

还有两个必须知道的分支：

* 除数不能为 0，否则 CPU 抛 `#DE`，Linux 把它变成 **SIGFPE，进程直接崩掉**；
* 商必须放得进 64 位（`rdx` 清零后就是 `rax < rbx` 不成立时），否则同样抛 `#DE`。
  所以 `div` 之前最好先比较一下。

**`idiv` 前的 `cqo`。**
有符号除法的被除数也是 `rdx:rax`，只是这里的 `rdx` 要是 `rax` 的**符号扩展**：
正数时 `rdx = 0`，负数时 `rdx = 0xffffffffffffffff`。`cqo` 就是干这个的
（`cqo` 把 rax 扩展到 rdx:rax；对应的 32 位版本是 `cdq`，16 位是 `cwd`，8 位是 `cbw`）。
有符号除法的余数符号跟**被除数**一致：`-100 / 7 = -14 余 -2`，
这和数学上的「余数取正」不一样。

**`inc` / `dec` / `neg`。**
`inc rax` 比 `add rax, 1` 编码更短，但要注意它**不修改 CF**，这是历史遗留设计
（为了让循环里的进位链不被破坏）。`dec` 同理。`neg rax` 等价于 `0 - rax`，
会像 `sub` 一样设置 CF/OF/SF/ZF。

### 3.2 flags.asm —— 把标志位读出来

```asm
; ===========================================================================
; flags.asm —— 观察 rflags 里的 ZF / CF / SF / OF
;
;   * 算术、逻辑、比较指令都会按结果重设标志位（flag）
;   * pushfq 把整个 rflags 压栈，pop 到通用寄存器后就能逐位检查
;   * setz / setc / sets / seto 把单个标志位搬进寄存器的低 8 位
;
; 纯系统调用程序：入口 _start。运行：  make && ./flags
; ===========================================================================
default rel

%define FLAG_MASK 0x8c1             ; CF=bit0、ZF=bit6、SF=bit7、OF=bit11

section .data
    ; 第一组：用 setcc 逐个打印标志位的名字
    c1 db "sub 5 - 5            -> "
    lc1 equ $ - c1
    c2 db "sub 1 - 2            -> "
    lc2 equ $ - c2
    c3 db "add 0x7fff..ff + 1   -> "
    lc3 equ $ - c3

    s_zf db "ZF="
    l_zf equ $ - s_zf
    s_cf db "  CF="
    l_cf equ $ - s_cf
    s_sf db "  SF="
    l_sf equ $ - s_sf
    s_of db "  OF="
    l_of equ $ - s_of

    ; 第二组：用 pushfq 直接看 rflags 的二进制
    c4 db "add -1 + 1           -> rflags & 0x8c1 = "
    lc4 equ $ - c4
    c5 db "test 0x0f & 0xf0     -> rflags & 0x8c1 = "
    lc5 equ $ - c5
    c6 db "shl 0x8000..00 by 1  -> rflags & 0x8c1 = "
    lc6 equ $ - c6
    legend db "   [bit0=CF bit6=ZF bit7=SF bit11=OF]", 10
    l_legend equ $ - legend

section .text
    global _start
%include "io.inc"

_start:
; ===========================================================================
; 第一组：setcc 把四个标志位分别写进 r12b / r13b / r14b / r15b
;   setz（同义 sete）：ZF=1 写 1；setc（同义 setb）：CF=1 写 1；
;   sets：SF=1 写 1；seto：OF=1 写 1。
; 打印时用 movzx edi, r12b 零扩展再打印：setcc 只写低 8 位，高 56 位是垃圾值。
; ===========================================================================

; ---- 例 1：5 - 5 = 0 → ZF=1；无进位/借位，SF、OF 都是 0 ----
    lea  rsi, [rel c1]
    mov  rdx, lc1
    call io_print
    mov  rax, 5
    sub  rax, 5                     ; ← 被观察的指令
    setz r12b
    setc r13b
    sets r14b
    seto r15b
    lea  rsi, [rel s_zf]
    mov  rdx, l_zf
    call io_print
    movzx edi, r12b
    call io_print_uint
    lea  rsi, [rel s_cf]
    mov  rdx, l_cf
    call io_print
    movzx edi, r13b
    call io_print_uint
    lea  rsi, [rel s_sf]
    mov  rdx, l_sf
    call io_print
    movzx edi, r14b
    call io_print_uint
    lea  rsi, [rel s_of]
    mov  rdx, l_of
    call io_print
    movzx edi, r15b
    call io_print_uint
    call io_newline

; ---- 例 2：1 - 2 = -1 → 借位 CF=1；结果为负 SF=1；两正数相减不溢出 OF=0 ----
    lea  rsi, [rel c2]
    mov  rdx, lc2
    call io_print
    mov  rax, 1
    sub  rax, 2                     ; ← 被观察的指令
    setz r12b
    setc r13b
    sets r14b
    seto r15b
    lea  rsi, [rel s_zf]
    mov  rdx, l_zf
    call io_print
    movzx edi, r12b
    call io_print_uint
    lea  rsi, [rel s_cf]
    mov  rdx, l_cf
    call io_print
    movzx edi, r13b
    call io_print_uint
    lea  rsi, [rel s_sf]
    mov  rdx, l_sf
    call io_print
    movzx edi, r14b
    call io_print_uint
    lea  rsi, [rel s_of]
    mov  rdx, l_of
    call io_print
    movzx edi, r15b
    call io_print_uint
    call io_newline

; ---- 例 3：0x7fffffffffffffff + 1 = 0x8000000000000000
;          无符号无进位 CF=0；有符号「正 + 正 = 负」溢出 OF=1，SF 也随之为 1 ----
    lea  rsi, [rel c3]
    mov  rdx, lc3
    call io_print
    mov  rax, 0x7fffffffffffffff
    add  rax, 1                     ; ← 被观察的指令
    setz r12b
    setc r13b
    sets r14b
    seto r15b
    lea  rsi, [rel s_zf]
    mov  rdx, l_zf
    call io_print
    movzx edi, r12b
    call io_print_uint
    lea  rsi, [rel s_cf]
    mov  rdx, l_cf
    call io_print
    movzx edi, r13b
    call io_print_uint
    lea  rsi, [rel s_sf]
    mov  rdx, l_sf
    call io_print
    movzx edi, r14b
    call io_print_uint
    lea  rsi, [rel s_of]
    mov  rdx, l_of
    call io_print
    movzx edi, r15b
    call io_print_uint
    call io_newline

; ===========================================================================
; 第二组：pushfq / popfq 直接拿完整 rflags
;   pushfq 把 64 位 rflags 压栈（它自己不改标志位），pop rbx 就得到全部标志位；
;   再用 and 只留关心的 4 位，交给 io_print_bin 打成 0bxxxx 的形式。
; ===========================================================================

; ---- 例 4：-1 + 1 = 0，加法产生进位 CF=1、结果为 0 所以 ZF=1
;          → 掩码留下 bit0、bit6 = 0b1000001 ----
    lea  rsi, [rel c4]
    mov  rdx, lc4
    call io_print
    mov  rax, -1                    ; 0xffffffffffffffff
    add  rax, 1                     ; ← 被观察的指令
    pushfq
    pop  rbx                        ; rbx = 完整 rflags
    mov  rdi, rbx
    and  rdi, FLAG_MASK             ; 只留 CF/ZF/SF/OF，其余位清 0
    call io_print_bin
    lea  rsi, [rel legend]
    mov  rdx, l_legend
    call io_print                   ; legend 末尾自带 '\n'

; ---- 例 5：test 只做按位与、不写回，且规定 CF=OF=0
;          0x0f & 0xf0 = 0 → ZF=1 → 只剩 bit6 = 0b1000000 ----
    lea  rsi, [rel c5]
    mov  rdx, lc5
    call io_print
    mov  rax, 0x0f
    test rax, 0xf0                  ; ← 被观察的指令
    pushfq
    pop  rbx
    mov  rdi, rbx
    and  rdi, FLAG_MASK
    call io_print_bin
    lea  rsi, [rel legend]
    mov  rdx, l_legend
    call io_print

; ---- 例 6：0x8000000000000000 << 1 = 0，移出的 1 进 CF=1，结果全 0 → ZF=1，
;          OF = 结果最高位 XOR CF = 0 XOR 1 = 1
;          → bit0+bit6+bit11 = 0b100001000001 ----
    lea  rsi, [rel c6]
    mov  rdx, lc6
    call io_print
    mov  rax, 0x8000000000000000
    shl  rax, 1                     ; ← 被观察的指令
    pushfq
    pop  rbx
    mov  rdi, rbx
    and  rdi, FLAG_MASK
    call io_print_bin
    lea  rsi, [rel legend]
    mov  rdx, l_legend
    call io_print

; ---- 结束进程 ----
    xor  edi, edi
    call io_exit
```

程序分两组，分别演示「读单个标志位」和「读整个 rflags」两种办法。

**第一组：`setcc`。**
`setz/setc/sets/seto` 根据刚执行的指令留下的标志位，把目标寄存器的**低 8 位**写成 1 或 0，
其余 56 位**保持原样**。所以打印前要用 `movzx edi, r12b` 把这一字节零扩展成 64 位，
否则高位垃圾值会让 `io_print_uint` 打印出一个天文数字。
`setcc` 必须紧跟在被观察的指令后面：中间只要插入任何改标志位的指令（包括 `mov` 不影响标志，
但 `xor`、`add` 会），读到的就不是原来那次运算的结果了。

三个例子的标志位推导：

| 指令 | ZF | CF | SF | OF | 原因 |
|---|---|---|---|---|---|
| `sub rax, 5`（rax=5） | 1 | 0 | 0 | 0 | 结果为 0 → ZF=1；无借位 → CF=0；最高位 0 → SF=0 |
| `sub rax, 2`（rax=1） | 0 | 1 | 1 | 0 | 1-2 不够减 → CF=1；结果为负 → SF=1；同号相减不会溢出 → OF=0 |
| `add rax, 1`（rax=0x7fff…ff） | 0 | 0 | 1 | 1 | 无符号没进位 → CF=0；正+正=负 → OF=1，结果最高位为 1 → SF=1 |

**第二组：`pushfq` + 掩码 + `io_print_bin`。**
`pushfq` 把整个 rflags 压到栈上，`pop rbx` 就拿到了全部标志位（这一对指令本身不改标志位）。
然后用 `and rdi, 0x8c1` 只留下 CF(bit0)、ZF(bit6)、SF(bit7)、OF(bit11) 四位，
其余位清零，再用 `io_print_bin` 打成 `0b…` 的形式。

| 指令 | 留下的位 | 输出的二进制 | 怎么读 |
|---|---|---|---|
| `add rax, 1`（rax=-1） | CF+ZF | `0b1000001` | bit0=1(CF)、bit6=1(ZF) |
| `test rax, 0xf0`（rax=0x0f） | ZF | `0b1000000` | `0x0f & 0xf0 = 0` → ZF=1；test 强制 CF=OF=0 |
| `shl rax, 1`（rax=0x8000…00） | CF+ZF+OF | `0b100001000001` | 移出的 1 进 CF，结果全 0 所以 ZF=1，OF = 结果最高位 XOR CF = 1 |

最后一条 `shl` 的规则值得记：**移位次数为 1 时**，`shl` 的 OF = 结果的最高位 XOR CF。
（`shr` 的 OF 是移位前操作数的最高位，`sar` 的 OF 恒为 0；这些细节在需要判断溢出时才用得上。）

顺便说一句：`test` 指令就是「只做 `and`、不写回结果」的版本，它和所有 `and` 一样会清掉 CF 和 OF，
所以 `test` 之后不可能靠 `jb/ja` 判断大小，只能看 ZF/SF。

### 3.3 bitops.asm —— 位运算

```asm
; ===========================================================================
; bitops.asm —— 位运算：and / or / xor / not / shl / shr / sar
;
; 纯系统调用程序：入口 _start。运行：  make && ./bitops
;
; 移位次数只有两种写法：shl rax, 4（立即数）或 shl rax, cl（寄存器）。
; 寄存器形式**必须**用 cl，别的寄存器不行；64 位下只取 cl 的低 6 位，
; 所以 cl=65 实际只移 1 位。
; ===========================================================================
default rel

section .data
    t_and  db "and:  0x1234abcd & 0x0000ffff = "
    l_and  equ $ - t_and
    t_or   db "or:   0x1000 | 0x0001         = "
    l_or   equ $ - t_or
    t_xor  db "xor:  0b1100 ^ 0b1010         = "
    l_xor  equ $ - t_xor
    t_not  db "not:  ~0x0f                   = "
    l_not  equ $ - t_not
    t_shl4 db "shl:  1 << 4                  = "
    l_shl4 equ $ - t_shl4
    t_shl63 db "shl:  1 << 63                 = "
    l_shl63 equ $ - t_shl63
    t_shr  db "shr:  0x8000000000000000 >> 3 = "
    l_shr  equ $ - t_shr
    t_sar  db "sar:  -16 >> 2 (arith)        = "
    l_sar  equ $ - t_sar
    t_shrn db "shr:  -16 >> 2 (logical)      = "
    l_shrn equ $ - t_shrn
    t_cl8  db "shl:  1 << cl (cl = 8)        = "
    l_cl8  equ $ - t_cl8
    t_cl65 db "shl:  1 << cl (cl = 65)       = "
    l_cl65 equ $ - t_cl65
    t_zero db "xor:  eax ^= eax (zero idiom) = "
    l_zero equ $ - t_zero

section .text
    global _start
%include "io.inc"

_start:
; ---- 1) and：按位与，用来「取某些位」（掩码 mask），test 指令内部就是它 ----
    lea  rsi, [rel t_and]
    mov  rdx, l_and
    call io_print
    mov  rax, 0x1234abcd
    and  rax, 0x0000ffff            ; 只保留低 16 位 → 0xabcd
    mov  rdi, rax
    call io_print_hex
    call io_newline

; ---- 2) or：按位或，用来「置某些位」 ----
    lea  rsi, [rel t_or]
    mov  rdx, l_or
    call io_print
    mov  rax, 0x1000
    or   rax, 0x0001                ; 最低位置 1 → 0x1001
    mov  rdi, rax
    call io_print_hex
    call io_newline

; ---- 3) xor：相同为 0、不同为 1；0b1100 ^ 0b1010 = 0b0110 ----
    lea  rsi, [rel t_xor]
    mov  rdx, l_xor
    call io_print
    mov  rax, 0b1100
    xor  rax, 0b1010                ; → 0b110（去掉了前导 0）
    mov  rdi, rax
    call io_print_bin
    call io_newline

; ---- 4) not：按位取反，64 位寄存器就是全部 64 位取反 ----
    lea  rsi, [rel t_not]
    mov  rdx, l_not
    call io_print
    mov  rax, 0x0f
    not  rax                        ; 0xfffffffffffffff0
    mov  rdi, rax
    call io_print_hex
    call io_newline

; ---- 5) shl：逻辑左移，低位补 0，移出去的最高位进 CF ----
    lea  rsi, [rel t_shl4]
    mov  rdx, l_shl4
    call io_print
    mov  rax, 1
    shl  rax, 4                     ; 1 << 4 = 16
    mov  rdi, rax
    call io_print_uint
    call io_newline

    lea  rsi, [rel t_shl63]
    mov  rdx, l_shl63
    call io_print
    mov  rax, 1
    shl  rax, 63                    ; 1 << 63 = 0x8000000000000000
    mov  rdi, rax
    call io_print_hex
    call io_newline

; ---- 6) shr：逻辑右移，高位一律补 0（把操作数当无符号数看） ----
    lea  rsi, [rel t_shr]
    mov  rdx, l_shr
    call io_print
    mov  rax, 0x8000000000000000
    shr  rax, 3                     ; → 0x1000000000000000
    mov  rdi, rax
    call io_print_hex
    call io_newline

; ---- 7) sar：算术右移，高位补符号位。
;         对比：同一个 -16 用 shr 会变成一个很大的正数 ----
    lea  rsi, [rel t_sar]
    mov  rdx, l_sar
    call io_print
    mov  rax, -16                   ; 0xfffffffffffffff0
    sar  rax, 2                     ; -16 / 4 = -4
    mov  rdi, rax
    call io_print_int
    call io_newline

    lea  rsi, [rel t_shrn]
    mov  rdx, l_shrn
    call io_print
    mov  rax, -16
    shr  rax, 2                     ; 高位补 0 → 0x3ffffffffffffffc
    mov  rdi, rax
    call io_print_uint              ; 4611686018427387900
    call io_newline

; ---- 8) 移位次数放在 cl 里：cl=65 只取低 6 位（65 & 63 = 1），等于左移 1 位 ----
    lea  rsi, [rel t_cl8]
    mov  rdx, l_cl8
    call io_print
    mov  rax, 1
    mov  cl, 8                      ; 只用到 cl，rcx 高位是什么都不影响
    shl  rax, cl                    ; 1 << 8 = 256
    mov  rdi, rax
    call io_print_uint
    call io_newline

    lea  rsi, [rel t_cl65]
    mov  rdx, l_cl65
    call io_print
    mov  rax, 1
    mov  cl, 65                     ; 65 & 63 = 1
    shl  rax, cl                    ; 实际只左移 1 位 → 2
    mov  rdi, rax
    call io_print_uint
    call io_newline

; ---- 9) xor 自己 = 清零：x86 上把寄存器置 0 的推荐写法（比 mov 短，
;         而且不依赖寄存器的旧值；副作用是 ZF=1、CF=OF=0） ----
    lea  rsi, [rel t_zero]
    mov  rdx, l_zero
    call io_print
    xor  eax, eax                   ; rax = 0（写 32 位寄存器会顺带清高 32 位）
    mov  rdi, rax
    call io_print_uint
    call io_newline

; ---- 结束进程 ----
    xor  edi, edi
    call io_exit
```

**四种按位运算的典型用途。**

| 运算 | 口诀 | 典型用途 | 对标志位的影响 |
|---|---|---|---|
| `and` | 都为 1 才为 1 | 取某些位（掩码）、`test` | 清 CF=OF=0，设置 SF/ZF/PF |
| `or` | 有一个 1 就为 1 | 置某些位 | 同上 |
| `xor` | 不同为 1 | 翻转某些位、`xor reg,reg` 清零 | 同上 |
| `not` | 逐位取反 | 生成掩码的补 | **一个都不改** |

`not` 不改标志位这一点经常坑人：写 `not rax` 后接着 `jz` 是没意义的，得自己再 `test rax, rax`。

**移位三兄弟。**

* `shl`：左移，低位补 0。左移 1 位等于乘 2，移出去的最高位进 CF。
  注意 `1 << 63` 得到的 `0x8000000000000000` 在**有符号**视角下是负数（-9223372036854775808）。
* `shr`：逻辑右移，高位一律补 0。它把操作数当无符号数看，所以 `-16 >> 2` 会得到
  `0x3ffffffffffffffc = 4611686018427387900` 这个很大的正数。
* `sar`：算术右移，高位补符号位。`-16 sar 2 = -4`，这是编译器处理「有符号数除以 2 的幂」时用的指令
  （对负数它等价于向下取整，`-5 sar 1 = -3`，而 `-5 / 2` 在 C 里是 `-2`）。

**移位次数必须放在 `cl`。**
`shl rax, bl`、`shl rax, r10` 都是非法指令，只有 `cl` 能用。
而且 64 位操作数下 CPU 只取 `cl` 的低 6 位：`cl = 65` 时 `65 & 63 = 1`，实际只移 1 位，
所以文件里 `1 << cl`（cl=65）打印出来是 2 而不是「移出天际」。
移位次数为 0 时指令什么都不做，标志位也不变。

**`xor eax, eax` 清零。**
它比 `mov eax, 0` 短，而且 CPU 能识别这个惯用法、不产生对旧值的依赖，是 x86 上的推荐写法。
副作用是它会设置 ZF=1、PF=1，并清掉 CF/OF —— 后面接 `jz`/`jnz` 时留意。

## 四、编译与运行

```bash
cd lesson04
make                # 编译 arith、flags、bitops
./arith
./flags
./bitops
make test           # 一键编译并比对输出（test.sh）
```

`./arith` 的真实输出（每行的数字都是本课要你亲手验证的结果）：

```text
add:     15 + 27               = 42
sub:     15 - 27               = -12
imul:    15 * 27               = 405
imul:    1000000 * 1000000     = 1000000000000
imul:    (2^32)*(2^32) rdx:rax = 1:0
div:     100 / 7               = 14  rem 2
idiv:    -100 / 7              = -14  rem -2
inc:     41 + 1                = 42
dec:     42 - 1                = 41
neg:     -(5)                  = -5
div:     2^64 / 10             = 1844674407370955161  rem 6
div:     100 / 7 (rdx=1)       = 2635249153387078816  rem 4
```

`./flags`：

```text
sub 5 - 5            -> ZF=1  CF=0  SF=0  OF=0
sub 1 - 2            -> ZF=0  CF=1  SF=1  OF=0
add 0x7fff..ff + 1   -> ZF=0  CF=0  SF=1  OF=1
add -1 + 1           -> rflags & 0x8c1 = 0b1000001   [bit0=CF bit6=ZF bit7=SF bit11=OF]
test 0x0f & 0xf0     -> rflags & 0x8c1 = 0b1000000   [bit0=CF bit6=ZF bit7=SF bit11=OF]
shl 0x8000..00 by 1  -> rflags & 0x8c1 = 0b100001000001   [bit0=CF bit6=ZF bit7=SF bit11=OF]
```

`./bitops`：

```text
and:  0x1234abcd & 0x0000ffff = 0xabcd
or:   0x1000 | 0x0001         = 0x1001
xor:  0b1100 ^ 0b1010         = 0b110
not:  ~0x0f                   = 0xfffffffffffffff0
shl:  1 << 4                  = 16
shl:  1 << 63                 = 0x8000000000000000
shr:  0x8000000000000000 >> 3 = 0x1000000000000000
sar:  -16 >> 2 (arith)        = -4
shr:  -16 >> 2 (logical)      = 4611686018427387900
shl:  1 << cl (cl = 8)        = 256
shl:  1 << cl (cl = 65)       = 2
xor:  eax ^= eax (zero idiom) = 0
```

## 五、动手练习

1. 把 `arith.asm` 里 `val_a`、`val_b` 改成别的数（比如 100 和 7，或两个负数），重新 `make && ./arith`，
   猜一遍输出再看结果。
2. 在 `bitops.asm` 里把 `mov cl, 65` 改成 `mov cl, 128`，先写出你预测的值再运行验证。
3. 在 `flags.asm` 第一组里加一个例子 `sub rax, rax`（rax 任意），把 ZF/CF/SF/OF 都打印出来，
   并解释为什么 CF 是 0 而不是 1。
4. 用 `and` + `test` 判断一个数是奇数还是偶数（偶数的最低位是 0），打印 `even` / `odd`。
5. 用移位代替乘除：把 7 乘 8、把 -128 除以 8（分别用 `shl`、`shr`、`sar` 各试一次），
   比较无符号和有符号结果为什么不同。
6. 自己写一个程序：计算 `(a * b + c) / d`（a、b、c、d 用 `.data` 里的 `dq` 定义，
   含负数），把商和余数都打印出来。

练习 3 提示：`sub x, x` 的结果一定是 0，但「无符号减法」要发生借位只有 `x < x` 时成立，
所以 CF 只会是 0；`inc/dec` 和 `sub` 对 CF 的处理差别也可以顺手对比一下。

练习 6 提示：乘法用 `imul`（单操作数形式会得到 `rdx:rax`，记得先搬走再用）；
除法前先想清楚是 `xor rdx,rdx` 还是 `cqo`，余数在 `rdx` 里、并且在任何 `io.inc` 调用之前就要搬走。

## 六、常见坑

1. **`div` 前忘记清 `rdx`**：本课用实例演示了它会把商变成天文数字。同理 `idiv` 前忘记 `cqo`，
   负数除法会得到完全错误的结果（`-100 / 7` 会算出 `2635249153387078815` 之类的怪值）。
2. **设置 64 位量的长度时写 `mov dl, 1`**：只写低 8 位，`rdx` 的高 56 位还是旧的。
   要写 `mov edx, 1`（写 32 位会顺带清高 32 位），需要完整 64 位就用 `mov rdx, 1`。
3. **`imul` 两操作数形式溢出没有任何报错**，只有 CF/OF 被置位；要么自己检查 CF，要么用 `imul rbx` 的 128 位形式。
4. **`inc`/`dec` 不改 CF**，想在循环里用 `jc` 判断「加爆了」是无效的。
5. **`setcc` 只写低 8 位**，直接 `mov rdi, r12` 打印可能打出一个巨大的数字；记得 `movzx`。
6. **移位次数只能用 `cl`**，而且 64 位下只取低 6 位（`cl=64` 等于移 0 位，不是移 64 位）。
7. **`shr` 不等于有符号除法**：负数右移要用 `sar`，`shr` 会把符号位带走变成大正数。
8. **`io.inc` 例程会破坏 `rcx`**（`syscall` 会把返回地址放进 rcx），
   把循环计数器放在 `rcx` 里跨调用使用必然出错；跨调用请用 `rbx/rbp/r12-r15`。
   实测还发现：`io_print_int/uint/hex` 内部用 `div`、`io_print_bin` 用 `rdx` 当中转，
   **这四个打印例程都会破坏 `rdx`**；另外负数路径下的 `io_print_int` 会把 `rdi`
   改成绝对值 —— 所以除法算完的余数（在 `rdx` 里）和后面还要打印的值都要先搬到
   `rbx/rbp/r12-r15` 再调用打印例程。
9. **`.data` 里不能用 `LF`、`STDOUT`、`SYS_write` 这些宏**：它们在 `io.inc`/`syscalls.inc` 里定义，
   而 `%include` 写在 `.text` 段中、`_start` 之前，预处理是按行顺序进行的，
   在它之前的数据定义里引用这些宏会报「symbol not defined」。数据区里换行直接写 `10`。
10. **内存操作数的宽度不能想当然**：`val_b` 是 `dq` 才能写 `add rax, [rel val_b]`；
    换成正数 16 位的 `dw` 就必须改用 16 位寄存器或先 `movzx/movsx`。

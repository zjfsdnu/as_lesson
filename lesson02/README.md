# 第 02 课：寄存器、内存、段（objdump 初探）

## 一、本课目标

- 记住 16 个通用寄存器（general purpose register）的 64/32/16/8 位名字，理解它们是**同一个物理寄存器的不同窗口**。
- 掌握两条容易搞错的宽窄规则：写 32 位寄存器会清零高 32 位，写 16/8 位不会。
- 分清程序的三种数据位置：`.data`（有初值）、`.bss`（无初值）、栈（运行期临时空间），并知道各自的地址大概在哪。
- 会用 `objdump`、`readelf`、`nm`、`size` 看段（section）和符号（symbol）。
- 会写最小的一段栈操作：`sub rsp, N` → `mov [rsp], ...` → `add rsp, N`。

## 二、新概念 / 新指令

### 2.1 通用寄存器宽度对照表

x86-64 有 16 个通用寄存器。同一个寄存器的低位部分有单独的名字：

| 64 位 | 低 32 位 | 低 16 位 | 低 8 位 | 第 8~15 位 | 常见用途 |
|---|---|---|---|---|---|
| `rax` | `eax` | `ax` | `al` | `ah` | 累加器；**系统调用号 / 函数返回值** |
| `rbx` | `ebx` | `bx` | `bl` | `bh` | 被调用者保存（callee-saved），可跨 `call` 使用 |
| `rcx` | `ecx` | `cx` | `cl` | `ch` | C 函数第 4 个参数；`syscall` 会破坏它 |
| `rdx` | `edx` | `dx` | `dl` | `dh` | 第 3 个参数 |
| `rsi` | `esi` | `si` | `sil` | — | 第 2 个参数；常放源地址 |
| `rdi` | `edi` | `di` | `dil` | — | 第 1 个参数；常放目标地址 |
| `rbp` | `ebp` | `bp` | `bpl` | — | 栈帧基址（frame pointer） |
| `rsp` | `esp` | `sp` | `spl` | — | **栈指针**，指向栈顶 |
| `r8`~`r15` | `r8d`~`r15d` | `r8w`~`r15w` | `r8b`~`r15b` | — | x86-64 新增的 8 个寄存器 |

（`rip` 是指令指针、`rflags` 是标志位寄存器，它们不能当普通数据寄存器用。）

注意 `rsi/rdi/rbp/rsp` **没有**"高 8 位"版本，只有 `sil/dil/bpl/spl`；这几个名字需要 REX 前缀才能编码。

### 2.2 本课新指令与新概念

| 概念 / 指令 | 一句话说明 | 小例子 |
|---|---|---|
| `mov ax, 0xaabb` | 只写低 16 位，高 48 位**保持原样** | `mov ax, 0xaabb` |
| `mov al, 0xcc` | 只写低 8 位，其余位不动 | `mov al, 0xcc` |
| `mov eax, 0xdeadbeef` | 写 32 位，rax 的**高 32 位自动清零** | `mov eax, 1` |
| `mov ah, 0x77` | 写第 8~15 位（第二个字节） | `mov ah, 0x77` |
| `movzx 目标, 源` | 零扩展：把窄值放大到宽寄存器，空位补 0 | `movzx rax, al` |
| `movsx 目标, 源` | 符号扩展：空位用符号位填充 | `movsx rax, al` |
| `movsxd 目标, 源` | 专门把 32 位**符号**扩展到 64 位 | `movsxd rdi, dword [rel d1]` |
| `section .data` | 已初始化数据段，占可执行文件体积 | `d_val dq 0x1122` |
| `section .bss` | 未初始化数据段，**不占文件体积**，加载时清零 | `b_num resq 1` |
| `resb` / `resq` | "预留" N 字节 / N 个 qword 的空间（只声明，不给初值） | `buf resb 64` |
| `[rsp]`、`[rsp+8]` | 用寄存器当地址的内存操作数 | `mov qword [rsp], 0x1111` |
| `sub rsp, 16` | 在栈上"开"16 字节（栈向低地址增长） | `sub rsp, 16` |
| `add rsp, 16` | 把栈"还"回去，必须和 `sub` 成对 | `add rsp, 16` |
| `byte` / `word` / `dword` / `qword` | 明确告诉汇编器要操作几个字节 | `mov byte [rel b], 1` |
| `nm` | 列出符号和地址；大写 = 全局，小写 = 局部 | `nm -n mem` |
| `readelf -S` | 列出所有段的名字、地址、类型 | `readelf -S mem` |
| `objdump -d -M intel` | 反汇编，`-M intel` 用 Intel 语法 | `objdump -d -M intel mem` |

## 三、示例源码逐段讲解

### 3.1 regs.asm —— 寄存器宽度演示

```asm
; ===========================================================================
; regs.asm —— 第 02 课：通用寄存器的宽度（64/32/16/8 位别名）
;
; 这个程序演示三件事：
;   1. rax / eax / ax / al / ah 指的是同一个物理寄存器，只是"窗口"大小不同
;   2. 写 32 位（eax）会自动把高 32 位清零；写 16/8 位（ax/al/ah）不会
;   3. movzx（零扩展）与 movsx（符号扩展）的区别
;
; 构建/运行：
;   make && ./regs
; ===========================================================================

default rel

section .data
    banner      db  "=== 第 02 课：寄存器宽度演示 ===", 10
    banner_len  equ $ - banner

    s1      db  "1) mov rax, 0x1122334455667788          -> rax = "
    s1_len  equ $ - s1
    s2      db  "2) 再 mov ax, 0xaabb（只动低 16 位）    -> rax = "
    s2_len  equ $ - s2
    s3      db  "3) 重来再 mov al, 0xcc（只动低 8 位）   -> rax = "
    s3_len  equ $ - s3
    s4      db  "4) 重来 mov eax, 0xdeadbeef（清高 32）  -> rax = "
    s4_len  equ $ - s4
    s5      db  "5) 接上一步 mov ah, 0x77（第 2 字节）   -> rax = "
    s5_len  equ $ - s5
    s6a     db  "6) rax = -1，当有符号数看               -> "
    s6a_len equ $ - s6a
    s6b     db  "   rax = -1，当无符号数看               -> "
    s6b_len equ $ - s6b
    s7a     db  "7) mov al,0xFF 后 movzx rax,al          -> "
    s7a_len equ $ - s7a
    s7b     db  "   mov al,0xFF 后 movsx rax,al          -> "
    s7b_len equ $ - s7b

section .text
    global _start
    %include "io.inc"

_start:
    ; ---------------- 标题 ----------------
    lea     rsi, [rel banner]
    mov     rdx, banner_len
    call    io_print

    ; ---------------- 1. 64 位写入 ----------------
    lea     rsi, [rel s1]
    mov     rdx, s1_len
    call    io_print                    ; 先输出说明文字
    mov     rax, 0x1122334455667788      ; 64 位立即数（NASM 会用 movabs 编码）
    mov     rdi, rax                    ; io_print_hex 的参数在 rdi
    call    io_print_hex                ; 0x1122334455667788
    call    io_newline

    ; ---------------- 2. 只写低 16 位 ----------------
    lea     rsi, [rel s2]
    mov     rdx, s2_len
    call    io_print

    mov     rax, 0x1122334455667788      ; 先恢复初值
    mov     ax, 0xaabb                  ; 只改最低 16 位，高 48 位不动
    mov     rdi, rax
    call    io_print_hex                ; 0x112233445566aabb
    call    io_newline

    ; ---------------- 3. 只写低 8 位 ----------------
    lea     rsi, [rel s3]
    mov     rdx, s3_len
    call    io_print

    mov     rax, 0x1122334455667788
    mov     al, 0xcc                    ; 只改最低 8 位
    mov     rdi, rax
    call    io_print_hex                ; 0x11223344556677cc
    call    io_newline

    ; ---------------- 4. 写 32 位会清零高 32 位 ----------------
    lea     rsi, [rel s4]
    mov     rdx, s4_len
    call    io_print

    mov     rax, 0x1122334455667788
    mov     eax, 0xdeadbeef             ; 写 eax ⇒ rax 的高 32 位自动变成 0
    mov     rdi, rax
    call    io_print_hex                ; 0xdeadbeef
    call    io_newline

    ; ---------------- 5. ah 是第 2 个字节 ----------------
    lea     rsi, [rel s5]
    mov     rdx, s5_len
    call    io_print

    mov     rax, 0x1122334455667788
    mov     eax, 0xdeadbeef
    mov     ah, 0x77                    ; ah = rax 的 bit8..bit15
    mov     rdi, rax
    call    io_print_hex                ; 0xdead77ef
    call    io_newline

    ; ---------------- 6. 同一个位模式，两种解释 ----------------
    lea     rsi, [rel s6a]
    mov     rdx, s6a_len
    call    io_print

    mov     rax, -1                     ; 64 个二进制 1
    mov     rdi, rax
    call    io_print_int                ; 有符号解释：-1
    call    io_newline

    lea     rsi, [rel s6b]
    mov     rdx, s6b_len
    call    io_print

    mov     rax, -1
    mov     rdi, rax
    call    io_print_uint               ; 无符号解释：18446744073709551615
    call    io_newline

    ; ---------------- 7. movzx 与 movsx ----------------
    lea     rsi, [rel s7a]
    mov     rdx, s7a_len
    call    io_print

    mov     rax, 0x1122334455667788
    mov     al, 0xFF                    ; al = 0xFF，rax 其余位还是原来那堆
    movzx   rax, al                     ; 零扩展：高 56 位全部清零
    mov     rdi, rax
    call    io_print_int                ; 255
    call    io_newline

    lea     rsi, [rel s7b]
    mov     rdx, s7b_len
    call    io_print

    mov     rax, 0x1122334455667788
    mov     al, 0xFF
    movsx   rax, al                     ; 符号扩展：0xFF 当成 -1
    mov     rdi, rax
    call    io_print_int                ; -1
    call    io_newline

    ; ---------------- 结束 ----------------
    xor     edi, edi                    ; 退出码 0
    call    io_exit                     ; io_exit 不会返回
```
这个程序把 7 组实验串起来，每一组都是"输出说明文字 → 造一个值 → 把值打印成十六进制"。

**为什么要 `%include "io.inc"`**

```asm
section .text
    global _start
    %include "io.inc"

_start:
```

`io.inc` 是**实现**而不是声明：它里面是 `io_print`、`io_print_hex` 等函数的完整代码。所以：

- 位置有讲究：必须放在 `section .text` 里面，否则那些函数会被塞进数据段；
- 一个程序**只能 include 一次**，include 两次就是同一个标签定义两遍，报 duplicate symbol；
- 它自己会 `%include "syscalls.inc"`，你不用重复写。

**第 1 组：写 64 位**

```asm
    mov     rax, 0x1122334455667788      ; 64 位立即数（NASM 会用 movabs 编码）
    mov     rdi, rax                    ; io_print_hex 的参数在 rdi
    call    io_print_hex                ; 0x1122334455667788
```

`io_print_hex` 的入参是 `rdi`，返回值/结果直接打到 stdout。它只破坏 `rax/rcx/r11`，其余寄存器调用前后不变——这一点后面很有用，因为我们可以拿 `r12`、`r13` 当"保险箱"。

**第 2 组：只写低 16 位**

```asm
    mov     rax, 0x1122334455667788      ; 先恢复初值
    mov     ax, 0xaabb                  ; 只改最低 16 位，高 48 位不动
```

结果 `rax = 0x112233445566aabb`：高 48 位还是原来的 `0x112233445566`。所以 `ax` 是个"只改局部"的窗口。

**第 3 组：只写低 8 位**

```asm
    mov     rax, 0x1122334455667788
    mov     al, 0xcc                    ; 只改最低 8 位
```

结果 `0x11223344556677cc`。同样的道理。

**第 4 组：写 32 位会清零高 32 位**

```asm
    mov     rax, 0x1122334455667788
    mov     eax, 0xdeadbeef             ; 写 eax ⇒ rax 的高 32 位自动变成 0
```

结果 `0xdeadbeef`，高 32 位的 `0x11223344` **消失了**。这是 x86-64 的一条硬规则：**任何对 32 位寄存器的写入都会把对应 64 位寄存器的高 32 位清零**。

这条规则有两个后果：

1. 它是"特性"：`mov eax, 1` 就能安全地把整个 `rax` 设成 1，机器码还比 `mov rax, 1` 短。
2. 它是"陷阱"：`inc eax`、`add eax, ebx` 这类操作也会清零高 32 位，别以为只动了低半截。

**第 5 组：`ah` 是第二个字节**

```asm
    mov     rax, 0x1122334455667788
    mov     eax, 0xdeadbeef
    mov     ah, 0x77                    ; ah = rax 的 bit8..bit15
```

`0xdeadbeef` 里 bit8~bit15 是 `0xbe`，换成 `0x77` 之后得到 `0xdead77ef`。这也说明"高 8 位寄存器"（`ah`、`bh`、`ch`、`dh`）用起来是分裂的：它们和 REX 前缀不能共存，现代编译器很少用。

**第 6 组：同一串二进制位，两种解释**

```asm
    mov     rax, -1                     ; 64 个二进制 1
    mov     rdi, rax
    call    io_print_int                ; 有符号解释：-1
    ...
    call    io_print_uint               ; 无符号解释：18446744073709551615
```

寄存器里存的是 64 个 1。**位模式本身没有符号**，是"怎么解释它"决定了它是 -1 还是 18446744073709551615。所以打印时必须挑对函数：`io_print_int`（有符号）还是 `io_print_uint`（无符号）。

**第 7 组：`movzx` 与 `movsx`**

```asm
    mov     rax, 0x1122334455667788
    mov     al, 0xFF                    ; al = 0xFF，rax 其余位还是原来那堆
    movzx   rax, al                     ; 零扩展：高 56 位全部清零 ⇒ 255
    ...
    movsx   rax, al                     ; 符号扩展：0xFF 当成 -1 ⇒ -1
```

`movzx`/`movsx` 都会**整体替换**目标寄存器：先把源取出来，按规则补高位，再整个写回。所以要"把一个小值安全地放大"就必须用它俩，不能靠 `mov al, ...`。

### 3.2 mem.asm —— .data / .bss / 栈

```asm
; ===========================================================================
; mem.asm —— 第 02 课：程序里的三种数据位置
;
;   1) .data  已初始化数据：有初值，初值会写进可执行文件
;   2) .bss   未初始化数据：可执行文件里只记"要多少字节"，加载时被清零
;   3) 栈     运行期的临时空间：sub rsp, N 开出来，add rsp, N 还回去
;
; 构建/运行：
;   make && ./mem
; ===========================================================================

default rel

; ---------------------------------------------------------------------------
; 已初始化数据段
; ---------------------------------------------------------------------------
section .data
    banner      db  "=== 第 02 课：三种数据位置 .data / .bss / 栈 ===", 10
    banner_len  equ $ - banner

    d_val       dq  0x1122334455667788      ; 8 字节，有初值
    d_msg       db  "d_msg：我在 .data，初值已经写进可执行文件", 10
    d_msg_len   equ $ - d_msg

    t1      db  "[.data] d_val 的初值               = "
    t1_len  equ $ - t1
    t2      db  "[.data] d_msg 的内容               : "
    t2_len  equ $ - t2
    t3      db  "[.bss ] b_num 没赋过值，读出来是   = "
    t3_len  equ $ - t3
    t4      db  "[.bss ] 往 b_num 写 0x2a 再读      = "
    t4_len  equ $ - t4
    t5      db  "[.bss ] b_buf[0] 当数字看          = "
    t5_len  equ $ - t5
    t6      db  "[.bss ] b_buf 当字符串看           = "
    t6_len  equ $ - t6
    t7      db  "[栈   ] sub rsp,16 之后 [rsp]      = "
    t7_len  equ $ - t7
    t8      db  "[栈   ] 同一块空间的 [rsp+8]       = "
    t8_len  equ $ - t8
    t9      db  "[栈   ] add rsp,16 后 (备份rsp-rsp)= "
    t9_len  equ $ - t9
    t9_tail db  "   ← 0 表示栈指针已经复原"
    t9_tail_len equ $ - t9_tail

    ta      db  "[地址 ] d_val(.data) = "
    ta_len  equ $ - ta
    tb      db  "   b_num(.bss) = "
    tb_len  equ $ - tb
    tc      db  "   rsp(栈顶) = "
    tc_len  equ $ - tc
    tnote   db  "（地址每次运行都可能不同，这是正常的）", 10
    tnote_len equ $ - tnote

; ---------------------------------------------------------------------------
; 未初始化数据段：只声明"要多少字节"，不占可执行文件的体积
; ---------------------------------------------------------------------------
section .bss
    b_num   resq 1                  ; 8 字节（1 个 qword）
    b_buf   resb 8                  ; 8 字节

section .text
    global _start
    %include "io.inc"

_start:
    lea     rsi, [rel banner]
    mov     rdx, banner_len
    call    io_print

    ; ======================= .data =======================
    lea     rsi, [rel t1]
    mov     rdx, t1_len
    call    io_print
    mov     rdi, [rel d_val]            ; 从 .data 里读 8 字节
    call    io_print_hex
    call    io_newline

    lea     rsi, [rel t2]
    mov     rdx, t2_len
    call    io_print
    lea     rsi, [rel d_msg]
    mov     rdx, d_msg_len
    call    io_print                    ; d_msg 自带换行，不用再补

    ; ======================= .bss ========================
    lea     rsi, [rel t3]
    mov     rdx, t3_len
    call    io_print
    mov     rdi, [rel b_num]            ; 从来没写过，读出来一定是 0
    call    io_print_hex
    call    io_newline

    mov     qword [rel b_num], 0x2a     ; 往 .bss 里写 8 字节
    lea     rsi, [rel t4]
    mov     rdx, t4_len
    call    io_print
    mov     rdi, [rel b_num]
    call    io_print_hex
    call    io_newline

    mov     byte [rel b_buf], 0x41      ; 'A'
    mov     byte [rel b_buf + 1], 0x42  ; 'B'
    mov     byte [rel b_buf + 2], 0     ; 字符串结尾的 0

    lea     rsi, [rel t5]
    mov     rdx, t5_len
    call    io_print
    movzx   rdi, byte [rel b_buf]       ; 只读 1 个字节
    call    io_print_hex                ; 0x41
    call    io_newline

    lea     rsi, [rel t6]
    mov     rdx, t6_len
    call    io_print
    lea     rsi, [rel b_buf]
    mov     edx, 2                      ; 只打印 "AB" 这 2 个字节
    call    io_print
    call    io_newline

    ; ======================= 栈 ==========================
    mov     r12, rsp                    ; 备份 rsp（r12 不会被 io.inc 破坏）
    sub     rsp, 16                     ; 在栈上开 16 字节的临时空间

    mov     qword [rsp], 0x1111         ; 第 1 个 8 字节槽
    mov     qword [rsp + 8], 0x2222     ; 第 2 个 8 字节槽

    lea     rsi, [rel t7]
    mov     rdx, t7_len
    call    io_print
    mov     rdi, [rsp]                  ; 从栈上读回来
    call    io_print_hex                ; 0x1111
    call    io_newline

    lea     rsi, [rel t8]
    mov     rdx, t8_len
    call    io_print
    mov     rdi, [rsp + 8]              ; 也读回来
    call    io_print_hex                ; 0x2222
    call    io_newline

    add     rsp, 16                     ; 把栈还回去（sub/add 必须成对）

    lea     rsi, [rel t9]
    mov     rdx, t9_len
    call    io_print
    mov     rax, r12                    ; 备份的 rsp
    sub     rax, rsp                    ; 减去当前 rsp
    mov     rdi, rax
    call    io_print_hex                ; 差是 0x0 就说明复原了
    lea     rsi, [rel t9_tail]
    mov     rdx, t9_tail_len
    call    io_print
    call    io_newline

    ; ======================= 地址对比 ====================
    lea     rsi, [rel ta]
    mov     rdx, ta_len
    call    io_print
    lea     rdi, [rel d_val]            ; .data 里 d_val 的地址
    call    io_print_hex

    lea     rsi, [rel tb]
    mov     rdx, tb_len
    call    io_print
    lea     rdi, [rel b_num]            ; .bss 里 b_num 的地址
    call    io_print_hex

    lea     rsi, [rel tc]
    mov     rdx, tc_len
    call    io_print
    mov     rdi, rsp                    ; 当前栈顶
    call    io_print_hex
    call    io_newline

    lea     rsi, [rel tnote]
    mov     rdx, tnote_len
    call    io_print

    xor     edi, edi
    call    io_exit
```
**`.data`：有初值的数据**

```asm
section .data
    d_val       dq  0x1122334455667788      ; 8 字节，有初值
    d_msg       db  "d_msg：我在 .data，初值已经写进可执行文件", 10
```

`.data` 里的初值会原样写进可执行文件。程序一加载，这块内存就已经是初值了。读取方式是：

```asm
    mov     rdi, [rel d_val]            ; 从 .data 里读 8 字节
```

注意有方括号：这是"去地址取值"。因为 `d_val` 是用 `dq` 定义的 8 字节，目标又是 64 位寄存器 `rdi`，汇编器知道该读 8 字节，不用写尺寸。

**`.bss`：没有初值的数据**

```asm
section .bss
    b_num   resq 1                  ; 8 字节（1 个 qword）
    b_buf   resb 8                  ; 8 字节
```

`resq`/`resb` 只是"预留空间"，不给初值。这样的段叫做 `.bss`，它在可执行文件里**不占字节**（`readelf -S` 里类型是 `NOBITS`），只在程序头里记一句"加载时给我留这么多，并且清零"。所以：

```asm
    mov     rdi, [rel b_num]            ; 从来没写过，读出来一定是 0
```

读出 `0x0` 是**语言/加载器保证的**，不是碰巧。C 语言里全局变量默认是 0，也是同一个机制。

往 `.bss` 写必须写清楚尺寸，因为汇编器无从推断：

```asm
    mov     qword [rel b_num], 0x2a     ; 往 .bss 里写 8 字节
    mov     byte [rel b_buf], 0x41      ; 'A'
    mov     byte [rel b_buf + 1], 0x42  ; 'B'
    mov     byte [rel b_buf + 2], 0     ; 字符串结尾的 0
```

**栈：运行期临时空间**

```asm
    mov     r12, rsp                    ; 备份 rsp（r12 不会被 io.inc 破坏）
    sub     rsp, 16                     ; 在栈上开 16 字节的临时空间

    mov     qword [rsp], 0x1111         ; 第 1 个 8 字节槽
    mov     qword [rsp + 8], 0x2222     ; 第 2 个 8 字节槽
```

栈向**低地址**增长。`sub rsp, 16` 之后，`rsp` 变小了，`[rsp]` 和 `[rsp+8]` 这 16 个字节就归你用了。用完必须还回去：

```asm
    add     rsp, 16                     ; 把栈还回去（sub/add 必须成对）

    mov     rax, r12                    ; 备份的 rsp
    sub     rax, rsp                    ; 减去当前 rsp
```

程序用"备份的 rsp 减去当前 rsp"来验证是否复原：差是 `0x0` 就说明栈指针回到原位。这比打印 rsp 本身好，因为 rsp 的具体数值每次运行都不一样（栈地址受地址空间随机化影响），但"差值为 0"是恒定的。

为什么选 `r12` 来备份？因为 `io.inc` 承诺只破坏 `rax/rcx/r11`，`r12` 是安全的。如果改用 `rax` 备份，中间随便一次 `call io_print` 都会把它冲掉——这是新手最常犯的一类错误。

**地址对比**

```asm
    lea     rdi, [rel d_val]            ; .data 里 d_val 的地址
    call    io_print_hex
    ...
    lea     rdi, [rel b_num]            ; .bss 里 b_num 的地址
    call    io_print_hex
    ...
    mov     rdi, rsp                    ; 当前栈顶
    call    io_print_hex
```

这三个地址一起看，就能建立"内存地图"的概念：

```text
高地址  0x7fff??????????   ← rsp 栈顶（每次运行都不同）
        ...
        0x402294  b_buf   （.bss，8 字节）
        0x40228c  b_num   （.bss，8 字节）
        0x40203b  d_val   （.data）
        0x402000  .data 段起点（banner、各种标签字符串排在 d_val 前面）
        0x401171  _start
        0x401000  .text 段起点（io.inc 的函数排在 _start 前面）
低地址
```

`.data` 和 `.bss` 都在 0x400000 附近，是加载时就定死的（本课用 `ld` 直接链接，生成的是非 PIE 可执行文件）；栈在 0x7fff 开头的很高地址上，而且每次运行都变。

## 四、编译与运行

```bash
cd lesson02
make
./regs
./mem
```

`regs` 的真实输出（共 10 行，全是确定值）：

```text
=== 第 02 课：寄存器宽度演示 ===
1) mov rax, 0x1122334455667788          -> rax = 0x1122334455667788
2) 再 mov ax, 0xaabb（只动低 16 位）    -> rax = 0x112233445566aabb
3) 重来再 mov al, 0xcc（只动低 8 位）   -> rax = 0x11223344556677cc
4) 重来 mov eax, 0xdeadbeef（清高 32）  -> rax = 0xdeadbeef
5) 接上一步 mov ah, 0x77（第 2 字节）   -> rax = 0xdead77ef
6) rax = -1，当有符号数看               -> -1
   rax = -1，当无符号数看               -> 18446744073709551615
7) mov al,0xFF 后 movzx rax,al          -> 255
   mov al,0xFF 后 movsx rax,al          -> -1
```

`mem` 的真实输出（共 12 行）：

```text
=== 第 02 课：三种数据位置 .data / .bss / 栈 ===
[.data] d_val 的初值               = 0x1122334455667788
[.data] d_msg 的内容               : d_msg：我在 .data，初值已经写进可执行文件
[.bss ] b_num 没赋过值，读出来是   = 0x0
[.bss ] 往 b_num 写 0x2a 再读      = 0x2a
[.bss ] b_buf[0] 当数字看          = 0x41
[.bss ] b_buf 当字符串看           = AB
[栈   ] sub rsp,16 之后 [rsp]      = 0x1111
[栈   ] 同一块空间的 [rsp+8]       = 0x2222
[栈   ] add rsp,16 后 (备份rsp-rsp)= 0x0   ← 0 表示栈指针已经复原
[地址 ] d_val(.data) = 0x40203b   b_num(.bss) = 0x40228c   rsp(栈顶) = 0x7fff13155100
（地址每次运行都可能不同，这是正常的）
```

倒数第二行的三个地址要这么看：`d_val`、`b_num` 在**非 PIE** 可执行文件里是固定地址（本次是 `0x40203b`、`0x40228c`），而 `rsp` 每次运行都会变（栈有随机化）。本课 `test.sh` 的做法就是：先把这一行用 `grep -vF` 滤掉，再对剩下的 11 行做整段比对，另外单独检查这一行里三个 `0x` 开头的地址是否都在。

### 4.1 用 objdump / readelf / nm 看段和符号

```bash
readelf -S mem
nm -n mem | grep -E ' (_start|d_val|b_num|b_buf)$'
objdump -d -M intel mem | head -40
size mem
file mem
```

`readelf -S mem` 的关键三行（已实测）：

```text
  [ 1] .text             PROGBITS         0000000000401000  00001000
  [ 2] .data             PROGBITS         0000000000402000  00002000
  [ 3] .bss              NOBITS           000000000040228c  0000228c
```

- `.text` 从 `0x401000` 开始：代码。
- `.data` 从 `0x402000` 开始：有初值的数据，类型 `PROGBITS`（在文件里真的有内容）。
- `.bss` 从 `0x40228c` 开始：类型是 `NOBITS`——它在文件里**没有内容**，只占一个地址范围。你可以对比偏移量：`.bss` 的偏移 `0x228c` 和下一个段的偏移一样，说明它没占用任何文件字节。

`nm -n mem`（`-n` 按地址排序）里挑几行：

```text
0000000000401171 T _start
000000000040203b d d_val
000000000040228c b b_num
0000000000402294 b b_buf
```

`nm` 输出的第二个字母就是段：大写 `T` = 全局代码（`.text`），小写 `d` = 局部 `.data`，小写 `b` = 局部 `.bss`。另外注意 `d_val` 的地址是 `0x40203b` 而不是段首 `0x402000`——因为 `banner` 和一大堆标签字符串都定义在它前面，**符号的顺序就是你写代码的顺序**。

`objdump -d -M intel mem` 会看到 `io.inc` 的全部函数也反汇编出来了，它们排在 `_start` **前面**，因为 `%include "io.inc"` 写在 `_start:` 之前。这正是"include 的位置会决定代码顺序"的实证。

### 4.2 gdb 初探

Debian 13 默认**不带 gdb**，先装：

```bash
sudo apt install gdb
```

因为 Makefile 里已经带了 `-g -F dwarf`，可执行文件里有调试信息，gdb 能直接认标签、认源码行号：

```bash
gdb ./mem
```

进入 gdb 后依次输入：

```text
(gdb) break _start          # 在 _start 处下断点
(gdb) run                   # 跑起来，会停在断点
(gdb) info registers rip rsp rbp rax    # 看几个关键寄存器
(gdb) x/8xb &d_val          # 以十六进制看 d_val 那 8 个字节
(gdb) x/s &d_msg            # 把 d_msg 当字符串看
(gdb) disassemble _start    # 反汇编 _start
(gdb) stepi                 # 单步执行一条机器指令
(gdb) continue              # 继续跑完
(gdb) quit
```

调试汇编要用 `stepi`/`nexti`（单步一条指令）而不是 `step`/`next`（单步一行源码）。第 14 课会把调试技巧系统讲一遍；本课只要能在断点处把寄存器和内存"看穿"就够用了。

## 五、动手练习

1. 把 `regs.asm` 第 4 组改成 `mov ax, 0x1234` 之后紧跟 `mov eax, 0xdeadbeef`，预测第 5 组的输出会是多少，然后运行验证。

2. 在 `regs.asm` 里加一组实验：`mov rax, 0x1122334455667788` 然后 `inc eax`，观察高 32 位有没有被清零，把结论写下来。

3. 修改 `mem.asm`，在栈上开 32 字节而不是 16 字节，写入 `[rsp]`、`[rsp+8]`、`[rsp+16]`、`[rsp+24]` 四个值并全部读出来，最后仍然验证 `备份rsp - rsp == 0`。

4. 在 `mem.asm` 的 `.bss` 里加一个 `resb 16` 的缓冲区，往里面写入你自己的名字（ASCII 字节，记得补结尾 0），然后用 `lea rsi, [rel 名字]` + `mov edx, 长度` + `call io_print` 把它打印出来。

5. **只给思路**：把 `mem.asm` 里备份 `rsp` 用的 `r12` 改成 `rax`，重新编译运行，观察"复原检查"那一行会不会变成非 0，然后解释为什么。（提示：`call io_print` 内部会把 `rax` 当成系统调用号用。）

6. **只给思路**：用 `nm` 找出 `regs` 里 `io_print_hex` 的地址和 `_start` 的地址，比较大小，解释谁在前、为什么。（提示：和 `%include "io.inc"` 的位置有关。）

## 六、常见坑

1. **忘了 `default rel` / 不写 `[rel 标签]`**。64 位下 `mov rdi, [d_val]` 会被当成 32 位绝对地址寻址，链接时可能报 `R_X86_64_32S against '.data' can not be used when making a PIE object`。统一写 `[rel 标签]`。

2. **手写 `mov dl, 1` 而不写 `mov edx, 1`**。`dl` 只改最低 8 位。想设置长度、循环计数这类 64 位量时，一律写 32 位寄存器名：`mov edx, 1`，它会顺带把高 32 位清零。

3. **以为 `mov ax, ...` / `mov al, ...` 会清零其余位**。不会。只有 32 位写入才会清零高 32 位；16 位和 8 位写入是"局部修改"。

4. **忘了给内存操作数标尺寸**。`mov [rel b_num], 0x2a` 会让 NASM 报 `operation size not specified`。因为 `b_num` 是 `resq`（8 字节），而立即数可大可小，汇编器无从判断，必须写 `mov qword [rel b_num], 0x2a`。

5. **`sub rsp, N` 忘了 `add rsp, N`**。栈指针一路往低地址跑，函数返回地址、甚至别的数据都会被踩坏，症状是"跑着跑着莫名奇异地崩了"。开栈和还栈要成对出现。

6. **没意识到 `call` 会动栈**。`call` 会把 8 字节返回地址压到 `rsp - 8`。所以 `mov [rsp], ...` 之后如果插入了一次 `call`，那块内存**仍然安全**（返回地址在更低的地方），但如果你写的是 `[rsp - 8]`，就会被覆盖。

7. **拿 `rax` 当"保险箱"**。`rax/rcx/rdx/rsi/rdi/r8-r11` 都是调用者保存（caller-saved），随便一次 `call io_print*` 就会改掉（`io.inc` 明确会改 `rax/rcx/r11`，而 `rcx`/`r11` 是 `syscall` 破坏的）。要跨调用保存数据，用 `rbx/rbp/r12-r15`。

8. **`io.inc` include 两次**。它是实现不是声明，include 两次会报函数重复定义。本教程的规定是：写在 `section .text` 内、`global _start` 之后、`_start:` 之前，且只写一次。

9. **`.bss` 里读到了 0 就以为"正好是 0"**。要记住这是加载器清零的结果，是规范保证的；如果你先写了别的值再读，读到的就是那个值。

10. **算错了 `io_print` 的参数**。它的签名是 `io_print(rsi=地址, rdx=长度)`，**不是** 0 结尾字符串。给 `rdx` 传 0 会输出 0 字节（不会报错，静默什么都不打），传大了会打出一堆垃圾。`io_print_hex` 则是只打有效数字、不补前导零，所以 0 打印出来是 `0x0`。

11. **预告一个后面会踩的坑**：`syscall` 的第 4 个参数放在 `r10`，不是 `rcx`（C 函数调用才用 `rcx`）。现在记住，第 09 课读写文件时会用到。

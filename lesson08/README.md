# 第 08 课：字符串与数字互转

## 本课目标

* 手写「整数 → 十进制字符串」：用 `div` 反复除 10 取余，理解 `printf("%d")` 背后的过程；
* 手写「十进制字符串 → 整数」：`atoi` 的完整逻辑，包括正负号、非法字符、溢出、空串；
* 学会用「栈上的临时缓冲区」和「.bss 里的缓冲区」两种放字符串的办法；
* 掌握 `div` / `imul` 的用法和必须清零 `rdx` 的原因；
* 能自己判断一次运算有没有溢出（而不是靠猜）。

## 新概念 / 新指令

| 指令 / 概念 | 一句话说明 | 小例子 |
|---|---|---|
| `div 寄存器` | 无符号除法：`rax ÷ 源`，商回 `rax`，余数进 `rdx` | `xor rdx,rdx` + `div rbx` |
| 除法前清零 `rdx` | `div` 的被除数是 `rdx:rax`，不清零结果就是错的 | `xor rdx, rdx` |
| `imul rax, rbx, 10` | 三操作数乘法：`rax = rbx * 10` | `imul r12, r12, 10` |
| `add dl, '0'` | 数字 0~9 转成字符 `'0'`~`'9'`（ASCII 48） | `add dl, '0'` |
| `sub al, '0'` | 字符转回数字 | `sub al, al, '0'` |
| `movzx eax, byte [p]` | 取一个字节并零扩展到 32 位（避免高位垃圾） | `movzx eax, byte [rbx]` |
| `test al, al` / `jz` | 判断是不是字符串结束符 NUL | `test al,al` + `jz .end` |
| `cmp al, 9` / `ja` | 无符号比较，用来判断「不是数字」 | `cmp al, 9` + `ja .bad` |
| 栈上缓冲区 | `sub rsp, 32` 借一块空间当草稿纸，用完 `add rsp, 32` | `lea r12, [rsp+32]` |
| `.bss` 缓冲区 | `resb 32` 定义不占文件体积的全局缓冲区 | `decbuf resb 32` |
| 溢出检测（乘法） | 乘完再除回去，和原值不等就是溢出了 | `div r10` + `cmp rax, rcx` |
| 溢出检测（加法） | 无符号加法进位标志 `jc` | `add r12, rcx` + `jc .overflow` |
| 状态码 | 用第二个返回值告诉调用者「成功 / 非法 / 溢出」 | `rdx = 0/1/2/3/4` |
| `movzx ecx, ah` | 取 8 位寄存器的高半部分（但别在 `div` 前后用 `ah`！） | 见「常见坑」 |

## 示例 1：num2str.asm —— 整数转字符串

### 完整源码

```asm
; ===========================================================================
; num2str.asm —— 第 08 课示例 1：整数 → 十进制字符串（自己动手写）
;
; 编译（在 lesson08 目录下）：
;   make
; 运行：
;   ./num2str
;
; 本程序故意【不调用 io_print_int / io_print_uint】，
; 而是自己用「除 10 取余」把数字一位一位算出来，
; 看看 printf("%d") 背后到底发生了什么。
;
; 核心难点：除 10 先得到的是【最低位】，而我们想从最高位开始打印。
; 两种常见解法：
;   * 缓冲区倒在栈上：sub rsp 借一块栈空间，指针从末尾往前进
;             —— 见 print_uint_v1
;   * 缓冲区放在 .bss：同上，只是固定一块全局内存，还能把字符串返回给调用者
;             —— 见 u64_to_dec
; ===========================================================================

section .data
    title       db "=== 整数 -> 十进制字符串（除法 + 取余）==="
    title_len   equ $ - title

    l_v1        db "--- v1：栈上开缓冲区，从末尾往前填 ---"
    l_v1_len    equ $ - l_v1

    l_v1_a      db "print_uint_v1(0)                    = "
    l_v1_a_len  equ $ - l_v1_a

    l_v1_b      db "print_uint_v1(7)                    = "
    l_v1_b_len  equ $ - l_v1_b

    l_v1_c      db "print_uint_v1(12345)                = "
    l_v1_c_len  equ $ - l_v1_c

    l_v1_d      db "print_uint_v1(18446744073709551615) = "
    l_v1_d_len  equ $ - l_v1_d

    l_rev       db "print_uint_reversed(12345)          = "
    l_rev_len   equ $ - l_rev

    l_rev2      db "  <- 反面教材：低位先算出来，直接打印就是倒的"
    l_rev2_len  equ $ - l_rev2

    l_trace     db "--- 12345 的除法过程（顺序是反的：先出最低位）---"
    l_trace_len equ $ - l_trace

    l_step      db "  余数(当前最低位) = "
    l_step_len  equ $ - l_step

    l_quot      db "   商 = "
    l_quot_len  equ $ - l_quot

    l_v2        db "--- v2：往缓冲区末尾倒着填，再整体打印 ---"
    l_v2_len    equ $ - l_v2

    l_v2_a      db "u64_to_dec(0)        -> 【"
    l_v2_a_len  equ $ - l_v2_a

    l_v2_b      db "u64_to_dec(12345)    -> 【"
    l_v2_b_len  equ $ - l_v2_b

    l_v2_c      db "u64_to_dec(1000000)  -> 【"
    l_v2_c_len  equ $ - l_v2_c

    l_v2_d      db "u64_to_dec(18446744073709551615) -> 【"
    l_v2_d_len  equ $ - l_v2_d

    l_v2_e      db "u64_to_dec(1) 之后，缓冲区的末尾 12 字节是 ["
    l_v2_e_len  equ $ - l_v2_e

    l_v2_f      db "]，只有最后一个字节被改写 —— 字符串是从末尾往前长的"
    l_v2_f_len  equ $ - l_v2_f

    quote_end   db "】"
    quote_end_len equ $ - quote_end

section .bss
    decbuf      resb 32         ; u64_to_dec 用的缓冲区（最长 20 位，留足）
    dumpbuf     resb 32         ; 演示「从末尾往前长」的缓冲区（同样留足 20 字节）

section .text
    global _start
%include "io.inc"

_start:
    lea rsi, [rel title]
    mov rdx, title_len
    call io_println

    ; ---- v1：压栈法 -----------------------------------------------------
    lea rsi, [rel l_v1]
    mov rdx, l_v1_len
    call io_println

    lea rsi, [rel l_v1_a]
    mov rdx, l_v1_a_len
    call io_print
    xor rdi, rdi                ; 参数 = 0
    call print_uint_v1
    call io_newline

    lea rsi, [rel l_v1_b]
    mov rdx, l_v1_b_len
    call io_print
    mov rdi, 7
    call print_uint_v1
    call io_newline

    lea rsi, [rel l_v1_c]
    mov rdx, l_v1_c_len
    call io_print
    mov rdi, 12345
    call print_uint_v1
    call io_newline

    lea rsi, [rel l_v1_d]
    mov rdx, l_v1_d_len
    call io_print
    mov rdi, -1                 ; 按无符号解释就是 2^64-1
    call print_uint_v1
    call io_newline

    ; ---- 反面教材：先算出来的低位先打印 ---------------------------------
    lea rsi, [rel l_rev]
    mov rdx, l_rev_len
    call io_print
    mov rdi, 12345
    call print_uint_reversed
    lea rsi, [rel l_rev2]
    mov rdx, l_rev2_len
    call io_println

    ; ---- 把除法过程打印出来 ---------------------------------------------
    lea rsi, [rel l_trace]
    mov rdx, l_trace_len
    call io_println
    mov rdi, 12345
    call trace_digits

    ; ---- v2：缓冲区倒着填 ------------------------------------------------
    lea rsi, [rel l_v2]
    mov rdx, l_v2_len
    call io_println

    lea rsi, [rel l_v2_a]
    mov rdx, l_v2_a_len
    call io_print
    xor rdi, rdi
    call print_dec_string
    lea rsi, [rel quote_end]
    mov rdx, quote_end_len
    call io_print
    call io_newline

    lea rsi, [rel l_v2_b]
    mov rdx, l_v2_b_len
    call io_print
    mov rdi, 12345
    call print_dec_string
    lea rsi, [rel quote_end]
    mov rdx, quote_end_len
    call io_print
    call io_newline

    lea rsi, [rel l_v2_c]
    mov rdx, l_v2_c_len
    call io_print
    mov rdi, 1000000
    call print_dec_string
    lea rsi, [rel quote_end]
    mov rdx, quote_end_len
    call io_print
    call io_newline

    lea rsi, [rel l_v2_d]
    mov rdx, l_v2_d_len
    call io_print
    mov rdi, -1
    call print_dec_string
    lea rsi, [rel quote_end]
    mov rdx, quote_end_len
    call io_print
    call io_newline

    ; ---- 演示：字符串从缓冲区末尾往前长 ---------------------------------
    ; 先往「第 8~19 字节」写上 '#'，转换后哪几个字节被改写一目了然。
    ; ⚠ 缓冲区要按 u64_to_dec 的要求给够 20 字节（它在 rsi+20 处收笔），
    ;   这里 dumpbuf 开了 32 字节，我们只看最后 12 字节那一小段。
    lea rdi, [rel dumpbuf + 8]
    mov rcx, 12
    mov al, '#'
.fill:
    mov [rdi], al
    inc rdi
    dec rcx
    jnz .fill

    ; 再转换一个很小的数：它只占用最后 1 个字节
    mov rdi, 1
    lea rsi, [rel dumpbuf]
    call u64_to_dec             ; rsi 会被改成真正的起点（缓冲区末尾-1）

    lea rsi, [rel l_v2_e]
    mov rdx, l_v2_e_len
    call io_print
    lea rsi, [rel dumpbuf + 8]  ; 只把最后那 12 字节原样打出来
    mov rdx, 12
    call io_print
    lea rsi, [rel l_v2_f]
    mov rdx, l_v2_f_len
    call io_println

    xor rdi, rdi
    call io_exit

; ---------------------------------------------------------------------------
; print_uint_v1 —— 自己写十进制输出（栈上开缓冲区，从末尾往前填）
;
;   入参：rdi = 无符号 64 位整数
;   返回：无；直接写到 stdout
;   破坏：rax/rcx/rdx/rsi/rdi/r8-r11；rbx/rbp/r12-r15 已保存
;
;   思路：
;     1. 反复 div 10：商留给下一轮，余数是「当前最低位」；
;     2. 每算出一位就放到缓冲区的【末尾】，然后指针前移一格；
;     3. 算完时指针正好停在最高位上，缓冲区从那里到末尾就是正序字符串。
;
;   缓冲区直接开在被减小的 rsp 上（sub rsp, 32），不额外用 .bss，
;   这是汇编里很常见的写法：rsp 以下的空间没人用，借来当草稿纸最方便。
; ---------------------------------------------------------------------------
print_uint_v1:
    push rbp
    mov rbp, rsp
    push rbx                    ; 被调用者保存：用 rbx 当除数
    push r12                    ; 用 r12 当「从后往前写」的指针
    sub rsp, 32                 ; ⚠ 缓冲区必须在 push 之后再开，否则会
                                ;   和刚保存的 rbx/r12 叠在一起！

    mov rax, rdi                ; rax = 被除数
    mov rbx, 10                 ; 除数（div 的除数不能是立即数）
    lea r12, [rsp + 32]         ; r12 = 缓冲区末尾（rsp+32 是缓冲区之外）

.loop:
    xor rdx, rdx                ; ⚠ div 之前必须把 rdx（被除数高 64 位）清零
    div rbx                     ; rax = rax / 10，rdx = rax % 10
    add dl, '0'                 ; 0..9 -> '0'..'9'
    dec r12                     ; 指针先退一格
    mov [r12], dl               ; 写入这一位
    test rax, rax
    jnz .loop                   ; 商不为 0 就继续

    mov rsi, r12                ; 起点 = 最高位
    lea rdx, [rsp + 32]         ; 终点 = 缓冲区末尾
    sub rdx, r12                ; 长度 = 终点 - 起点
    call io_print

    add rsp, 32
    pop r12
    pop rbx
    leave
    ret

; ---------------------------------------------------------------------------
; print_uint_reversed —— 反面教材：先算出来的低位先打印，结果是倒的
;
;   入参：rdi = 无符号 64 位整数
;   print_uint_reversed(12345) 会打印成 54321。
;   因为除 10 第一次拿到的就是最低位，直接输出自然是从低位到高位。
; ---------------------------------------------------------------------------
print_uint_reversed:
    push rbp
    mov rbp, rsp
    push rbx

    mov rax, rdi
    mov rbx, 10

.loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    push rax                    ; 打印会破坏 rax，先把它存好
    mov rdi, rdx                ; rdx 的低 8 位就是这一位的 ASCII
    call io_putchar
    pop rax
    test rax, rax
    jnz .loop

    pop rbx
    leave
    ret

; ---------------------------------------------------------------------------
; u64_to_dec —— 把 rdi 转成十进制字符串，写进 rsi 指向的缓冲区（倒着填）
;
;   入参：rdi = 无符号 64 位整数
;         rsi = 缓冲区首地址（必须至少有 20 字节！）
;   返回：rax = 字符串长度（不含结尾的 0；本函数不写 0）
;         rsi = 字符串真正的起点（可能在缓冲区中间甚至末尾）
;
;   为什么需要 20 字节？u64 最大 18446744073709551615，正好 20 位。
;   为什么从后往前填？因为除 10 先得到最低位，而字符串要求最高位在前。
; ---------------------------------------------------------------------------
u64_to_dec:
    push rbx                    ; 被调用者保存：本函数要用 rbx/r12
    push r12

    mov rax, rdi                ; 被除数
    mov rbx, 10                 ; 除数
    lea r12, [rsi + 20]         ; r12 = 缓冲区末尾（指向最后一个字节之后）

.digits:
    xor rdx, rdx                ; ⚠ 每次 div 前都要清零
    div rbx
    add dl, '0'
    dec r12                     ; 先退一格
    mov [r12], dl               ; 再写入这一位
    test rax, rax
    jnz .digits

    ; 长度 = 缓冲区末尾(rsi+20) - 起点(r12)
    lea rax, [rsi + 20]
    sub rax, r12
    mov rsi, r12                ; rsi = 真正的起点

    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; print_dec_string —— 把 rdi 转成十进制字符串并打印（调用 u64_to_dec）
;
;   入参：rdi = 无符号 64 位整数
; ---------------------------------------------------------------------------
print_dec_string:
    lea rsi, [rel decbuf]       ; 传缓冲区首地址
    call u64_to_dec
    mov rdx, rax                ; rdx = 长度（rsi 已经是 u64_to_dec 返回的起点）
    call io_print
    ret

; ---------------------------------------------------------------------------
; trace_digits —— 把「除 10 取余」的每一步打出来（演示用）
;
;   入参：rdi = 数值
; ---------------------------------------------------------------------------
trace_digits:
    push rbp
    mov rbp, rsp
    push rbx
    mov rax, rdi
    mov rbx, 10

.loop:
    xor rdx, rdx
    div rbx                     ; rdx = 余数（当前最低位），rax = 商
    push rax                    ; 打印会破坏 rax/rdx，先存到栈上
    push rdx

    lea rsi, [rel l_step]
    mov rdx, l_step_len
    call io_print
    mov rdi, [rsp]              ; 余数
    call io_print_int

    lea rsi, [rel l_quot]
    mov rdx, l_quot_len
    call io_print
    mov rdi, [rsp + 8]          ; 商
    call io_print_int
    call io_newline

    pop rdx                     ; 取回余数（后面不用了，只为平衡栈）
    pop rax                     ; 取回商
    test rax, rax
    jnz .loop

    pop rbx
    leave
    ret
```

### 逐段讲解

**1）核心只有四行**

```asm
; ===========================================================================
; str2num.asm —— 第 08 课示例 2：十进制字符串 → 整数（atoi 的原理）
;
; 编译（在 lesson08 目录下）：
;   make
; 运行：
;   ./str2num
;   printf '  12345\n' | ./str2num      # 从标准输入读一行再转换
;
; 本程序要处理 atoi 的四个老大难问题：
;   1. 正负号：'+' / '-' 只能出现在开头，'-' 还要照顾好 INT64_MIN；
;   2. 非法字符：遇到不是 '0'..'9' 的字节，要分得清它是「字符串结束符」
;      还是「垃圾字符」；
;   3. 溢出：乘 10 或加本位之后超出 [INT64_MIN, INT64_MAX]；
;   4. 空串 / 只有符号：不能当成 0 蒙混过关。
;
; 解析核心：value = value * 10 + (c - '0')
; 溢出判断用了一个很实用的技巧（见 parse_str 里的注释）：
;   如果 value*10 溢出，那么 (value*10 / 10) 就不再等于原来的 value。
; ===========================================================================

section .data
    ; ---- 提示文字 -------------------------------------------------------
    title      db "=== 字符串 -> 整数（atoi 手写实现）==="
    title_len  equ $ - title

    l_head     db "输入                    值(十进制)                值(十六进制)          位数  状态"
    l_head_len equ $ - l_head

    ; ---- 内建测试用例（每个都以 NUL 结尾）-------------------------------
    t1         db "12345", 0
    t2         db "-987", 0
    t3         db "+42", 0
    t4         db "0000", 0
    t5         db "9223372036854775807", 0        ; INT64_MAX
    t6         db "-9223372036854775808", 0       ; INT64_MIN
    t7         db "9223372036854775808", 0        ; 比 INT64_MAX 大 1：溢出
    t8         db "99999999999999999999", 0       ; 远远溢出
    t9         db 0                                ; 真正的空串
    t10        db "-", 0                          ; 只有符号
    t11        db "12a3", 0                       ; 中间夹了非法字符

    ; 指针表：dq 存的是各字符串的地址，配合循环遍历
    table      dq t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11
    table_cnt  equ ($ - table) / 8

    ; 状态码对应的文字
    txt_ok        db "OK"
    txt_ok_len    equ $ - txt_ok
    txt_bad        db "非法字符"
    txt_bad_len    equ $ - txt_bad
    txt_ovf        db "溢出"
    txt_ovf_len    equ $ - txt_ovf
    txt_nul        db "空指针"
    txt_nul_len    equ $ - txt_nul
    txt_emp        db "空串/只有符号"
    txt_emp_len    equ $ - txt_emp

    ; ---- 从标准输入读的那个演示 -----------------------------------------
    l_stdin    db "--- 从标准输入读一行（可用 printf '...' | ./str2num 喂进去）---"
    l_stdin_len equ $ - l_stdin

    l_prompt   db "读出（已去掉换行）= "
    l_prompt_len equ $ - l_prompt

    l_eof      db "读到 0 字节（EOF），没有输入可解析，直接退出。"
    l_eof_len  equ $ - l_eof

    empty_mark db "(空串)"
    empty_mark_len equ $ - empty_mark

section .bss
    inbuf      resb 64          ; 读标准输入用的缓冲区

section .text
    global _start
%include "io.inc"

_start:
    lea rsi, [rel title]
    mov rdx, title_len
    call io_println

    lea rsi, [rel l_head]
    mov rdx, l_head_len
    call io_println

    ; ---- 遍历内建用例表 --------------------------------------------------
    lea rbx, [rel table]        ; rbx 指向指针表（rbx 被调用者保存）
    mov rbp, table_cnt          ; rbp 当循环计数器（同样被调用者保存）

.next:
    mov rdi, [rbx]              ; rdi = 当前测试字符串
    call show_one
    add rbx, 8
    dec rbp
    jnz .next

    call io_newline

    ; ---- 从标准输入读一行 ------------------------------------------------
    lea rsi, [rel l_stdin]
    mov rdx, l_stdin_len
    call io_println

    ; read(0, inbuf, 64)：从标准输入最多读 64 字节
    xor edi, edi                ; fd = STDIN
    lea rsi, [rel inbuf]
    mov edx, 64
    mov rax, SYS_read
    syscall                     ; 返回值在 rax（负数表示出错）

    test rax, rax
    jle .eof                    ; 0 = EOF，负数 = 错误，都直接收工

    ; ---- 手工去掉结尾的 '\n' 和 '\r' ------------------------------------
    mov rcx, rax                ; rcx = 读到的字节数
    lea rdi, [rel inbuf]
.strip:
    test rcx, rcx
    jz .stripped
    mov al, [rdi + rcx - 1]     ; 看最后一个字节
    cmp al, LF
    je .cut
    cmp al, 13                  ; '\r'（Windows 换行）
    je .cut
    jmp .stripped
.cut:
    dec rcx
    jmp .strip
.stripped:
    mov byte [rdi + rcx], 0     ; 打上字符串结束符

    lea rsi, [rel l_prompt]
    mov rdx, l_prompt_len
    call io_print
    lea rsi, [rel inbuf]
    mov rdx, rcx                ; 长度 = 去掉换行后的字节数
    call io_println

    lea rdi, [rel inbuf]
    call show_one

    xor rdi, rdi
    call io_exit

.eof:
    lea rsi, [rel l_eof]
    mov rdx, l_eof_len
    call io_println
    xor rdi, rdi
    call io_exit

; ---------------------------------------------------------------------------
; show_one —— 解析并打印一个用例：输入串、值、十六进制、位数、状态
;
;   入参：rdi = 指向 NUL 结尾字符串的指针
;   如果字符串是空串（连符号都没有），终端里什么都看不见，
;   所以显示的时候换成 "(空串)" 字样，解析时用的还是那个空串本身。
; ---------------------------------------------------------------------------
show_one:
    push rbx                    ; 要用 rbx/r12-r15 存跨调用的值，先保存
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                ; rbx = 要解析的字符串

    cmp byte [rbx], 0           ; 真·空串？
    jne .parse
    lea rdi, [rel empty_mark + empty_mark_len]  ; 解析用末尾的 NUL
    mov rbx, rdi
    sub rbx, empty_mark_len     ; 但显示的时候换成 "(空串)" 字样
.parse:
    call parse_str
    mov r12, rax                ; r12 = 值
    mov r13, rdx                ; r13 = 状态码
    mov r14, rcx                ; r14 = 位数（要留到第四列）

    ; ---- 第一列：输入字符串，不足 20 列补空格 ---------------------------
    mov rsi, rbx
    call cstr_len
    mov r15, rax                ; r15 = 这一列的长度（r14 要留着装位数）
    mov rsi, rbx
    mov rdx, r15
    call io_print
    mov rdi, 21                 ; 第一列固定 21 列
    sub rdi, r15                ; 还要补几个空格
    call print_spaces

    ; ---- 第二列：值（十进制，末尾补两格）-------------------------------
    mov rdi, r12
    call print_int64
    mov edi, ' '
    call io_putchar
    call io_putchar
    call io_putchar             ; 多补几格，让 19 位数也留出间距

    ; ---- 第三列：十六进制 ------------------------------------------------
    mov rdi, r12
    call io_print_hex
    mov edi, ' '
    call io_putchar
    call io_putchar
    call io_putchar
    call io_putchar

    ; ---- 第四列：位数 ----------------------------------------------------
    mov rdi, r14
    call print_u64
    mov edi, ' '
    call io_putchar
    mov edi, ' '
    call io_putchar

    ; ---- 第五列：状态 ----------------------------------------------------
    mov rdx, r13
    call print_status

    call io_newline

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; parse_str —— 把 rdi 指向的十进制字符串转成 64 位有符号整数
;
;   入参：rdi = 指向 NUL 结尾字符串的指针
;   返回：rax = 解析出的数值
;         rdx = 状态码：0 成功 / 1 非法字符 / 2 溢出 / 3 空指针 / 4 空串或只有符号
;         rcx = 有效数字位数（不含 '+'/'-'；状态不为 0 时无意义）
;
;   寄存器分工（故意全用「被调用者保存」寄存器，因为中途要调 io_putchar）：
;         rbx = 扫描指针
;         r12 = 累加器 value
;         r13 = 符号标志（0 = 正，1 = 负）
;         r14 = 常量 '0'
;         r15 = 第一个数字的位置（最后用它算位数）
;
;   溢出检测两处：
;     * value*10 溢出 —— 乘完再除以 10，回不到原来的 value；
;     * + digit 溢出  —— 64 位无符号加法进位（jc）。
;   最后再按符号和 INT64_MAX / INT64_MIN 比较。
; ---------------------------------------------------------------------------
parse_str:
    push rbx
    push r12
    push r13
    push r14
    push r15                    ; 5 个 push 是奇数：进函数时 rsp ≡ 8 (mod 16)，
                                ; 5*8 = 40 之后 rsp ≡ 0 (mod 16)，
                                ; 函数体里 call 就满足「rsp 是 16 的倍数」

    ; ---- 0. 空指针检查（防止调用者忘了判空） ----------------------------
    test rdi, rdi
    jnz .have_ptr
    xor eax, eax
    mov rdx, 3
    xor ecx, ecx
    jmp .ret

.have_ptr:
    mov rbx, rdi                ; 扫描指针
    xor r12, r12                ; value = 0
    xor r13, r13                ; 符号 = 正

    ; ---- 1. 跳过开头的空白字符（空格 / TAB / 回车 / 换行）--------------
    ; 「  -12345」这种输入很常见（从终端读进来时尤其如此），
    ; 真正的 atoi 也是这么处理的
.skip_ws:
    mov al, [rbx]
    cmp al, ' '
    je .ws
    cmp al, TAB
    je .ws
    cmp al, 13
    je .ws
    cmp al, LF
    jne .sign
.ws:
    inc rbx
    jmp .skip_ws

    ; ---- 2. 可选的正负号（只认第一个非空白字符）------------------------
.sign:
    mov al, [rbx]
    cmp al, '-'
    jne .chk_plus
    mov r13, 1
    inc rbx
    jmp .digits
.chk_plus:
    cmp al, '+'
    jne .digits
    inc rbx

.digits:
    mov r15, rbx                ; 记下第一个数字的位置
    mov r14b, '0'               ; 常量 '0' 暂放 r14 低 8 位（本函数没别人用 r14）

.loop:
    movzx eax, byte [rbx]       ; 读一个字节（movzx：高位清零）
    test al, al
    jz .end                     ; NUL：字符串正常结束
    sub al, r14b                ; al = c - '0'
    cmp al, 9
    ja .bad_char                ; 不是 '0'..'9'

    ; --- value = value * 10 + digit，带两处溢出检查 ---------------------
    ; ⚠ 不要把 digit 暂存在 ah 里！div 会写 rax，把 ah 一起冲掉
    ;   （这个坑在 README 里也会讲）。这里用 r8 这个「调用者保存」寄存器。
    movzx r8d, al               ; r8 = digit（下面一直要活着）

    mov rcx, r12                ; rcx = 乘之前的 value
    imul r12, r12, 10           ; r12 *= 10
    mov rax, r12
    xor edx, edx
    mov r9, 10
    div r9                      ; rax = (value*10) / 10
    cmp rax, rcx
    jne .overflow               ; 除不回来 -> 乘 10 时就溢出了

    add r12, r8                 ; value += digit
    jc .overflow                ; 无符号加法进位 -> 溢出

    inc rbx
    jmp .loop

.bad_char:
    mov rdx, 1
    xor eax, eax
    xor ecx, ecx
    jmp .ret

.end:
    mov rcx, rbx
    sub rcx, r15                ; 位数 = 扫描位置 - 第一个数字的位置
    test rcx, rcx
    jz .empty                   ; 一个数字都没读到："", "-", "+"

    test r13, r13
    jnz .neg

    mov rax, 0x7fffffffffffffff ; INT64_MAX
    cmp r12, rax
    ja .overflow
    mov rax, r12
    xor rdx, rdx
    jmp .ret

.neg:
    ; 负数最小可以到 -2^63，即无符号写法 0x8000000000000000
    mov rax, 0x8000000000000000
    cmp r12, rax
    ja .overflow
    mov rax, r12
    neg rax                     ; 取负；0x8000000000000000 取负还是它自己
    xor rdx, rdx
    jmp .ret

.empty:
    xor eax, eax
    mov rdx, 4
    xor ecx, ecx
    jmp .ret

.overflow:
    xor eax, eax
    mov rdx, 2
    xor ecx, ecx
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; 下面是给示例配套的小工具函数
; ---------------------------------------------------------------------------

; str_eq —— 比较 rdi 和 rsi 两个 NUL 结尾字符串
;   返回：rax = 1 相等 / 0 不等
str_eq:
    xor eax, eax
.loop:
    mov cl, [rdi]
    mov dl, [rsi]
    cmp cl, dl
    jne .no
    test cl, cl
    jz .yes                     ; 同时到 NUL：相等
    inc rdi
    inc rsi
    jmp .loop
.yes:
    mov eax, 1
.no:
    ret

; cstr_len —— 求 rsi 指向的 NUL 结尾字符串长度
;   返回：rax = 长度（不含 NUL）
cstr_len:
    xor eax, eax
.loop:
    cmp byte [rsi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; print_spaces —— 打印 rdi 个空格
;   入参：rdi = 个数（<= 0 时什么都不打）
print_spaces:
    push rbx
    mov rbx, rdi
    test rbx, rbx
    jle .done
.loop:
    mov rdi, ' '
    call io_putchar
    dec rbx
    jnz .loop
.done:
    pop rbx
    ret

; print_int64 —— 自己写的有符号十进制输出（负数先打 '-' 再取绝对值）
;   入参：rdi = 有符号整数
print_int64:
    test rdi, rdi
    js .neg
    jmp print_u64
.neg:
    push rdi
    mov rdi, '-'
    call io_putchar
    pop rdi
    mov rax, rdi
    neg rax
    mov rdi, rax
    jmp print_u64

; print_u64 —— 无符号十进制输出（栈上开缓冲区，从末尾往前填）
;   入参：rdi = 无符号整数
print_u64:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32                 ; ⚠ 缓冲区必须在 push 之后开

    mov rax, rdi
    mov rbx, 10
    lea r12, [rsp + 32]         ; 缓冲区末尾
.loop:
    xor rdx, rdx                ; ⚠ div 前清零
    div rbx
    add dl, '0'
    dec r12
    mov [r12], dl
    test rax, rax
    jnz .loop

    mov rsi, r12
    lea rdx, [rsp + 32]
    sub rdx, r12                ; 长度
    call io_print

    add rsp, 32
    pop r12
    pop rbx
    leave
    ret

; print_status —— 打印状态码对应的文字
;   入参：rdx = 状态码
print_status:
    cmp rdx, 0
    je .s0
    cmp rdx, 1
    je .s1
    cmp rdx, 2
    je .s2
    cmp rdx, 3
    je .s3
    lea rsi, [rel txt_emp]
    mov rdx, txt_emp_len
    jmp io_print
.s0:
    lea rsi, [rel txt_ok]
    mov rdx, txt_ok_len
    jmp io_print
.s1:
    lea rsi, [rel txt_bad]
    mov rdx, txt_bad_len
    jmp io_print
.s2:
    lea rsi, [rel txt_ovf]
    mov rdx, txt_ovf_len
    jmp io_print
.s3:
    lea rsi, [rel txt_nul]
    mov rdx, txt_nul_len
    jmp io_print
```

以 `12345` 为例，每轮得到：

| 轮次 | rax（商） | rdx（余数） | 字符 |
|---|---|---|---|
| 1 | 1234 | 5 | `'5'` |
| 2 | 123 | 4 | `'4'` |
| 3 | 12 | 3 | `'3'` |
| 4 | 1 | 2 | `'2'` |
| 5 | 0 | 1 | `'1'` |

**先算出来的是最低位**，这就是本课所有难点的根源：想要「正序」输出，必须把顺序倒过来。

**2）倒过来的两种办法**

* **缓冲区倒着填**（`u64_to_dec`、`print_uint_v1` 用的办法）：先在内存里开一块缓冲区，把指针指向**末尾**，每次算出一位就 `dec` 指针再写入。这样字符在内存里天然是正序的：

  ```text
  缓冲区（32 字节）：[      ...      ][ '1' ][ '2' ][ '3' ][ '4' ][ '5' ][ ... ]
                                    ↑
                               r12 最后停在这里，它就是要打印的起点
  ```

* **压栈再按地址读**：每算出一位就 `push rdx`，全部压完后，最高位在栈的深处、最低位在栈顶。栈是往下长的，所以「地址由低到高」正好是「低位到高位」的反向——要从**最高位的地址**开始连续打印。这招很巧但容易搞错，本课没有用它。

**3）`print_uint_v1` 为什么把缓冲区开在栈上**

```asm
print_uint_v1:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32                 ; ⚠ 缓冲区必须在 push 之后开
    ...
    lea r12, [rsp + 32]         ; 末尾
```

`sub rsp, 32` 之后，`[rsp, rsp+32)` 这 32 字节就是本函数私有的草稿纸，返回前 `add rsp, 32` 还回去即可。注意顺序：**必须先 `push` 保存寄存器、再 `sub rsp`**。如果先开缓冲区再 `push rbx`，`push` 会把 `rbx` 写到缓冲区里，把刚填好的数字冲掉——这是一个很隐蔽的经典错误。

**4）`u64_to_dec` 把缓冲区交给调用者**

```asm
; 入参：rdi = 数值，rsi = 缓冲区首地址（至少 20 字节）
; 返回：rax = 字符串长度，rsi = 字符串真正的起点
u64_to_dec:
    push rbx
    push r12
    mov rax, rdi
    mov rbx, 10
    lea r12, [rsi + 20]         ; 从末尾开始
.digits:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec r12
    mov [r12], dl
    test rax, rax
    jnz .digits
    lea rax, [rsi + 20]
    sub rax, r12                ; 长度 = 末尾 - 起点
    mov rsi, r12                ; 起点可能不是缓冲区开头！
    pop r12
    pop rbx
    ret
```

`u64` 最多 20 位十进制（`18446744073709551615`），所以 20 字节缓冲区够用。返回的 `rsi` 很关键：数值小的时候，字符串只占最后几个字节，缓冲区前面是没被写过的垃圾。调用者必须用返回的 `rsi` 和 `rax`，不能想当然认为字符串从缓冲区首地址开始。

**5）`print_uint_reversed`：故意留下的反面教材**

同一段逻辑，把每一位**立刻**打印出来，结果就是 `54321`。写出这个函数是为了让你亲眼看到「顺序反了」是什么样；它比任何文字解释都直观。

**6）`12345` 的除法过程为什么要单独打一遍**

`trace_digits` 把每轮的余数和商都打出来，你在终端看到的就是上面那张表格。建议先自己用纸算一遍，再对照程序输出。

### 期望输出

```text
=== 整数 -> 十进制字符串（除法 + 取余）===
--- v1：栈上开缓冲区，从末尾往前填 ---
print_uint_v1(0)                    = 0
print_uint_v1(7)                    = 7
print_uint_v1(12345)                = 12345
print_uint_v1(18446744073709551615) = 18446744073709551615
print_uint_reversed(12345)          = 54321  <- 反面教材：低位先算出来，直接打印就是倒的
--- 12345 的除法过程（顺序是反的：先出最低位）---
  余数(当前最低位) = 5   商 = 1234
  余数(当前最低位) = 4   商 = 123
  余数(当前最低位) = 3   商 = 12
  余数(当前最低位) = 2   商 = 1
  余数(当前最低位) = 1   商 = 0
--- v2：往缓冲区末尾倒着填，再整体打印 ---
u64_to_dec(0)        -> 【0】
u64_to_dec(12345)    -> 【12345】
u64_to_dec(1000000)  -> 【1000000】
u64_to_dec(18446744073709551615) -> 【18446744073709551615】
u64_to_dec(1) 之后，缓冲区的末尾 12 字节是 [###########1]，只有最后一个字节被改写 —— 字符串是从末尾往前长的
```

最后一行很值得琢磨：缓冲区末尾那 12 个字节先被填成 `#`，转换 `1` 之后**只有最后一个字节**变成了 `'1'`，前面 11 个 `#` 原封不动。这就是「从末尾往前长」的直接证据。

也正因为如此，`u64_to_dec` 返回的 `rsi`（字符串真正的起点）和传入的缓冲区首地址常常不是同一个值——调用者必须用返回值，不能想当然地从缓冲区开头打印。

## 示例 2：str2num.asm —— 字符串转整数（atoi）

### 完整源码

```asm
; ===========================================================================
; str2num.asm —— 第 08 课示例 2：十进制字符串 → 整数（atoi 的原理）
;
; 编译（在 lesson08 目录下）：
;   make
; 运行：
;   ./str2num
;   printf '  12345\n' | ./str2num      # 从标准输入读一行再转换
;
; 本程序要处理 atoi 的四个老大难问题：
;   1. 正负号：'+' / '-' 只能出现在开头，'-' 还要照顾好 INT64_MIN；
;   2. 非法字符：遇到不是 '0'..'9' 的字节，要分得清它是「字符串结束符」
;      还是「垃圾字符」；
;   3. 溢出：乘 10 或加本位之后超出 [INT64_MIN, INT64_MAX]；
;   4. 空串 / 只有符号：不能当成 0 蒙混过关。
;
; 解析核心：value = value * 10 + (c - '0')
; 溢出判断用了一个很实用的技巧（见 parse_str 里的注释）：
;   如果 value*10 溢出，那么 (value*10 / 10) 就不再等于原来的 value。
; ===========================================================================

section .data
    ; ---- 提示文字 -------------------------------------------------------
    title      db "=== 字符串 -> 整数（atoi 手写实现）==="
    title_len  equ $ - title

    l_head     db "输入                    值(十进制)                值(十六进制)          位数  状态"
    l_head_len equ $ - l_head

    ; ---- 内建测试用例（每个都以 NUL 结尾）-------------------------------
    t1         db "12345", 0
    t2         db "-987", 0
    t3         db "+42", 0
    t4         db "0000", 0
    t5         db "9223372036854775807", 0        ; INT64_MAX
    t6         db "-9223372036854775808", 0       ; INT64_MIN
    t7         db "9223372036854775808", 0        ; 比 INT64_MAX 大 1：溢出
    t8         db "99999999999999999999", 0       ; 远远溢出
    t9         db 0                                ; 真正的空串
    t10        db "-", 0                          ; 只有符号
    t11        db "12a3", 0                       ; 中间夹了非法字符

    ; 指针表：dq 存的是各字符串的地址，配合循环遍历
    table      dq t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11
    table_cnt  equ ($ - table) / 8

    ; 状态码对应的文字
    txt_ok        db "OK"
    txt_ok_len    equ $ - txt_ok
    txt_bad        db "非法字符"
    txt_bad_len    equ $ - txt_bad
    txt_ovf        db "溢出"
    txt_ovf_len    equ $ - txt_ovf
    txt_nul        db "空指针"
    txt_nul_len    equ $ - txt_nul
    txt_emp        db "空串/只有符号"
    txt_emp_len    equ $ - txt_emp

    ; ---- 从标准输入读的那个演示 -----------------------------------------
    l_stdin    db "--- 从标准输入读一行（可用 printf '...' | ./str2num 喂进去）---"
    l_stdin_len equ $ - l_stdin

    l_prompt   db "读出（已去掉换行）= "
    l_prompt_len equ $ - l_prompt

    l_eof      db "读到 0 字节（EOF），没有输入可解析，直接退出。"
    l_eof_len  equ $ - l_eof

    empty_mark db "(空串)"
    empty_mark_len equ $ - empty_mark

section .bss
    inbuf      resb 64          ; 读标准输入用的缓冲区

section .text
    global _start
%include "io.inc"

_start:
    lea rsi, [rel title]
    mov rdx, title_len
    call io_println

    lea rsi, [rel l_head]
    mov rdx, l_head_len
    call io_println

    ; ---- 遍历内建用例表 --------------------------------------------------
    lea rbx, [rel table]        ; rbx 指向指针表（rbx 被调用者保存）
    mov rbp, table_cnt          ; rbp 当循环计数器（同样被调用者保存）

.next:
    mov rdi, [rbx]              ; rdi = 当前测试字符串
    call show_one
    add rbx, 8
    dec rbp
    jnz .next

    call io_newline

    ; ---- 从标准输入读一行 ------------------------------------------------
    lea rsi, [rel l_stdin]
    mov rdx, l_stdin_len
    call io_println

    ; read(0, inbuf, 64)：从标准输入最多读 64 字节
    xor edi, edi                ; fd = STDIN
    lea rsi, [rel inbuf]
    mov edx, 64
    mov rax, SYS_read
    syscall                     ; 返回值在 rax（负数表示出错）

    test rax, rax
    jle .eof                    ; 0 = EOF，负数 = 错误，都直接收工

    ; ---- 手工去掉结尾的 '\n' 和 '\r' ------------------------------------
    mov rcx, rax                ; rcx = 读到的字节数
    lea rdi, [rel inbuf]
.strip:
    test rcx, rcx
    jz .stripped
    mov al, [rdi + rcx - 1]     ; 看最后一个字节
    cmp al, LF
    je .cut
    cmp al, 13                  ; '\r'（Windows 换行）
    je .cut
    jmp .stripped
.cut:
    dec rcx
    jmp .strip
.stripped:
    mov byte [rdi + rcx], 0     ; 打上字符串结束符

    lea rsi, [rel l_prompt]
    mov rdx, l_prompt_len
    call io_print
    lea rsi, [rel inbuf]
    mov rdx, rcx                ; 长度 = 去掉换行后的字节数
    call io_println

    lea rdi, [rel inbuf]
    call show_one

    xor rdi, rdi
    call io_exit

.eof:
    lea rsi, [rel l_eof]
    mov rdx, l_eof_len
    call io_println
    xor rdi, rdi
    call io_exit

; ---------------------------------------------------------------------------
; show_one —— 解析并打印一个用例：输入串、值、十六进制、位数、状态
;
;   入参：rdi = 指向 NUL 结尾字符串的指针
;   如果字符串是空串（连符号都没有），终端里什么都看不见，
;   所以显示的时候换成 "(空串)" 字样，解析时用的还是那个空串本身。
; ---------------------------------------------------------------------------
show_one:
    push rbx                    ; 要用 rbx/r12-r15 存跨调用的值，先保存
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                ; rbx = 要解析的字符串

    cmp byte [rbx], 0           ; 真·空串？
    jne .parse
    lea rdi, [rel empty_mark + empty_mark_len]  ; 解析用末尾的 NUL
    mov rbx, rdi
    sub rbx, empty_mark_len     ; 但显示的时候换成 "(空串)" 字样
.parse:
    call parse_str
    mov r12, rax                ; r12 = 值
    mov r13, rdx                ; r13 = 状态码
    mov r14, rcx                ; r14 = 位数（要留到第四列）

    ; ---- 第一列：输入字符串，不足 20 列补空格 ---------------------------
    mov rsi, rbx
    call cstr_len
    mov r15, rax                ; r15 = 这一列的长度（r14 要留着装位数）
    mov rsi, rbx
    mov rdx, r15
    call io_print
    mov rdi, 21                 ; 第一列固定 21 列
    sub rdi, r15                ; 还要补几个空格
    call print_spaces

    ; ---- 第二列：值（十进制，末尾补两格）-------------------------------
    mov rdi, r12
    call print_int64
    mov edi, ' '
    call io_putchar
    call io_putchar
    call io_putchar             ; 多补几格，让 19 位数也留出间距

    ; ---- 第三列：十六进制 ------------------------------------------------
    mov rdi, r12
    call io_print_hex
    mov edi, ' '
    call io_putchar
    call io_putchar
    call io_putchar
    call io_putchar

    ; ---- 第四列：位数 ----------------------------------------------------
    mov rdi, r14
    call print_u64
    mov edi, ' '
    call io_putchar
    mov edi, ' '
    call io_putchar

    ; ---- 第五列：状态 ----------------------------------------------------
    mov rdx, r13
    call print_status

    call io_newline

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; parse_str —— 把 rdi 指向的十进制字符串转成 64 位有符号整数
;
;   入参：rdi = 指向 NUL 结尾字符串的指针
;   返回：rax = 解析出的数值
;         rdx = 状态码：0 成功 / 1 非法字符 / 2 溢出 / 3 空指针 / 4 空串或只有符号
;         rcx = 有效数字位数（不含 '+'/'-'；状态不为 0 时无意义）
;
;   寄存器分工（故意全用「被调用者保存」寄存器，因为中途要调 io_putchar）：
;         rbx = 扫描指针
;         r12 = 累加器 value
;         r13 = 符号标志（0 = 正，1 = 负）
;         r14 = 常量 '0'
;         r15 = 第一个数字的位置（最后用它算位数）
;
;   溢出检测两处：
;     * value*10 溢出 —— 乘完再除以 10，回不到原来的 value；
;     * + digit 溢出  —— 64 位无符号加法进位（jc）。
;   最后再按符号和 INT64_MAX / INT64_MIN 比较。
; ---------------------------------------------------------------------------
parse_str:
    push rbx
    push r12
    push r13
    push r14
    push r15                    ; 5 个 push 是奇数：进函数时 rsp ≡ 8 (mod 16)，
                                ; 5*8 = 40 之后 rsp ≡ 0 (mod 16)，
                                ; 函数体里 call 就满足「rsp 是 16 的倍数」

    ; ---- 0. 空指针检查（防止调用者忘了判空） ----------------------------
    test rdi, rdi
    jnz .have_ptr
    xor eax, eax
    mov rdx, 3
    xor ecx, ecx
    jmp .ret

.have_ptr:
    mov rbx, rdi                ; 扫描指针
    xor r12, r12                ; value = 0
    xor r13, r13                ; 符号 = 正

    ; ---- 1. 跳过开头的空白字符（空格 / TAB / 回车 / 换行）--------------
    ; 「  -12345」这种输入很常见（从终端读进来时尤其如此），
    ; 真正的 atoi 也是这么处理的
.skip_ws:
    mov al, [rbx]
    cmp al, ' '
    je .ws
    cmp al, TAB
    je .ws
    cmp al, 13
    je .ws
    cmp al, LF
    jne .sign
.ws:
    inc rbx
    jmp .skip_ws

    ; ---- 2. 可选的正负号（只认第一个非空白字符）------------------------
.sign:
    mov al, [rbx]
    cmp al, '-'
    jne .chk_plus
    mov r13, 1
    inc rbx
    jmp .digits
.chk_plus:
    cmp al, '+'
    jne .digits
    inc rbx

.digits:
    mov r15, rbx                ; 记下第一个数字的位置
    mov r14b, '0'               ; 常量 '0' 暂放 r14 低 8 位（本函数没别人用 r14）

.loop:
    movzx eax, byte [rbx]       ; 读一个字节（movzx：高位清零）
    test al, al
    jz .end                     ; NUL：字符串正常结束
    sub al, r14b                ; al = c - '0'
    cmp al, 9
    ja .bad_char                ; 不是 '0'..'9'

    ; --- value = value * 10 + digit，带两处溢出检查 ---------------------
    ; ⚠ 不要把 digit 暂存在 ah 里！div 会写 rax，把 ah 一起冲掉
    ;   （这个坑在 README 里也会讲）。这里用 r8 这个「调用者保存」寄存器。
    movzx r8d, al               ; r8 = digit（下面一直要活着）

    mov rcx, r12                ; rcx = 乘之前的 value
    imul r12, r12, 10           ; r12 *= 10
    mov rax, r12
    xor edx, edx
    mov r9, 10
    div r9                      ; rax = (value*10) / 10
    cmp rax, rcx
    jne .overflow               ; 除不回来 -> 乘 10 时就溢出了

    add r12, r8                 ; value += digit
    jc .overflow                ; 无符号加法进位 -> 溢出

    inc rbx
    jmp .loop

.bad_char:
    mov rdx, 1
    xor eax, eax
    xor ecx, ecx
    jmp .ret

.end:
    mov rcx, rbx
    sub rcx, r15                ; 位数 = 扫描位置 - 第一个数字的位置
    test rcx, rcx
    jz .empty                   ; 一个数字都没读到："", "-", "+"

    test r13, r13
    jnz .neg

    mov rax, 0x7fffffffffffffff ; INT64_MAX
    cmp r12, rax
    ja .overflow
    mov rax, r12
    xor rdx, rdx
    jmp .ret

.neg:
    ; 负数最小可以到 -2^63，即无符号写法 0x8000000000000000
    mov rax, 0x8000000000000000
    cmp r12, rax
    ja .overflow
    mov rax, r12
    neg rax                     ; 取负；0x8000000000000000 取负还是它自己
    xor rdx, rdx
    jmp .ret

.empty:
    xor eax, eax
    mov rdx, 4
    xor ecx, ecx
    jmp .ret

.overflow:
    xor eax, eax
    mov rdx, 2
    xor ecx, ecx
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; 下面是给示例配套的小工具函数
; ---------------------------------------------------------------------------

; str_eq —— 比较 rdi 和 rsi 两个 NUL 结尾字符串
;   返回：rax = 1 相等 / 0 不等
str_eq:
    xor eax, eax
.loop:
    mov cl, [rdi]
    mov dl, [rsi]
    cmp cl, dl
    jne .no
    test cl, cl
    jz .yes                     ; 同时到 NUL：相等
    inc rdi
    inc rsi
    jmp .loop
.yes:
    mov eax, 1
.no:
    ret

; cstr_len —— 求 rsi 指向的 NUL 结尾字符串长度
;   返回：rax = 长度（不含 NUL）
cstr_len:
    xor eax, eax
.loop:
    cmp byte [rsi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; print_spaces —— 打印 rdi 个空格
;   入参：rdi = 个数（<= 0 时什么都不打）
print_spaces:
    push rbx
    mov rbx, rdi
    test rbx, rbx
    jle .done
.loop:
    mov rdi, ' '
    call io_putchar
    dec rbx
    jnz .loop
.done:
    pop rbx
    ret

; print_int64 —— 自己写的有符号十进制输出（负数先打 '-' 再取绝对值）
;   入参：rdi = 有符号整数
print_int64:
    test rdi, rdi
    js .neg
    jmp print_u64
.neg:
    push rdi
    mov rdi, '-'
    call io_putchar
    pop rdi
    mov rax, rdi
    neg rax
    mov rdi, rax
    jmp print_u64

; print_u64 —— 无符号十进制输出（栈上开缓冲区，从末尾往前填）
;   入参：rdi = 无符号整数
print_u64:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32                 ; ⚠ 缓冲区必须在 push 之后开

    mov rax, rdi
    mov rbx, 10
    lea r12, [rsp + 32]         ; 缓冲区末尾
.loop:
    xor rdx, rdx                ; ⚠ div 前清零
    div rbx
    add dl, '0'
    dec r12
    mov [r12], dl
    test rax, rax
    jnz .loop

    mov rsi, r12
    lea rdx, [rsp + 32]
    sub rdx, r12                ; 长度
    call io_print

    add rsp, 32
    pop r12
    pop rbx
    leave
    ret

; print_status —— 打印状态码对应的文字
;   入参：rdx = 状态码
print_status:
    cmp rdx, 0
    je .s0
    cmp rdx, 1
    je .s1
    cmp rdx, 2
    je .s2
    cmp rdx, 3
    je .s3
    lea rsi, [rel txt_emp]
    mov rdx, txt_emp_len
    jmp io_print
.s0:
    lea rsi, [rel txt_ok]
    mov rdx, txt_ok_len
    jmp io_print
.s1:
    lea rsi, [rel txt_bad]
    mov rdx, txt_bad_len
    jmp io_print
.s2:
    lea rsi, [rel txt_ovf]
    mov rdx, txt_ovf_len
    jmp io_print
.s3:
    lea rsi, [rel txt_nul]
    mov rdx, txt_nul_len
    jmp io_print
```

### 逐段讲解

**1）`atoi` 要处理的四类输入**

| 输入 | 期望结果 | 状态码 |
|---|---|---|
| `12345` | 12345 | 0（OK） |
| `-987` | -987 | 0 |
| `9223372036854775808` | 不返回数值 | 2（溢出） |
| `99999999999999999999` | 不返回数值 | 2 |
| `(空串)` | 不返回数值 | 4（空串或只有符号） |
| `-` | 不返回数值 | 4 |
| `12a3` | 不返回数值 | 1（非法字符） |
| `  -12345`（前面有空格） | -12345 | 0 |

一个「能用的」解析函数必须把这几类全部分清——只处理第一类的话，程序在校验输入时会出各种问题。

**2）骨架：一个指针扫到底**

```asm
    mov rbx, rdi            ; rbx = 扫描指针
    xor r12, r12            ; value = 0
    xor r13, r13            ; 符号标志：0 正 / 1 负
.skip_ws:                   ; 跳过开头的空白
    ...
.sign:                      ; 处理 '+' / '-'
    ...
.loop:                      ; 每位数字：value = value*10 + digit
    movzx eax, byte [rbx]
    test al, al
    jz .end                 ; NUL：结束
    sub al, r14b            ; al = c - '0'
    cmp al, 9
    ja .bad_char            ; 不是 '0'..'9'
```

`movzx` 保证高 24 位是 0，否则 `sub al, '0'` 之后 `cmp al, 9` 可能因为高位垃圾而误判。读到 NUL 就正常结束，读到别的非数字就是非法字符——这两者必须分开。

**3）溢出检测：两个判据**

无符号的 `value = value * 10 + digit` 有两处可能溢出：

```asm
    movzx r8d, al           ; r8 = digit
    mov rcx, r12            ; rcx = 乘之前的 value
    imul r12, r12, 10       ; r12 *= 10
    mov rax, r12
    xor edx, edx
    mov r9, 10
    div r9                  ; rax = (value*10) / 10
    cmp rax, rcx
    jne .overflow           ; ← 判据 1：乘 10 溢出

    add r12, r8             ; value += digit
    jc .overflow            ; ← 判据 2：加法进位
```

* **判据 1 的原理**：如果 `value*10` 在 64 位里绕了一圈，那么它再除以 10 就回不到原来的 `value` 了。这是一个不需要比较 `2^64/10` 的通用技巧。
* **判据 2**：`add` 之后 `jc`（进位标志）置位，说明和超过了 `2^64-1`。

**4）为什么最后还要比一次 `INT64_MAX` / `INT64_MIN`**

上面的判据只保证「没超过 u64 的范围」。但对有符号的 `atoi` 来说，`9223372036854775808`（2^63）虽然没超 u64，却已经超了 `INT64_MAX`：

```asm
    test r13, r13
    jnz .neg

    mov rax, 0x7fffffffffffffff ; INT64_MAX
    cmp r12, rax
    ja .overflow
    mov rax, r12
    ...
.neg:
    mov rax, 0x8000000000000000 ; 负数最多到 -2^63
    cmp r12, rax
    ja .overflow
    mov rax, r12
    neg rax                     ; 0x8000000000000000 取负还是它自己
```

负数的最小值是 `-2^63`，它的绝对值 `0x8000000000000000` 比 `INT64_MAX` 大 1，所以负数用的是另一个上界。这也解释了为什么 `-9223372036854775808` 能正确解析、而 `9223372036854775808` 会报溢出。

**5）为什么解析函数要「全用被调用者保存寄存器」**

`parse_str` 内部会调用 `io_putchar`（打印非法字符），而 `io.inc` 的例程只保证 `rbx/rbp/r12-r15` 不变。所以扫描指针放 `rbx`、累加器放 `r12`、符号放 `r13`、常量 `'0'` 放 `r14`，跨调用全部安全：

```asm
parse_str:
    push rbx
    push r12
    push r13
    push r14
    push r15        ; 5 个 push 是奇数：进函数时 rsp ≡ 8 (mod 16)，
                    ; 5×8=40 之后 rsp ≡ 0 (mod 16)，正好满足 call 对齐
```

**6）`print_status`：把状态码翻译成人话**

状态码只用一个寄存器 `rdx` 返回，`rax` 放数值，`rcx` 放有效位数——三个返回值正好用三个寄存器，不需要额外的内存参数。这是小函数里很实用的做法。

### 期望输出

```text
=== 字符串 -> 整数（atoi 手写实现）===
输入                    值(十进制)                值(十六进制)          位数  状态
12345                12345   0x3039    5  OK
-987                 -987   0xfffffffffffffc25    3  OK
+42                  42   0x2a    2  OK
0000                 0   0x0    4  OK
9223372036854775807  9223372036854775807   0x7fffffffffffffff    19  OK
-9223372036854775808 -9223372036854775808   0x8000000000000000    19  OK
9223372036854775808  0   0x0    0  溢出
99999999999999999999 0   0x0    0  溢出
(空串)
            0   0x0    0  空串/只有符号
-                    0   0x0    0  空串/只有符号
12a3                 0   0x0    0  非法字符

--- 从标准输入读一行（可用 printf '...' | ./str2num 喂进去）---
读出（已去掉换行）=   -12345
  -12345             -12345   0xffffffffffffcfc7    5  OK
```

（`-987` 的十六进制是 `0xfffffffffffffc25`，也就是它 64 位补码的样子，这是有符号负数在寄存器里的真实存储方式。）

### 从标准输入读一个数

```bash
printf '  -12345\n' | ./str2num
```

程序会读一行、去掉结尾的换行、再解析。如果标准输入直接是 `/dev/null`（比如 `make run` 时），`read` 返回 0，程序会打印「读到 0 字节（EOF）」然后正常退出，不会崩。

## 编译与运行

```bash
cd lesson08
make
./num2str
./str2num
printf '42\n' | ./str2num      # 额外演示：从标准输入解析
make test
```

## 动手练习

1. 给 `u64_to_dec` 加一个「右对齐补零」的选项：转换后把前面空出来的字节全填 `'0'`（提示：返回起点之前，从缓冲区首地址一直填到起点）。
2. 写一个 `u64_to_hex`，把整数转成十六进制字符串（把 `10` 换成 `16`，`0~9` 之后补 `'a'~'f'`，参考 `io.inc` 里 `io_print_hex` 的判断 `cmp dl, 10 / jb`）。
3. 给 `parse_str` 加「支持 `0x` 前缀的十六进制」：读到 `0` 后面跟 `x` 时把基数换成 16，并对 `a`~`f` / `A`~`F` 做转换。
4. 写一个 `print_int64`，输出有符号数（负号单独打 `'-'`，再输出绝对值）。注意 `-9223372036854775808` 取绝对值会溢出，想想怎么处理。
5. 写一个程序：从标准输入读两个数（中间用空格分隔），输出它们的和。提示：读到空格就是第一个数的结尾，把指针往后挪一格继续解析第二个数。
6. 思考题：`u64_to_dec` 的注释里说缓冲区「必须至少 20 字节」。如果只给 10 字节会怎样？什么输入能触发这个问题？
7. 思考题：为什么 `div` 之前必须 `xor rdx, rdx`？如果 `rdx` 里残留着上一轮的余数会算出什么？（提示：`div rbx` 实际除的是 `rdx:rax` 这个 128 位数。）

## 常见坑

* **`div` 之前忘了清零 `rdx`。** `div rbx` 除的是 `rdx:rax` 组成的 128 位数。`rdx` 里有垃圾时，或者商大到超过 64 位时，CPU 会直接抛 `#DE`（除零/溢出异常），程序收到 `SIGFPE` 被杀掉，表现为「跑着跑着突然崩了」。养成习惯：`div` 前面紧跟 `xor rdx, rdx`。
* **字符串缓冲区忘了留 NUL 的位置。** `resb 20` 只够放 20 个数字字符，要当 C 风格字符串用还得再留 1 字节给结尾的 `\0`。本课的 `u64_to_dec` 返回「起点 + 长度」，不写 `\0`，所以 `resb 32` 更保险。
* **`.data` 里的字符串忘了写 `, 0` 结尾。** 如果这个字符串会交给「按 NUL 找结尾」的函数（本课 `cstr_len`、`str_eq`），少一个 0 就会一路读下去，把相邻的字符串甚至别的内容都算进去，输出莫名其妙多一截。写法：`db "abc", 0`。
* **`movzx` 与 `mov` 的区别。** `mov al, [rbx]` 只写 `al`，`rax` 的高 56 位保留旧值；`movzx eax, byte [rbx]` 会把高 56 位清零。凡是要把单字节当数值用，就用 `movzx`。
* **别把 digit 暂存在 `ah` 里。** `ah` 是 `rax` 的第 8~15 位，而 `div` 会写 `rax`——算完商，暂存在 `ah` 的数字就被冲掉了。正确的做法是放到一个独立的寄存器（本课用 `r8`）或内存里。
* **`imul r12, r12, 10` 之后不要指望标志位。** `imul` 会设置 `OF` / `CF`，但「乘 10 溢出」在无符号语义下用 `OF` 判断并不可靠；本课用「除回去比对」的通用办法。
* **`add r12, rcx` 之后要立刻看 `jc`。** `cmp`、`test`、`test` 之外很多指令都会改标志位；`add` 之后马上 `jc`，中间别插入别的指令。
* **负数写 `mov rcx, -5` 而不是 `mov ecx, -5`。** 后者会把高 32 位清零。
* **输出长度千万别用 `mov dl, 1`。** 写低 8 位不会清零高 24 位，`rdx` 里可能残留垃圾，`write` 就会输出一长串。要写 `mov edx, 1`。
* **字符串比较不要用 `cmp rsi, rdi`。** 那比的是两个地址，不是内容。要比内容必须逐字节循环（参考 `str_eq`）。

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
default rel                             ; 数据寻址默认 RIP 相对，所有 [标签] 都自动变成 [rel 标签]
bits 64

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

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

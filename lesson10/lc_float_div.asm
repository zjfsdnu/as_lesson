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

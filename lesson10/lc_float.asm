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

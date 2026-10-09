; ===========================================================================
; 第 12 课示例 2：lc_inline.asm
;   * 一个能**单独运行**的 libc 程序（入口 main），演示「汇编函数怎么调用
;     C 库函数 printf」；
;   * 同时它导出的两个函数 asm_flag / scale_shift 会被同目录的
;     lc_inline.c（用 GCC 内联汇编写的小程序）链接进去，演示 C 与汇编互调。
;
; 单独编译运行：
;   nasm -f elf64 -g -F dwarf -I ../include -o lc_inline.o lc_inline.asm
;   gcc -no-pie -Wall -O0 -o lc_inline lc_inline.o
;   ./lc_inline
;
; 和 lc_inline.c 一起编译运行：
;   nasm -f elf64 -g -F dwarf -I ../include -o lc_inline.o lc_inline.asm
;   gcc -no-pie -Wall -O0 -o lc_inline_c lc_inline.c lc_inline.o
;   ./lc_inline_c
;
; 说明：本文件里不出现任何 __asm__ —— 内联汇编是 **C 语言的特性**，
;       只有 lc_inline.c 里才有；这里是用 NASM 写的「对照版」。
;
; 调用约定复习（SysV AMD64）：
;   整数参数 rdi, rsi, rdx, rcx, r8, r9；浮点参数 xmm0..xmm7
;   调用变参函数 printf 前，eax = 本次调用用到的向量寄存器个数
;   call 时 rsp 必须是 16 的倍数 -> 函数开头 push rbp / mov rbp, rsp
; ===========================================================================

default rel
bits 64

section .data
    ; 每个 printf 只带一个 %f：一个格式串对应一个 xmm 寄存器，
    ; 这样 eax 永远是 1，不容易数错。
    f_shift     db "汇编函数 scale_shift(2.0, 0.5) = %.6f   (期望 4.5)", 10, 0
    f_flag1     db "汇编函数 asm_flag(%ld) 通过 printf 打印:", 10, 0
    f_flag2     db "  [asm] n = %ld", 10, 0
    f_head      db "=== 汇编版对照程序（真正的内联汇编在 lc_inline.c）===", 10, 0

    d_two       dq 2.0
    d_half      dq 0.5
    f_cvt       db "cvtsi2sd: %ld -> %.1f", 10, 0

section .text
    extern printf                       ; 引用 C 库函数
%ifndef NO_MAIN
    global main                         ; 自测入口；和 C 混链时用 -DNO_MAIN 去掉它
%endif
    global asm_flag
    global scale_shift
    global asm_double_int

; ---------------------------------------------------------------------------
; asm_flag(n) —— 汇编函数里调用 C 库的 printf
; 入参：rdi = n（64 位整数，由 C 或 NASM 按调用约定传进来）
; 要点：
;   * 要保留 rdi 跨过第一个 printf，所以先在序言里把 rdi 存到栈上；
;     存 1 个 8 字节会让 rsp 变成 8 mod 16，call 前必须补一个 8 字节填充，
;     否则 printf 内部的 movaps 会因 16 字节未对齐而崩。
;   * 变量的位置：-8(%rbp) 和 -16(%rbp)（push 的份也算在内）。
; ---------------------------------------------------------------------------
asm_flag:
    push rbp
    mov  rbp, rsp
    sub  rsp, 16                        ; 两个 8 字节栈槽：n 和填充
    mov  [rbp-8], rdi                   ; 保存 n

    lea  rdi, [rel f_flag1]             ; 第 1 个参数：格式串
    mov  rsi, [rbp-8]                   ; 第 2 个参数：n（%ld 需要整数参数）
    xor  eax, eax                       ; 没用向量寄存器
    call printf

    lea  rdi, [rel f_flag2]
    mov  rsi, [rbp-8]
    xor  eax, eax
    call printf

    leave                               ; = mov rsp, rbp + pop rbp
    ret

; ---------------------------------------------------------------------------
; scale_shift(x, s) -> x * 2 + s
; 入参：xmm0 = x, xmm1 = s；返回：xmm0
; 这个函数会被 lc_inline.c 里的同名绑定（register double ... asm("xmm0")）
; 调用，正好复用同一套寄存器位置。
; ---------------------------------------------------------------------------
scale_shift:
    addsd xmm0, xmm0                    ; xmm0 = 2x
    addsd xmm0, xmm1                    ; xmm0 = 2x + s
    ret                                 ; 返回值已经在 xmm0 里了

; ---------------------------------------------------------------------------
; asm_double_int(n) -> 2n
; 入参：rdi = n；返回：rax = 2n
; 这是「整数参数、整数返回」的最简单互调例子：
; lc_inline.c 里的 call_asm_double_int 会显式 movq 到 rdi、call、再从 rax 取回。
; 它不调用任何 libc 函数，所以是叶子函数，不需要栈帧。
; ---------------------------------------------------------------------------
asm_double_int:
    lea  rax, [rdi + rdi]               ; rax = rdi * 2（lea 比 imul 更短）
    ret

; ---------------------------------------------------------------------------
; 单独的 main：不依赖 lc_inline.c，自己就能跑
; ---------------------------------------------------------------------------
%ifndef NO_MAIN
main:
    push rbp
    mov  rbp, rsp

    lea  rdi, [rel f_head]
    xor  eax, eax
    call printf

    ; ---- 直接调用 scale_shift：按 ABI 把参数放进 xmm0/xmm1 ----
    movsd xmm0, [rel d_two]             ; 2.0
    movsd xmm1, [rel d_half]            ; 0.5
    call scale_shift                    ; 返回 4.5，在 xmm0 里
    lea  rdi, [rel f_shift]             ; 注意：格式串 -> rdi，和 xmm0 不冲突
    mov  eax, 1                         ; 用了 1 个向量寄存器（xmm0）
    call printf

    ; ---- 演示 cvtsi2sd：整数 -> double，然后交给 printf 打印 ----
    mov  rsi, 42
    mov  ecx, 42
    cvtsi2sd xmm0, ecx                  ; xmm0 = (double)42
    lea  rdi, [rel f_cvt]
    mov  eax, 1
    call printf

    ; ---- 调用自己写的 asm_flag，它会再调 printf ----
    mov  rdi, 99
    call asm_flag

    xor  eax, eax
    leave
    ret

%endif ; NO_MAIN

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

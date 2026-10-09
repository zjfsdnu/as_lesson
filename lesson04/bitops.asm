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

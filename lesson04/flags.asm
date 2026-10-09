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

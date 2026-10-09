; ===========================================================================
; cmpjmp.asm —— cmp 与条件转移（conditional jump）
;
; 关键点：同一对操作数，用「有符号」还是「无符号」的跳转指令，结果可能相反。
;
;   cmp a, b   实际做 a - b，但不保存结果，只设置标志位：
;       ZF=1  → a == b
;       CF=1  → 无符号角度 a < b（减法发生了借位）
;       有符号的大小关系由 SF 和 OF 共同决定（相等时还要看 ZF）
;
;   无符号用：jb(below) / jbe / ja(above) / jae
;   有符号用：jl(less)  / jle / jg(greater) / jge
;   相等用  ：je / jne（有符号无符号都一样）
;
; 纯系统调用程序：入口 _start。运行：  make && ./cmpjmp
; ===========================================================================
default rel

section .data
    t1 db "cmp   1, 2     : jl    -> "
    l1 equ $ - t1
    t2 db "cmp  -1, 1     : jl    -> "
    l2 equ $ - t2
    t3 db "cmp  -1, 1     : jg    -> "
    l3 equ $ - t3
    t4 db "cmp  -1, 1     : ja    -> "
    l4 equ $ - t4
    t5 db "cmp  -1, 1     : jb    -> "
    l5 equ $ - t5
    t6 db "cmp   5, 5     : je    -> "
    l6 equ $ - t6
    t7 db "cmp   3, 5     : jge   -> "
    l7 equ $ - t7
    t8 db "test  0, 0     : jz    -> "
    l8 equ $ - t8

    ; 判定结论；末尾直接带换行，省掉一次 io_newline
    s_yes db "taken", 10
    l_yes equ $ - s_yes
    s_no  db "not taken", 10
    l_no  equ $ - s_no

section .text
    global _start
%include "io.inc"

_start:
; ---- 测试 1：cmp 1, 2 → 1-2 借位 CF=1、SF=1，有符号 jl「小于」成立 ----
    lea  rsi, [rel t1]
    mov  rdx, l1
    call io_print
    mov  rax, 1
    mov  rbx, 2
    cmp  rax, rbx
    jl   .yes1
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr1
.yes1:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr1:
    call io_print

; ---- 测试 2：cmp -1, 1 → 有符号看：-1 < 1 成立（SF=1、OF=0 → jl 成立） ----
    lea  rsi, [rel t2]
    mov  rdx, l2
    call io_print
    mov  rax, -1
    mov  rbx, 1
    cmp  rax, rbx
    jl   .yes2
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr2
.yes2:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr2:
    call io_print

; ---- 测试 3：同样的 cmp -1, 1 换成 jg（有符号「大于」）→ 不成立 ----
    lea  rsi, [rel t3]
    mov  rdx, l3
    call io_print
    mov  rax, -1
    mov  rbx, 1
    cmp  rax, rbx
    jg   .yes3
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr3
.yes3:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr3:
    call io_print

; ---- 测试 4：★重点★ 同样的 cmp -1, 1 换成 ja（无符号「大于」）→ 成立！
;           无符号把 -1 看成 0xffffffffffffffff = 18446744073709551615，
;           它当然比 1「大」。ja 的条件是 CF=0 且 ZF=0 ----
    lea  rsi, [rel t4]
    mov  rdx, l4
    call io_print
    mov  rax, -1
    mov  rbx, 1
    cmp  rax, rbx
    ja   .yes4
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr4
.yes4:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr4:
    call io_print

; ---- 测试 5：同样的 cmp -1, 1 换成 jb（无符号「小于」）→ 不成立。
;           这就是为什么处理负数数组、负数下标时必须用 jl/jge ----
    lea  rsi, [rel t5]
    mov  rdx, l5
    call io_print
    mov  rax, -1
    mov  rbx, 1
    cmp  rax, rbx
    jb   .yes5
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr5
.yes5:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr5:
    call io_print

; ---- 测试 6：cmp 5, 5 → ZF=1，je 成立 ----
    lea  rsi, [rel t6]
    mov  rdx, l6
    call io_print
    mov  rax, 5
    mov  rbx, 5
    cmp  rax, rbx
    je   .yes6
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr6
.yes6:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr6:
    call io_print

; ---- 测试 7：cmp 3, 5 → jge（有符号「大于等于」）不成立 ----
    lea  rsi, [rel t7]
    mov  rdx, l7
    call io_print
    mov  rax, 3
    mov  rbx, 5
    cmp  rax, rbx
    jge  .yes7
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr7
.yes7:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr7:
    call io_print

; ---- 测试 8：test rax, rax 是「和 0 比较」的标准写法。test 不写回结果，
;           还会强制 CF=0、OF=0，所以之后只能用 jz/jnz/jl/js 之类看 ZF/SF ----
    lea  rsi, [rel t8]
    mov  rdx, l8
    call io_print
    xor  eax, eax                   ; rax = 0
    test rax, rax
    jz   .yes8
    lea  rsi, [rel s_no]
    mov  rdx, l_no
    jmp  .pr8
.yes8:
    lea  rsi, [rel s_yes]
    mov  rdx, l_yes
.pr8:
    call io_print

; ---- 结束进程 ----
    xor  edi, edi
    call io_exit

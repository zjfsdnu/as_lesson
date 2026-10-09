; ===========================================================================
; count.asm —— 计数循环：用 rcx 数数，打印 1..10、10..1，以及 loop 指令
;
; ★ 本课最重要的一条规则 ★
;   io.inc 里的每个例程内部都会执行 syscall，而 syscall 指令会把 rcx
;   和 r11 当作「返回地址/标志位暂存」来用，返回后 rcx 里就不是原来的值了。
;   所以：拿 rcx 当循环计数器时，每次调用 io 例程之前要把 rcx 压栈，
;         调用完再弹回来。不想这么麻烦就换成 rbx/rbp/r12-r15。
;
; 纯系统调用程序：入口 _start。运行： make && ./count
; ===========================================================================
default rel

section .data
    t_a db "A) rcx counter, 1..10   : "
    l_a equ $ - t_a
    t_b db "B) rcx counter, 10..1   : "
    l_b equ $ - t_b
    t_c db "C) loop: 1+2+...+100    = "
    l_c equ $ - t_c
    s_sp db " "
    l_sp equ $ - s_sp

section .text
    global _start
%include "io.inc"

_start:
; ---------------------------------------------------------------------------
; A) 用 rcx 当计数器打印 1 2 3 ... 10（数字之间一个空格，末尾没有空格）
;    每次调用 io 例程前后都 push/pop rcx —— 这就是「保护计数器」
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_a]
    mov  rdx, l_a
    call io_print

    mov  rcx, 1                     ; 计数器：1 .. 10
.a_loop:
    cmp  rcx, 1
    je   .a_first                   ; 第一个数字前面不加空格
    push rcx                        ; ★ 保护计数器（syscall 会破坏 rcx）
    lea  rsi, [rel s_sp]
    mov  rdx, l_sp
    call io_print
    pop  rcx                        ; ★ 取回计数器
.a_first:
    push rcx
    mov  rdi, rcx
    call io_print_int               ; 打印计数器的值
    pop  rcx
    inc  rcx                        ; 计数器 +1
    cmp  rcx, 10
    jle  .a_loop                    ; 还没数到 10 就继续
    call io_newline

; ---------------------------------------------------------------------------
; B) 倒着数 10 9 8 ... 1：用 dec + jnz
;    dec 会设置 ZF：减到 0 时 ZF=1，jnz 就不再跳回去
;    注意 dec 不影响 CF，所以别指望用 jb/jae 判断「减到 0 了」
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_b]
    mov  rdx, l_b
    call io_print

    mov  rcx, 10
.b_loop:
    cmp  rcx, 10
    je   .b_first                   ; 第一个数字（10）前面不加空格
    push rcx
    lea  rsi, [rel s_sp]
    mov  rdx, l_sp
    call io_print
    pop  rcx
.b_first:
    push rcx
    mov  rdi, rcx
    call io_print_int
    pop  rcx
    dec  rcx                        ; 计数器 -1
    jnz  .b_loop                    ; 还不是 0 就继续
    call io_newline

; ---------------------------------------------------------------------------
; C) loop 指令：rcx 减 1，如果 rcx != 0 就跳回标号
;    loop 只认 rcx，而且比「dec rcx + jnz」慢，实际代码里前者更常用。
;    这里循环体里没有 io 调用，所以 rcx 可以放心用。
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_c]
    mov  rdx, l_c
    call io_print

    xor  rax, rax                   ; rax = 累加和 0
    mov  rcx, 100                   ; 从 100 加到 1
.c_sum:
    add  rax, rcx                   ; sum += i
    loop .c_sum                     ; rcx--；rcx != 0 就跳回 .c_sum
    mov  rdi, rax
    call io_print_int               ; 5050
    call io_newline

; ---------------------------------------------------------------------------
; 结束进程
; ---------------------------------------------------------------------------
    xor  edi, edi
    call io_exit

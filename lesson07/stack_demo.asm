; ===========================================================================
; stack_demo.asm —— 第 07 课示例 2：栈是向下增长的
;
; 编译（在 lesson07 目录下）：
;   make
; 运行：
;   ./stack_demo
;
; 运行时会打印一串十六进制地址。这些地址和内核给的初始栈位置有关，
; 每台机器、每次运行都不一样，但有两点永远成立：
;   1. push 之后 rsp 变小，pop / add rsp 之后 rsp 变大 —— 栈往低地址方向长；
;   2. 下面打印的「相差 N 字节」在同一次运行里完全固定。
;
; 本程序把基准 rsp 存在 rbp / r15 里，靠它们算差值。
;   为什么不用 rax 存？因为 io.inc 的打印函数一律只保证
;   rax/rcx/r11 之外的寄存器不变（rbx/rbp/r12-r15 是被调用者保存），
;   拿 rax 存跨调用的值，调用一次 io_print 就被冲掉了。
; ===========================================================================

section .data
    title       db "=== 栈（stack）是向下增长的 ==="
    title_len   equ $ - title

    ; ---- 第一部分：push / pop -------------------------------------------
    s_push      db "--- push 一次，rsp 就减 8（一个 8 字节栈槽）---"
    s_push_len  equ $ - s_push

    s_rsp0      db "起始 rsp（对齐到 16）        = "
    s_rsp0_len  equ $ - s_rsp0

    s_push1     db "第 1 次 push 后的 rsp（下了 "
    s_push1_len equ $ - s_push1

    s_push2     db "第 2 次 push 后的 rsp（下了 "
    s_push2_len equ $ - s_push2

    s_end       db "全部弹干净后的 rsp             = "
    s_end_len   equ $ - s_end

    s_bytes     db " 字节） = "
    s_bytes_len equ $ - s_bytes

    s_unit      db " 字节"
    s_unit_len  equ $ - s_unit

    ; ---- 第二部分：函数帧（frame）---------------------------------------
    s_frame     db "--- 函数帧：push rbp; mov rbp, rsp; sub rsp, 16 ---"
    s_frame_len equ $ - s_frame

    s_rbp       db "函数里 rbp - rsp（局部空间） = "
    s_rbp_len   equ $ - s_rbp

    s_frame_rsp db "函数里 rsp                   = "
    s_frame_rsp_len equ $ - s_frame_rsp

    s_retaddr   db "call 压进去的返回地址槽位    = "
    s_retaddr_len equ $ - s_retaddr

    s_frame_ok  db "返回地址槽里存的确实是下一条指令的地址，"
    s_frame_ok_len equ $ - s_frame_ok
    s_frame_ok2 db "所以 ret 才能准确跳回来。"
    s_frame_ok2_len equ $ - s_frame_ok2

    ; 两个演示用的数（作为立即数 push 到栈上）
    v_one       equ 0x1111
    v_two       equ 0x2222

section .text
    global _start
default rel                             ; 数据寻址默认 RIP 相对，所有 [标签] 都自动变成 [rel 标签]
bits 64

%include "io.inc"

_start:
    ; 把 rsp 对齐到 16，这样打印出来的地址末尾都是 0，好对照
    and rsp, -16
    mov rbp, rsp                ; rbp = rsp0：全程不动的基准
    mov r15, rsp                ; r15 = rsp0（r15 也是被调用者保存）

    lea rsi, [rel title]
    mov rdx, title_len
    call io_println

    lea rsi, [rel s_push]
    mov rdx, s_push_len
    call io_println

    ; ---- 打印起始 rsp ---------------------------------------------------
    lea rsi, [rel s_rsp0]
    mov rdx, s_rsp0_len
    call io_print
    mov rdi, rbp
    call io_print_hex
    call io_newline

    ; ---- push 两个数 ----------------------------------------------------
    push v_one                  ; rsp = rsp0 - 8
    push v_two                  ; rsp = rsp0 - 16

    ; 第 1 次 push 后的 rsp 等于 rbp - 8
    lea rsi, [rel s_push1]
    mov rdx, s_push1_len
    call io_print
    mov rdi, 8                  ; 下了 8 字节
    call print_u64
    lea rsi, [rel s_bytes]
    mov rdx, s_bytes_len
    call io_print
    lea rdi, [rbp - 8]
    call io_print_hex
    call io_newline

    ; 现在（第 2 次 push 之后）的 rsp 就是 rsp0 - 16
    lea rsi, [rel s_push2]
    mov rdx, s_push2_len
    call io_print
    mov rdi, r15
    sub rdi, rsp                ; 下了 16 字节
    call print_u64
    lea rsi, [rel s_bytes]
    mov rdx, s_bytes_len
    call io_print
    mov rdi, rsp
    call io_print_hex
    call io_newline

    ; ---- 弹干净 ---------------------------------------------------------
    ; 效果上等于 pop 两次；这里直接用 add rsp, 16 更直观
    add rsp, 16

    lea rsi, [rel s_end]
    mov rdx, s_end_len
    call io_print
    mov rdi, rsp
    call io_print_hex
    call io_newline

    ; ---- 第二部分：函数帧 ------------------------------------------------
    lea rsi, [rel s_frame]
    mov rdx, s_frame_len
    call io_println
    call frame_probe            ; 内部把三个观测值写进 .bss

    lea rsi, [rel s_rbp]
    mov rdx, s_rbp_len
    call io_print
    mov rdi, [rel frame_size]
    call print_u64
    lea rsi, [rel s_unit]
    mov rdx, s_unit_len
    call io_print
    call io_newline

    lea rsi, [rel s_frame_rsp]
    mov rdx, s_frame_rsp_len
    call io_print
    mov rdi, [rel frame_rsp]
    call io_print_hex
    call io_newline

    lea rsi, [rel s_retaddr]
    mov rdx, s_retaddr_len
    call io_print
    mov rdi, [rel ret_slot]
    call io_print_hex
    call io_newline

    lea rsi, [rel s_frame_ok]
    mov rdx, s_frame_ok_len
    call io_println
    lea rsi, [rel s_frame_ok2]
    mov rdx, s_frame_ok2_len
    call io_println

    xor rdi, rdi
    call io_exit

; ---------------------------------------------------------------------------
; frame_probe —— 演示一个标准函数帧长什么样
;
; 刚进函数时栈上的布局（地址从高到低）：
;       [rsp + 8]   = _start 的 rbp（上一帧的帧基址）
;       [rsp]       = 返回地址（call frame_probe 压进去的）
;
; 序言执行完之后：
;       [rbp + 8]   = 返回地址
;       [rbp]       = 旧的 rbp
;       [rbp - 8]   = 局部空间的高 8 字节
;       [rbp - 16]  = 局部空间的低 8 字节  ← 函数体执行时 rsp 在这里
;
; 本函数把三个观测值记到 .bss 里：帧大小、当时的 rsp、返回地址槽的地址。
; ---------------------------------------------------------------------------
frame_probe:
    push rbp
    mov rbp, rsp
    sub rsp, 16                 ; 开 16 字节局部空间（保持 16 字节对齐）

    mov rax, rbp
    sub rax, rsp                ; 帧大小 = rbp - rsp = 16
    mov [rel frame_size], rax

    mov [rel frame_rsp], rsp

    lea rax, [rbp + 8]          ; 返回地址就在 rbp + 8 处
    mov [rel ret_slot], rax

    leave                       ; = mov rsp, rbp + pop rbp
    ret

; ---------------------------------------------------------------------------
; print_u64 —— 把 rdi 里的无符号数按十进制打印出来
;
;   本课只拿它打印「小整数」（偏移量），所以没有处理 0 之外的特殊情况，
;   但 0 也要能正确打印成 "0"（do-while 结构天然满足）。
; ---------------------------------------------------------------------------
print_u64:
    push rbx                    ; 本函数要用 rbx（被调用者保存），先存起来
    lea rbx, [rel numbuf + 24]  ; rbx 指向缓冲区末尾，从后往前填
    mov rax, rdi
    mov r8, 10                  ; 除数 10

.loop:
    xor rdx, rdx                ; div 前必须清零 rdx（被除数高 64 位）
    div r8                      ; rax = rax / 10，rdx = rax % 10
    add dl, '0'
    dec rbx
    mov [rbx], dl
    test rax, rax
    jnz .loop

    mov rsi, rbx
    lea rdx, [rel numbuf + 24]
    sub rdx, rbx
    call io_print

    pop rbx
    ret

section .bss
    frame_size  resq 1          ; 函数帧大小
    frame_rsp   resq 1          ; 函数里的 rsp
    ret_slot    resq 1          ; 返回地址槽的地址
    numbuf      resb 24         ; 十进制转换缓冲区

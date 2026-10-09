; ===========================================================================
; sum_array.asm —— 遍历 .data 里的 qword 数组：求和 / 数负数 / 求平均值
;
; 数组里故意放了负数，用来练：
;   * [基址 + 下标*8] 这种寻址方式
;   * 有符号比较（test/jns、jl、jge），别误用无符号跳转
;   * 有符号除法前的 cqo
;   * 循环计数器不能放 rcx —— syscall 会破坏它
;
; 纯系统调用程序：入口 _start。运行： make && ./sum_array
; 期望：sum = 80，count = 8，negative = 4，average = 10
; ===========================================================================
default rel

section .data
    arr     dq 10, -3, 25, -8, -1, 100, -50, 7
    arr_len equ ($ - arr) / 8       ; 8 个元素，每个 8 字节

    t_arr   db "array    : ["
    l_arr   equ $ - t_arr
    t_arr_e db "]", 10                 ; .data 里换行只能写 10（此时还没 include io.inc）
    l_arr_e equ $ - t_arr_e
    t_sum   db "sum      = "
    l_sum   equ $ - t_sum
    t_cnt   db "count    = "
    l_cnt   equ $ - t_cnt
    t_neg   db "negative = "
    l_neg   equ $ - t_neg
    t_avg   db "average  = "
    l_avg   equ $ - t_avg
    s_comma db ", "
    l_comma equ $ - s_comma

section .text
    global _start
%include "io.inc"

_start:
; ---------------------------------------------------------------------------
; 1) 打印数组内容，格式：[10, -3, 25, -8, -1, 100, -50, 7]
;    寄存器分工：
;      rbx = 数组首地址   rbp = 下标 i（这两个 io 例程都会原样保留）
;      r14 = 当前元素（先用 r14 存住，因为 io_print_int 会破坏 rax）
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_arr]
    mov  rdx, l_arr
    call io_print

    lea  rbx, [rel arr]             ; rbx → arr[0]
    xor  rbp, rbp                   ; i = 0
.prt_loop:
    cmp  rbp, arr_len
    jge  .prt_done

    mov  r14, [rbx + rbp*8]         ; r14 = arr[i]
    mov  rdi, r14
    call io_print_int

    inc  rbp
    cmp  rbp, arr_len
    jge  .prt_done                  ; 最后一个元素后面不加逗号
    lea  rsi, [rel s_comma]
    mov  rdx, l_comma
    call io_print
    jmp  .prt_loop

.prt_done:
    lea  rsi, [rel t_arr_e]
    mov  rdx, l_arr_e
    call io_print                   ; 打印 "]" 和换行

; ---------------------------------------------------------------------------
; 2) 遍历一遍，同时算出累加和与负数个数
;      r12 = sum    r13 = 负数个数    r15 = 元素总数（一会儿求平均值要用）
;    test r14, r14 后看 SF：SF=1 说明最高位是 1，也就是负数 → jns 是「非负就跳」
; ---------------------------------------------------------------------------
    xor  r12, r12                   ; sum = 0
    xor  r13, r13                   ; 负数个数 = 0
    mov  r15, arr_len               ; 元素总数
    lea  rbx, [rel arr]
    xor  rbp, rbp                   ; i = 0

.sum_loop:
    cmp  rbp, r15
    jge  .sum_done

    mov  r14, [rbx + rbp*8]         ; r14 = arr[i]
    add  r12, r14                   ; sum += arr[i]

    test r14, r14
    jns  .not_neg                   ; SF=0 → 不是负数，跳过计数
    inc  r13
.not_neg:
    inc  rbp
    jmp  .sum_loop

.sum_done:
    ; ---- 打印 sum ----
    lea  rsi, [rel t_sum]
    mov  rdx, l_sum
    call io_print
    mov  rdi, r12
    call io_print_int
    call io_newline

    ; ---- 打印 count ----
    lea  rsi, [rel t_cnt]
    mov  rdx, l_cnt
    call io_print
    mov  rdi, r15
    call io_print_int
    call io_newline

    ; ---- 打印 negative ----
    lea  rsi, [rel t_neg]
    mov  rdx, l_neg
    call io_print
    mov  rdi, r13
    call io_print_int
    call io_newline

; ---------------------------------------------------------------------------
; 3) 平均值 = sum / count
;    80 / 8 = 10；被除数和除数都在寄存器里，除法前必须 cqo（有符号）
;    如果这里错写成 xor rdx,rdx（无符号那套），负数数组就会得到荒唐的结果
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_avg]
    mov  rdx, l_avg
    call io_print

    mov  rax, r12                   ; 被除数 = sum
    cqo                             ; ★ 有符号除法：把符号位扩展到 rdx
    idiv r15                        ; rax = sum / count
    mov  rdi, rax
    call io_print_int
    call io_newline

; ---------------------------------------------------------------------------
; 结束进程
; ---------------------------------------------------------------------------
    xor  edi, edi
    call io_exit

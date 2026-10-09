; ===========================================================================
; minmax.asm —— 用条件跳转求最大值/最小值
;
;   第一部分：两个数的最大值。同样的两个数分别用「有符号」和「无符号」比较，
;             结果完全不同 —— 这就是 jg 和 ja 的区别。
;   第二部分：遍历 .data 里的 qword 数组，一边打印一边找最大/最小。
;
; 循环的写法下一课（第 06 课）细讲，这里先看懂「比较 → 条件跳转 → 更新」
; 这个三步套路即可。
;
; 纯系统调用程序：入口 _start。运行： make && ./minmax
; ===========================================================================
default rel

section .data
    arr     dq 17, -5, 42, -100, 0, 33, -7
    arr_len equ ($ - arr) / 8       ; 元素个数 = 总字节数 / 每个 qword 8 字节

    t_smax  db "max_signed(-7, 3)   = "
    l_smax  equ $ - t_smax
    t_umax  db "max_unsigned(-7, 3) = "
    l_umax  equ $ - t_umax
    t_udec  db "  (unsigned: "
    l_udec  equ $ - t_udec
    t_udone db ")"
    l_udone equ $ - t_udone

    t_arr   db "array               = ["
    l_arr   equ $ - t_arr
    t_arr_e db "]", 10                 ; ']' 加换行（.data 里还没 include io.inc，
    l_arr_e equ $ - t_arr_e           ;  所以换行写数字 10，不能写 LF 符号）

    t_max   db "max                 = "
    l_max   equ $ - t_max
    t_min   db "min                 = "
    l_min   equ $ - t_min

    s_comma db ", "
    l_comma equ $ - s_comma

section .text
    global _start
%include "io.inc"

_start:
; ---------------------------------------------------------------------------
; 1) 有符号比较：求 max(-7, 3)
;    套路：先假设第一个数是最大值，再拿第二个数跟它比，更大就替换
;    jle = 有符号「小于等于」：3 <= max 就不用替换
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_smax]
    mov  rdx, l_smax
    call io_print

    mov  rax, -7
    mov  rbx, 3
    mov  r12, rax                   ; 假设 max = -7
    cmp  rbx, r12                   ; 3 和 -7 比
    jle  .s_keep                    ; ★ 有符号比较：3 <= -7 不成立，所以不跳
    mov  r12, rbx                   ; max = 3
.s_keep:
    mov  rdi, r12
    call io_print_int
    call io_newline

; ---------------------------------------------------------------------------
; 2) 无符号比较：同样两个数，-7 被当成 0xfffffffffffffff9
;    jbe = 无符号「小于等于」：3 <= 0xff..f9 成立 → 跳过去，不替换
;    结果 max 是那个「巨大的负数」，打印出来是 0xfffffffffffffff9
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_umax]
    mov  rdx, l_umax
    call io_print

    mov  rax, -7
    mov  rbx, 3
    mov  r12, rax                   ; 假设 max = 0xfffffffffffffff9
    cmp  rbx, r12
    jbe  .u_keep                    ; ★ 无符号比较：3 <= 0xff..f9 成立
    mov  r12, rbx
.u_keep:
    mov  rdi, r12
    call io_print_hex               ; 0xfffffffffffffff9
    lea  rsi, [rel t_udec]
    mov  rdx, l_udec
    call io_print
    mov  rdi, r12
    call io_print_uint              ; 18446744073709551609
    lea  rsi, [rel t_udone]
    mov  rdx, l_udone
    call io_print
    call io_newline

; ---------------------------------------------------------------------------
; 3) 数组：一边打印元素，一边找最大值和最小值
;    寄存器分工（都不能用 rcx/rdx/rax，因为 io 例程会破坏它们）：
;      rbx = 数组首地址（lea rbx, [rel arr]）
;      rbp = 下标 i
;      r12 = 当前最大值    r13 = 当前最小值
;      r14 = 当前元素 —— 元素先放进 r14，再调用 io_print_int，
;            否则打印本身就把 rax 里的元素值冲掉了
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_arr]
    mov  rdx, l_arr
    call io_print

    lea  rbx, [rel arr]             ; rbx → arr[0]
    mov  r12, [rbx]                 ; max 先取 arr[0]
    mov  r13, [rbx]                 ; min 先取 arr[0]
    xor  rbp, rbp                   ; i = 0

.loop:
    cmp  rbp, arr_len
    jge  .loop_done                 ; i >= arr_len 就结束

    mov  r14, [rbx + rbp*8]         ; r14 = arr[i]（下标寻址：基址 + 下标*8）

    cmp  r14, r12
    jle  .no_max                    ; 有符号比较：arr[i] <= max 就不更新
    mov  r12, r14
.no_max:
    cmp  r14, r13
    jge  .no_min                    ; 有符号比较：arr[i] >= min 就不更新
    mov  r13, r14
.no_min:

    mov  rdi, r14                   ; 打印这个元素
    call io_print_int
    inc  rbp                        ; i++
    cmp  rbp, arr_len
    jge  .loop_done                 ; 最后一个元素后面不加逗号
    lea  rsi, [rel s_comma]
    mov  rdx, l_comma
    call io_print
    jmp  .loop

.loop_done:
    lea  rsi, [rel t_arr_e]
    mov  rdx, l_arr_e
    call io_print                   ; 打印 "]" 和换行

; ---------------------------------------------------------------------------
; 4) 打印最大值和最小值
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_max]
    mov  rdx, l_max
    call io_print
    mov  rdi, r12
    call io_print_int
    call io_newline

    lea  rsi, [rel t_min]
    mov  rdx, l_min
    call io_print
    mov  rdi, r13
    call io_print_int
    call io_newline

; ---------------------------------------------------------------------------
; 结束进程
; ---------------------------------------------------------------------------
    xor  edi, edi
    call io_exit

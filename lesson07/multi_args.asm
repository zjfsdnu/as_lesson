; ===========================================================================
; multi_args.asm —— 第 07 课示例 3：6 个参数怎么传（寄存器 + 栈）
;
; 编译（在 lesson07 目录下）：
;   make
; 运行：
;   ./multi_args
;
; System V AMD64 调用约定规定，整数/指针参数按顺序放进：
;   第 1 个 rdi、第 2 个 rsi、第 3 个 rdx、第 4 个 rcx、第 5 个 r8、第 6 个 r9
; 超出的第 7、8、… 个参数才压栈（从右往左压），返回值永远在 rax。
;
; 注意返回值不够用时（比如要返回两个值），rax 只能放一个，
; 另一个就得靠「调用者传进来的内存地址」写回去（见 README 里的说明）。
; ===========================================================================

section .data
    title      db "=== sum6(a,b,c,d,e,f)：参数依次进 rdi,rsi,rdx,rcx,r8,r9 ==="
    title_len  equ $ - title

    l_head     db "  a    b    c    d    e    f   | 和"
    l_head_len equ $ - l_head

    l_case     db "sum6(1,2,3,4,5,6)      = "
    l_case_len equ $ - l_case

    l_case2    db "sum6(10,20,30,40,50,60) = "
    l_case2_len equ $ - l_case2

    l_neg      db "sum6(-1,-2,-3,-4,-5,-6) = "
    l_neg_len  equ $ - l_neg

    l_all      db "sum6(100,200,300,400,500,600) = "
    l_all_len  equ $ - l_all

    l_seven    db "sum7(a..f, 第 7 个参数在栈上) = "
    l_seven_len equ $ - l_seven

    l_stack    db "  第 7 个参数写在栈上：[rsp+8] 就是它（[rsp] 是返回地址）"
    l_stack_len equ $ - l_stack

    ; 一批演示数据（情形 2 用）
    d1         dq 10
    d2         dq 20
    d3         dq 30
    d4         dq 40
    d5         dq 50
    d6         dq 60

section .text
    global _start
default rel                             ; 数据寻址默认 RIP 相对，所有 [标签] 都自动变成 [rel 标签]
bits 64

%include "io.inc"

_start:
    lea rsi, [rel title]
    mov rdx, title_len
    call io_println

    lea rsi, [rel l_head]
    mov rdx, l_head_len
    call io_println

    ; ---- 情形 1：六个立即数 ---------------------------------------------
    ; 把 6 个数依次放进 6 个参数寄存器。放的顺序无所谓，
    ; 只要别用错寄存器就行。
    lea rsi, [rel l_case]
    mov rdx, l_case_len
    call io_print               ; ← 先把标题打出去，rsi/rdx 才能腾出来当参数

    mov rdi, 1
    mov rsi, 2                  ; ⚠ rsi 又被借用了，但上一行的打印已经完成
    mov rdx, 3
    mov rcx, 4
    mov r8,  5
    mov r9,  6
    call sum6
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 情形 2：六个变量 -----------------------------------------------
    lea rsi, [rel l_case2]
    mov rdx, l_case2_len
    call io_print

    mov rdi, [rel d1]
    mov rsi, [rel d2]
    mov rdx, [rel d3]
    mov rcx, [rel d4]
    mov r8,  [rel d5]
    mov r9,  [rel d6]
    call sum6
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 情形 3：全负数（再次提醒负数与标号位数）------------------------
    lea rsi, [rel l_neg]
    mov rdx, l_neg_len
    call io_print

    mov rdi, -1
    mov rsi, -2
    mov rdx, -3
    mov rcx, -4
    mov r8,  -5
    mov r9,  -6
    call sum6
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 情形 4：大一点的数 ---------------------------------------------
    lea rsi, [rel l_all]
    mov rdx, l_all_len
    call io_print

    mov rdi, 100
    mov rsi, 200
    mov rdx, 300
    mov rcx, 400
    mov r8,  500
    mov r9,  600
    call sum6
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 情形 5：第 7 个参数必须走栈 ------------------------------------
    lea rsi, [rel l_seven]
    mov rdx, l_seven_len
    call io_print

    mov rdi, 1
    mov rsi, 2
    mov rdx, 3
    mov rcx, 4
    mov r8,  5
    mov r9,  6
    push qword 7                ; 第 7 个参数：压栈
                                ; 压完 rsp 还是 16 的倍数，call 时就有
                                ; 「rsp+8 是 16 的倍数」这个标准状态
    call sum7
    add rsp, 8                  ; 调用完必须把参数收回来，保持 rsp 平衡
    mov rdi, rax
    call io_print_int
    call io_newline

    lea rsi, [rel l_stack]
    mov rdx, l_stack_len
    call io_println

    xor rdi, rdi
    call io_exit

; ---------------------------------------------------------------------------
; sum6 —— 返回 a+b+c+d+e+f
;
;   入参：rdi=a, rsi=b, rdx=c, rcx=d, r8=e, r9=f
;   返回：rax = 六个数的和
;
;   函数体里只碰了 rax、rdi、rsi、rdx、rcx、r8、r9，
;   全是可以随便改的「调用者保存」寄存器，所以不用 push/pop。
;   累加时特意用 add rax, rXX 一个个加，方便对照它的参数寄存器。
; ---------------------------------------------------------------------------
sum6:
    mov rax, rdi                ; rax = a
    add rax, rsi                ; + b
    add rax, rdx                ; + c
    add rax, rcx                ; + d
    add rax, r8                 ; + e
    add rax, r9                 ; + f
    ret

; ---------------------------------------------------------------------------
; sum7 —— 返回 7 个数的和，第 7 个数在栈上
;
;   入参：rdi..r9 = 前 6 个，栈上 [rsp+8] = 第 7 个（[rsp] 是返回地址）
;   返回：rax
;
;   为什么是 [rsp+8] 而不是 [rsp]？
;   因为 call sum7 先把返回地址压在了栈顶，第 7 个参数在它上面一格。
;   用 rbp 建立帧之后就是 [rbp+16]，两种写法等价（见 README）。
; ---------------------------------------------------------------------------
sum7:
    mov rax, rdi
    add rax, rsi
    add rax, rdx
    add rax, rcx
    add rax, r8
    add rax, r9
    add rax, [rsp + 8]          ; 第 7 个参数在栈上
    ret

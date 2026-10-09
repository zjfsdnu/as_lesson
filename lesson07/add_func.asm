; ===========================================================================
; add_func.asm —— 第 07 课示例 1：第一个函数（call / ret / 返回值在 rax）
;
; 编译（在 lesson07 目录下）：
;   make
; 运行：
;   ./add_func
;
; 知识点：
;   * call 标签 —— 把「返回地址」压栈，然后跳到标签处执行
;   * ret       —— 从栈顶弹出返回地址，跳回去
;   * 参数按 System V 约定放在 rdi, rsi（第 1、2 个参数）
;   * 返回值放在 rax
;   * 被调用者保存（rbx/rbp/r12-r15）与调用者保存的含义
; ===========================================================================

section .data
    ; ---- 提示文字 -------------------------------------------------------
    title      db "=== add_two(a, b)：参数用 rdi/rsi，返回值用 rax ==="
    title_len  equ $ - title

    l_test     db "add_two(a_value, b_value)   = "
    l_test_len equ $ - l_test

    l_inline   db "add_two(1000, 2345)         = "
    l_inline_len equ $ - l_inline

    l_neg      db "add_two(7, -20)             = "
    l_neg_len  equ $ - l_neg

    l_wrap     db "add_two(1, -1)              = "
    l_wrap_len equ $ - l_wrap

    l_four     db "add_four(r12, rbx, 100, -5) = "
    l_four_len equ $ - l_four

    l_after    db "函数返回后 rbx（还是 22）   = "
    l_after_len equ $ - l_after

    ; ---- 演示用的操作数 -------------------------------------------------
    a_value    dq 12
    b_value    dq 30

section .text
    global _start
default rel                             ; 数据寻址默认 RIP 相对，所有 [标签] 都自动变成 [rel 标签]
bits 64

%include "io.inc"

; ---------------------------------------------------------------------------
; _start —— 程序入口（相当于 C 的 main）
; ---------------------------------------------------------------------------
_start:
    ; 打印标题
    lea rsi, [rel title]
    mov rdx, title_len
    call io_println

    ; ---- 第 1 个调用：参数来自内存里的变量 ------------------------------
    lea rsi, [rel l_test]
    mov rdx, l_test_len
    call io_print

    mov rdi, [rel a_value]      ; 第 1 个参数 = 12
    mov rsi, [rel b_value]      ; 第 2 个参数 = 30
    call add_two                ; 返回值在 rax
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 第 2 个调用：参数是立即数 --------------------------------------
    lea rsi, [rel l_inline]
    mov rdx, l_inline_len
    call io_print

    mov edi, 1000
    mov esi, 2345
    call add_two
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 第 3 个调用：带负数（补码加法，和 C 的 int64_t 一样） ----------
    lea rsi, [rel l_neg]
    mov rdx, l_neg_len
    call io_print

    mov rdi, 7
    mov rsi, -20                ; 有符号立即数可以直接写 -20
    call add_two
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 第 4 个调用：1 + (-1) = 0，顺便看 -1 的 64 位补码 --------------
    lea rsi, [rel l_wrap]
    mov rdx, l_wrap_len
    call io_print

    mov rdi, 1
    mov rsi, -1                 ; -1 的 64 位补码就是 0xFFFFFFFFFFFFFFFF
    call add_two
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 第 5 个调用：嵌套调用 + 被调用者保存寄存器 ---------------------
    mov r12, 20                 ; r12 是被调用者保存寄存器
    mov rbx, 22                 ; rbx 也是

    lea rsi, [rel l_four]
    mov rdx, l_four_len
    call io_print

    ; 按 rdi, rsi, rdx, rcx 的顺序放第 1..4 个参数
    mov rdi, r12
    mov rsi, rbx
    mov rdx, 100                ; 写 rdx 而不是 edx，风格统一
    mov rcx, -5                 ; ⚠ 负数千万别写 mov ecx, -5（见 README「常见坑」）
    call add_four               ; 内部会调用 add_two_rbx（故意破坏 rbx）
    mov rdi, rax
    call io_print_int
    call io_newline

    ; 如果 add_two_rbx 老老实实保存、恢复了 rbx，这里 rbx 还应该是 22
    lea rsi, [rel l_after]
    mov rdx, l_after_len
    call io_print
    mov rdi, rbx
    call io_print_int
    call io_newline

    ; ---- 正常退出：退出码 0 --------------------------------------------
    xor rdi, rdi
    call io_exit

; ---------------------------------------------------------------------------
; add_two —— 返回 rdi + rsi
;
;   入参：rdi = 第一个数，rsi = 第二个数
;   返回：rax = 两数之和
;   只用到调用者保存寄存器 rax，所以不需要 push/pop
; ---------------------------------------------------------------------------
add_two:
    mov rax, rdi
    add rax, rsi
    ret

; ---------------------------------------------------------------------------
; add_two_rbx —— 和 add_two 一样，但故意把 rbx 写坏
;
;   目的：演示「被调用者保存」的规矩 —— 谁破坏 rbx，谁负责恢复。
; ---------------------------------------------------------------------------
add_two_rbx:
    push rbx                    ; 先保存调用者的 rbx
    mov rbx, rdi
    add rbx, rsi
    mov rax, rbx
    pop rbx                     ; 返回前恢复，调用者感觉不到 rbx 被用过
    ret

; ---------------------------------------------------------------------------
; add_four —— 返回 a+b+c+d，内部调用 add_two_rbx
;
;   入参：rdi=a, rsi=b, rdx=c, rcx=d
;   返回：rax = a+b+c+d
;
;   注意栈的对齐：这里 push/pop 严格成对（2 个 push、2 个 pop），
;   add_two_rbx 内部也是 1 个 push、1 个 pop，
;   所以进每个函数时 rsp 的对齐状态一路保持不变（详见 README「栈对齐」）。
; ---------------------------------------------------------------------------
add_four:
    push rbp                    ; 标准函数序言
    mov rbp, rsp                ; rbp 指向「栈上保存的旧 rbp」
    push rbx                    ; 本函数要用 rbx，先保存
    push r12                    ; 也要用 r12，先保存（push 两个，对齐不变）

    mov r12, rdx                ; 先把 c 存进 r12（rdx 马上就要被用掉了）
    mov rbx, rcx                ; 再把 d 存进 rbx

    call add_two_rbx            ; 算 a + b（参数已经在 rdi/rsi 里）
    add rax, r12                ; 加 c
    add rax, rbx                ; 加 d

    pop r12
    pop rbx
    leave                       ; = mov rsp, rbp + pop rbp
    ret

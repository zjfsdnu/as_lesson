; ===========================================================================
; wc.asm —— 第 09 课示例 2：统计文件的字节数 / 行数 / 单词数
;
; 编译（在 lesson09 目录下）：
;   make
; 用法：
;   ./wc 文件名
;   ./wc            # 不写文件名就从标准输入读
; 例子：
;   printf 'hello world\nfoo bar\n' > /tmp/t.txt
;   ./wc /tmp/t.txt
;   printf 'a b\n' | ./wc
;
; 输出三列（和系统的 wc 默认顺序一致）：
;   行数  单词数  字节数  文件名
;
; 和 copy.asm 相比，这里多学三点：
;   1. 统计要「跨缓冲区边界」仍然正确 —— 一个单词可能正好被切成两半，
;      所以「当前是否在单词里」这个状态必须保留到下一轮（存在 rbp 里）；
;   2. 不带参数时从标准输入（fd 0）读，让程序更实用；
;   3. 右对齐输出：先算数字有几位，再补空格（print_padded）。
; ===========================================================================

%define AT_FDCWD -100

section .data
    dash        db "-"
    dash_len    equ $ - dash
    dash_nul    db 0            ; ⚠ cstr_len 需要 NUL 结尾，所以单独补一个 0
                                ;   （这样 dash_len 还是 1，不会被算进去）

    e_open      db "wc: 打不开文件: "
    e_open_len  equ $ - e_open

    e_read      db "wc: 读取出错"
    e_read_len  equ $ - e_read

    buf_size    equ 65536       ; 64 KiB（8 的倍数，保持栈对齐）

section .bss
    argv_base   resq 1          ; 保存 &argv[0]（程序一开始从栈上取下来的）
    buf         resb buf_size   ; 读取缓冲区
    nbytes      resq 1          ; 字节数
    nlines      resq 1          ; 行数
    nwords      resq 1          ; 单词数

section .text
    global _start
default rel                             ; 数据寻址默认 RIP 相对，所有 [标签] 都自动变成 [rel 标签]
bits 64

%include "io.inc"

_start:
    ; ---- 0. 取 argc / argv（必须在任何 push 之前）-----------------------
    mov r12, [rsp]              ; r12 = argc
    lea rax, [rsp + 8]
    mov [rel argv_base], rax    ; 把 &argv[0] 存到 .bss
                                ; （不用寄存器存它：r12-r15 下面都有正经用途）

    mov rbx, STDIN              ; rbx = 要读的文件描述符，默认标准输入
    lea r14, [rel dash]         ; r14 = 显示用的文件名，默认 "-"（NUL 结尾）
                                ;       （很多工具的惯例：stdin 显示成 -）

    cmp r12, 2                  ; 有给文件名吗？
    jl .count                   ; argc < 2：从标准输入读

    mov rax, [rel argv_base]
    mov r14, [rax + 8]          ; r14 = argv[1]，也就是文件名

    ; openat(AT_FDCWD, 文件名, O_RDONLY)
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r14                ; 路径
    mov rdx, O_RDONLY
    xor r10d, r10d
    syscall

    test rax, rax
    jns .opened
    ; 打开失败：打印错误并退出（退出码 2）
    lea rsi, [rel e_open]
    mov rdx, e_open_len
    call io_print
    mov rsi, r14
    call cstr_len
    mov rdx, rax
    call io_println
    mov rdi, 2
    call io_exit

.opened:
    mov rbx, rax                ; rbx = 真正的文件描述符

.count:
    ; ---- 1. 初始化计数器 ------------------------------------------------
    mov qword [rel nbytes], 0
    mov qword [rel nlines], 0
    mov qword [rel nwords], 0
    xor ebp, ebp                ; rbp = 「当前是否在单词里」：0 不在 / 1 在

    ; ---- 2. 读-统计循环 -------------------------------------------------
.read_loop:
    mov rax, SYS_read
    mov rdi, rbx                ; 读哪个 fd
    lea rsi, [rel buf]          ; 缓冲区
    mov rdx, buf_size
    syscall                     ; ⚠ 这之后 rcx、r11 不可信

    test rax, rax
    js .read_err                ; 负数 = 出错
    jz .report                  ; 0 = EOF，统计完了

    add [rel nbytes], rax       ; 字节数直接累加

    mov r15, rax                ; r15 = 本轮读到的字节数（跨下面的调用保持）
    xor ecx, ecx                ; rcx = 本轮已处理的下标
                                ;     本轮里没有 syscall，所以用它没问题

.byte_loop:
    lea rsi, [rel buf]
    movzx eax, byte [rsi + rcx] ; 取第 rcx 个字节

    ; ---- 2.1 行数：数 '\n' 的个数 ---------------------------------------
    cmp al, LF
    jne .word_part
    inc qword [rel nlines]

    ; ---- 2.2 单词边界：分隔符 -> 非分隔符 才算一个新单词 ----------------
.word_part:
    xor r8d, r8d                ; r8 = 0：先假设不是分隔符
    cmp al, ' '
    je .is_sep
    cmp al, TAB
    je .is_sep
    cmp al, LF
    je .is_sep
    cmp al, 13                  ; '\r'
    je .is_sep
    cmp al, 12                  ; '\f'
    je .is_sep
    cmp al, 11                  ; '\v'
    je .is_sep
    jmp .sep_done
.is_sep:
    mov r8d, 1
.sep_done:

    test r8d, r8d
    jz .not_sep
    xor ebp, ebp                ; 是分隔符：离开单词状态
    jmp .next_byte

.not_sep:
    test rbp, rbp
    jnz .next_byte              ; 本来就在单词里，不重复计数
    inc qword [rel nwords]      ; 从「不在单词里」变成「在单词里」
    mov ebp, 1

.next_byte:
    inc rcx
    cmp rcx, r15
    jb .byte_loop               ; 本轮还没处理完
    jmp .read_loop              ; 继续读下一块

.report:
    ; ---- 3. 打开过文件就先关掉 ------------------------------------------
    cmp rbx, STDIN
    je .print
    mov rax, SYS_close
    mov rdi, rbx
    syscall                     ; 关闭失败也没关系，统计结果已经拿到了

.print:
    ; ---- 4. 三列输出，每列右对齐 7 位，最后跟文件名 ---------------------
    ; 列的顺序和系统 wc 一样：行、词、字节
    ;
    ; ⚠ 调用约定小提醒：rdi 放数值、rsi 放列宽，两个都要设对。
    ;   如果中间插了 lea rsi, [...] 之类的指令，就会把列宽冲掉。
    mov rdi, [rel nlines]
    mov rsi, 7
    call print_padded

    mov rdi, [rel nwords]
    mov rsi, 7
    call print_padded

    mov rdi, [rel nbytes]
    mov rsi, 7
    call print_padded

    mov edi, ' '
    call io_putchar
    mov rsi, r14                ; 文件名（或者 "-"）
    call cstr_len
    mov rdx, rax
    call io_println

    xor rdi, rdi
    call io_exit

.read_err:
    lea rsi, [rel e_read]
    mov rdx, e_read_len
    call io_println
    mov rdi, 3
    call io_exit

; ---------------------------------------------------------------------------
; print_padded —— 把 rdi 里的无符号数以「右对齐 rsi 列」的方式打印
;
;   入参：rdi = 数值，rsi = 列宽
;   例子：print_padded(42, 7) 会输出 "     42"（5 个空格 + 两位数字）
;   做法：先算数字有几位，再补「列宽 - 位数」个空格。
; ---------------------------------------------------------------------------
print_padded:
    push rbx                    ; 本函数要用 rbx/r12/r13，先保存
    push r12
    push r13

    mov r12, rdi                ; r12 = 要打印的数值
    mov r13, rsi                ; r13 = 列宽

    ; ---- 1. 数一数这个数有几位（0 也算 1 位）----------------------------
    ; 这段没有 syscall，用 rcx 当除数完全安全
    mov rbx, 1                  ; rbx = 位数
    mov rax, r12
.digit_count:
    cmp rax, 10
    jb .counted
    xor rdx, rdx
    mov rcx, 10
    div rcx                     ; rax /= 10
    inc rbx
    jmp .digit_count

.counted:
    mov rax, r13
    sub rax, rbx                ; rax = 需要补的空格数 = 列宽 - 位数
    mov rbx, rax                ; ⚠ 计数器放 rbx（被调用者保存）
                                ;   io_putchar 内部有 syscall，而内核会破坏 rcx；
                                ;   拿 rcx 计数会变成天文数字，最后把栈都冲掉
    test rbx, rbx
    jle .print_num              ; 不需要补空格就直接打印
.pad:
    mov edi, ' '
    call io_putchar
    dec rbx
    jnz .pad

.print_num:
    mov rdi, r12
    call print_u64

    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; cstr_len —— 求 rsi 指向的 NUL 结尾字符串长度
;   返回：rax = 长度
; ---------------------------------------------------------------------------
cstr_len:
    xor eax, eax
.loop:
    cmp byte [rsi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; ---------------------------------------------------------------------------
; print_u64 —— 无符号十进制输出（栈上开缓冲区，从末尾往前填）
;   入参：rdi = 数值
; ---------------------------------------------------------------------------
print_u64:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32                 ; 缓冲区必须在 push 之后再开

    mov rax, rdi
    mov rbx, 10
    lea r12, [rsp + 32]
.loop:
    xor rdx, rdx                ; div 前清零 rdx
    div rbx
    add dl, '0'
    dec r12
    mov [r12], dl
    test rax, rax
    jnz .loop

    mov rsi, r12
    lea rdx, [rsp + 32]
    sub rdx, r12
    call io_print

    add rsp, 32
    pop r12
    pop rbx
    leave
    ret

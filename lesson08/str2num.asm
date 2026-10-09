; ===========================================================================
; str2num.asm —— 第 08 课示例 2：十进制字符串 → 整数（atoi 的原理）
;
; 编译（在 lesson08 目录下）：
;   make
; 运行：
;   ./str2num
;   printf '  12345\n' | ./str2num      # 从标准输入读一行再转换
;
; 本程序要处理 atoi 的四个老大难问题：
;   1. 正负号：'+' / '-' 只能出现在开头，'-' 还要照顾好 INT64_MIN；
;   2. 非法字符：遇到不是 '0'..'9' 的字节，要分得清它是「字符串结束符」
;      还是「垃圾字符」；
;   3. 溢出：乘 10 或加本位之后超出 [INT64_MIN, INT64_MAX]；
;   4. 空串 / 只有符号：不能当成 0 蒙混过关。
;
; 解析核心：value = value * 10 + (c - '0')
; 溢出判断用了一个很实用的技巧（见 parse_str 里的注释）：
;   如果 value*10 溢出，那么 (value*10 / 10) 就不再等于原来的 value。
; ===========================================================================

section .data
    ; ---- 提示文字 -------------------------------------------------------
    title      db "=== 字符串 -> 整数（atoi 手写实现）==="
    title_len  equ $ - title

    l_head     db "输入                    值(十进制)                值(十六进制)          位数  状态"
    l_head_len equ $ - l_head

    ; ---- 内建测试用例（每个都以 NUL 结尾）-------------------------------
    t1         db "12345", 0
    t2         db "-987", 0
    t3         db "+42", 0
    t4         db "0000", 0
    t5         db "9223372036854775807", 0        ; INT64_MAX
    t6         db "-9223372036854775808", 0       ; INT64_MIN
    t7         db "9223372036854775808", 0        ; 比 INT64_MAX 大 1：溢出
    t8         db "99999999999999999999", 0       ; 远远溢出
    t9         db 0                                ; 真正的空串
    t10        db "-", 0                          ; 只有符号
    t11        db "12a3", 0                       ; 中间夹了非法字符

    ; 指针表：dq 存的是各字符串的地址，配合循环遍历
    table      dq t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11
    table_cnt  equ ($ - table) / 8

    ; 状态码对应的文字
    txt_ok        db "OK"
    txt_ok_len    equ $ - txt_ok
    txt_bad        db "非法字符"
    txt_bad_len    equ $ - txt_bad
    txt_ovf        db "溢出"
    txt_ovf_len    equ $ - txt_ovf
    txt_nul        db "空指针"
    txt_nul_len    equ $ - txt_nul
    txt_emp        db "空串/只有符号"
    txt_emp_len    equ $ - txt_emp

    ; ---- 从标准输入读的那个演示 -----------------------------------------
    l_stdin    db "--- 从标准输入读一行（可用 printf '...' | ./str2num 喂进去）---"
    l_stdin_len equ $ - l_stdin

    l_prompt   db "读出（已去掉换行）= "
    l_prompt_len equ $ - l_prompt

    l_eof      db "读到 0 字节（EOF），没有输入可解析，直接退出。"
    l_eof_len  equ $ - l_eof

    empty_mark db "(空串)"
    empty_mark_len equ $ - empty_mark

section .bss
    inbuf      resb 64          ; 读标准输入用的缓冲区

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

    ; ---- 遍历内建用例表 --------------------------------------------------
    lea rbx, [rel table]        ; rbx 指向指针表（rbx 被调用者保存）
    mov rbp, table_cnt          ; rbp 当循环计数器（同样被调用者保存）

.next:
    mov rdi, [rbx]              ; rdi = 当前测试字符串
    call show_one
    add rbx, 8
    dec rbp
    jnz .next

    call io_newline

    ; ---- 从标准输入读一行 ------------------------------------------------
    lea rsi, [rel l_stdin]
    mov rdx, l_stdin_len
    call io_println

    ; read(0, inbuf, 64)：从标准输入最多读 64 字节
    xor edi, edi                ; fd = STDIN
    lea rsi, [rel inbuf]
    mov edx, 64
    mov rax, SYS_read
    syscall                     ; 返回值在 rax（负数表示出错）

    test rax, rax
    jle .eof                    ; 0 = EOF，负数 = 错误，都直接收工

    ; ---- 手工去掉结尾的 '\n' 和 '\r' ------------------------------------
    mov rcx, rax                ; rcx = 读到的字节数
    lea rdi, [rel inbuf]
.strip:
    test rcx, rcx
    jz .stripped
    mov al, [rdi + rcx - 1]     ; 看最后一个字节
    cmp al, LF
    je .cut
    cmp al, 13                  ; '\r'（Windows 换行）
    je .cut
    jmp .stripped
.cut:
    dec rcx
    jmp .strip
.stripped:
    mov byte [rdi + rcx], 0     ; 打上字符串结束符

    lea rsi, [rel l_prompt]
    mov rdx, l_prompt_len
    call io_print
    lea rsi, [rel inbuf]
    mov rdx, rcx                ; 长度 = 去掉换行后的字节数
    call io_println

    lea rdi, [rel inbuf]
    call show_one

    xor rdi, rdi
    call io_exit

.eof:
    lea rsi, [rel l_eof]
    mov rdx, l_eof_len
    call io_println
    xor rdi, rdi
    call io_exit

; ---------------------------------------------------------------------------
; show_one —— 解析并打印一个用例：输入串、值、十六进制、位数、状态
;
;   入参：rdi = 指向 NUL 结尾字符串的指针
;   如果字符串是空串（连符号都没有），终端里什么都看不见，
;   所以显示的时候换成 "(空串)" 字样，解析时用的还是那个空串本身。
; ---------------------------------------------------------------------------
show_one:
    push rbx                    ; 要用 rbx/r12-r15 存跨调用的值，先保存
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                ; rbx = 要解析的字符串

    cmp byte [rbx], 0           ; 真·空串？
    jne .parse
    lea rdi, [rel empty_mark + empty_mark_len]  ; 解析用末尾的 NUL
    mov rbx, rdi
    sub rbx, empty_mark_len     ; 但显示的时候换成 "(空串)" 字样
.parse:
    call parse_str
    mov r12, rax                ; r12 = 值
    mov r13, rdx                ; r13 = 状态码
    mov r14, rcx                ; r14 = 位数（要留到第四列）

    ; ---- 第一列：输入字符串，不足 20 列补空格 ---------------------------
    mov rsi, rbx
    call cstr_len
    mov r15, rax                ; r15 = 这一列的长度（r14 要留着装位数）
    mov rsi, rbx
    mov rdx, r15
    call io_print
    mov rdi, 21                 ; 第一列固定 21 列
    sub rdi, r15                ; 还要补几个空格
    call print_spaces

    ; ---- 第二列：值（十进制，末尾补两格）-------------------------------
    mov rdi, r12
    call print_int64
    mov edi, ' '
    call io_putchar
    call io_putchar
    call io_putchar             ; 多补几格，让 19 位数也留出间距

    ; ---- 第三列：十六进制 ------------------------------------------------
    mov rdi, r12
    call io_print_hex
    mov edi, ' '
    call io_putchar
    call io_putchar
    call io_putchar
    call io_putchar

    ; ---- 第四列：位数 ----------------------------------------------------
    mov rdi, r14
    call print_u64
    mov edi, ' '
    call io_putchar
    mov edi, ' '
    call io_putchar

    ; ---- 第五列：状态 ----------------------------------------------------
    mov rdx, r13
    call print_status

    call io_newline

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; parse_str —— 把 rdi 指向的十进制字符串转成 64 位有符号整数
;
;   入参：rdi = 指向 NUL 结尾字符串的指针
;   返回：rax = 解析出的数值
;         rdx = 状态码：0 成功 / 1 非法字符 / 2 溢出 / 3 空指针 / 4 空串或只有符号
;         rcx = 有效数字位数（不含 '+'/'-'；状态不为 0 时无意义）
;
;   寄存器分工（故意全用「被调用者保存」寄存器，因为中途要调 io_putchar）：
;         rbx = 扫描指针
;         r12 = 累加器 value
;         r13 = 符号标志（0 = 正，1 = 负）
;         r14 = 常量 '0'
;         r15 = 第一个数字的位置（最后用它算位数）
;
;   溢出检测两处：
;     * value*10 溢出 —— 乘完再除以 10，回不到原来的 value；
;     * + digit 溢出  —— 64 位无符号加法进位（jc）。
;   最后再按符号和 INT64_MAX / INT64_MIN 比较。
; ---------------------------------------------------------------------------
parse_str:
    push rbx
    push r12
    push r13
    push r14
    push r15                    ; 5 个 push 是奇数：进函数时 rsp ≡ 8 (mod 16)，
                                ; 5*8 = 40 之后 rsp ≡ 0 (mod 16)，
                                ; 函数体里 call 就满足「rsp 是 16 的倍数」

    ; ---- 0. 空指针检查（防止调用者忘了判空） ----------------------------
    test rdi, rdi
    jnz .have_ptr
    xor eax, eax
    mov rdx, 3
    xor ecx, ecx
    jmp .ret

.have_ptr:
    mov rbx, rdi                ; 扫描指针
    xor r12, r12                ; value = 0
    xor r13, r13                ; 符号 = 正

    ; ---- 1. 跳过开头的空白字符（空格 / TAB / 回车 / 换行）--------------
    ; 「  -12345」这种输入很常见（从终端读进来时尤其如此），
    ; 真正的 atoi 也是这么处理的
.skip_ws:
    mov al, [rbx]
    cmp al, ' '
    je .ws
    cmp al, TAB
    je .ws
    cmp al, 13
    je .ws
    cmp al, LF
    jne .sign
.ws:
    inc rbx
    jmp .skip_ws

    ; ---- 2. 可选的正负号（只认第一个非空白字符）------------------------
.sign:
    mov al, [rbx]
    cmp al, '-'
    jne .chk_plus
    mov r13, 1
    inc rbx
    jmp .digits
.chk_plus:
    cmp al, '+'
    jne .digits
    inc rbx

.digits:
    mov r15, rbx                ; 记下第一个数字的位置
    mov r14b, '0'               ; 常量 '0' 暂放 r14 低 8 位（本函数没别人用 r14）

.loop:
    movzx eax, byte [rbx]       ; 读一个字节（movzx：高位清零）
    test al, al
    jz .end                     ; NUL：字符串正常结束
    sub al, r14b                ; al = c - '0'
    cmp al, 9
    ja .bad_char                ; 不是 '0'..'9'

    ; --- value = value * 10 + digit，带两处溢出检查 ---------------------
    ; ⚠ 不要把 digit 暂存在 ah 里！div 会写 rax，把 ah 一起冲掉
    ;   （这个坑在 README 里也会讲）。这里用 r8 这个「调用者保存」寄存器。
    movzx r8d, al               ; r8 = digit（下面一直要活着）

    mov rcx, r12                ; rcx = 乘之前的 value
    imul r12, r12, 10           ; r12 *= 10
    mov rax, r12
    xor edx, edx
    mov r9, 10
    div r9                      ; rax = (value*10) / 10
    cmp rax, rcx
    jne .overflow               ; 除不回来 -> 乘 10 时就溢出了

    add r12, r8                 ; value += digit
    jc .overflow                ; 无符号加法进位 -> 溢出

    inc rbx
    jmp .loop

.bad_char:
    mov rdx, 1
    xor eax, eax
    xor ecx, ecx
    jmp .ret

.end:
    mov rcx, rbx
    sub rcx, r15                ; 位数 = 扫描位置 - 第一个数字的位置
    test rcx, rcx
    jz .empty                   ; 一个数字都没读到："", "-", "+"

    test r13, r13
    jnz .neg

    mov rax, 0x7fffffffffffffff ; INT64_MAX
    cmp r12, rax
    ja .overflow
    mov rax, r12
    xor rdx, rdx
    jmp .ret

.neg:
    ; 负数最小可以到 -2^63，即无符号写法 0x8000000000000000
    mov rax, 0x8000000000000000
    cmp r12, rax
    ja .overflow
    mov rax, r12
    neg rax                     ; 取负；0x8000000000000000 取负还是它自己
    xor rdx, rdx
    jmp .ret

.empty:
    xor eax, eax
    mov rdx, 4
    xor ecx, ecx
    jmp .ret

.overflow:
    xor eax, eax
    mov rdx, 2
    xor ecx, ecx
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; 下面是给示例配套的小工具函数
; ---------------------------------------------------------------------------

; str_eq —— 比较 rdi 和 rsi 两个 NUL 结尾字符串
;   返回：rax = 1 相等 / 0 不等
str_eq:
    xor eax, eax
.loop:
    mov cl, [rdi]
    mov dl, [rsi]
    cmp cl, dl
    jne .no
    test cl, cl
    jz .yes                     ; 同时到 NUL：相等
    inc rdi
    inc rsi
    jmp .loop
.yes:
    mov eax, 1
.no:
    ret

; cstr_len —— 求 rsi 指向的 NUL 结尾字符串长度
;   返回：rax = 长度（不含 NUL）
cstr_len:
    xor eax, eax
.loop:
    cmp byte [rsi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; print_spaces —— 打印 rdi 个空格
;   入参：rdi = 个数（<= 0 时什么都不打）
print_spaces:
    push rbx
    mov rbx, rdi
    test rbx, rbx
    jle .done
.loop:
    mov rdi, ' '
    call io_putchar
    dec rbx
    jnz .loop
.done:
    pop rbx
    ret

; print_int64 —— 自己写的有符号十进制输出（负数先打 '-' 再取绝对值）
;   入参：rdi = 有符号整数
print_int64:
    test rdi, rdi
    js .neg
    jmp print_u64
.neg:
    push rdi
    mov rdi, '-'
    call io_putchar
    pop rdi
    mov rax, rdi
    neg rax
    mov rdi, rax
    jmp print_u64

; print_u64 —— 无符号十进制输出（栈上开缓冲区，从末尾往前填）
;   入参：rdi = 无符号整数
print_u64:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32                 ; ⚠ 缓冲区必须在 push 之后开

    mov rax, rdi
    mov rbx, 10
    lea r12, [rsp + 32]         ; 缓冲区末尾
.loop:
    xor rdx, rdx                ; ⚠ div 前清零
    div rbx
    add dl, '0'
    dec r12
    mov [r12], dl
    test rax, rax
    jnz .loop

    mov rsi, r12
    lea rdx, [rsp + 32]
    sub rdx, r12                ; 长度
    call io_print

    add rsp, 32
    pop r12
    pop rbx
    leave
    ret

; print_status —— 打印状态码对应的文字
;   入参：rdx = 状态码
print_status:
    cmp rdx, 0
    je .s0
    cmp rdx, 1
    je .s1
    cmp rdx, 2
    je .s2
    cmp rdx, 3
    je .s3
    lea rsi, [rel txt_emp]
    mov rdx, txt_emp_len
    jmp io_print
.s0:
    lea rsi, [rel txt_ok]
    mov rdx, txt_ok_len
    jmp io_print
.s1:
    lea rsi, [rel txt_bad]
    mov rdx, txt_bad_len
    jmp io_print
.s2:
    lea rsi, [rel txt_ovf]
    mov rdx, txt_ovf_len
    jmp io_print
.s3:
    lea rsi, [rel txt_nul]
    mov rdx, txt_nul_len
    jmp io_print

; ===========================================================================
; io.inc —— 面向初学者的输入输出小工具（纯系统调用实现，不依赖 libc）
;
; 用法：  %include "io.inc"
;   ⚠ 同一个程序里只能 %include 一次，否则函数会重复定义。
;   ⚠ 只在「纯 syscall 程序」里用（入口 _start、用 ld 链接）。
;     要用 printf 的 libc 程序（lc_ 前缀、入口 main）不要 include 本文件。
;
; 【寄存器契约】下面这些例程统一保证：
;   * 只破坏 rax、rcx、r11
;       - rax：返回值 / 系统调用号
;       - rcx、r11：syscall 指令本身必然破坏（内核用它们存 rip 和 rflags）
;   * rdi、rsi、rdx、rbx、rbp、r12 ~ r15 调用前后**保持不变**
;     （即使某个例程内部把 rdi 当入参、把 rdx 当长度用，返回前也会恢复）
;   所以：想安全就把跨调用的值放 rbx/rbp/r12~r15（它们本来就是「被调用者保存」）；
;   在本文件的例程面前，rdi/rsi/rdx 也是安全的。
;   唯一例外是 io_exit —— 它不返回，自然不会替你恢复任何东西。
;
; 函数一览（参数用寄存器传递）：
;   io_write(rdi=fd, rsi=缓冲区, rdx=长度)      写任意数据，rax=写入字节数
;   io_print(rsi=字符串首地址, rdx=长度)        写到 stdout
;   io_println(rsi=字符串首地址, rdx=长度)      写到 stdout 并换行
;   io_newline()                                输出一个 '\n'
;   io_putchar(rdi=字符)                        输出一个字节
;   io_exit(rdi=退出码)                         退出进程（不返回）
;   io_print_int(rdi=有符号整数)                十进制输出
;   io_print_uint(rdi=无符号整数)               十进制输出
;   io_print_hex(rdi=整数)                      十六进制输出，如 0x2a
;   io_print_bin(rdi=整数)                      二进制输出，如 0b1010
;
; 典型写法：
;       lea rsi, [rel msg]
;       mov rdx, msg_len
;       call io_println
; ===========================================================================

%ifndef IO_INC
%define IO_INC

%include "syscalls.inc"

section .data
; 输出单个字节时用的 1 字节缓冲区。放在 .data 里而不是栈上：
; 让「写入 syscall 的源地址」永远指向静态内存，避免把 rsi 指向
; 正在使用的栈空间（配合 push/pop 时很容易踩坏返回地址）。
io_one_byte: db 0

section .text

; ---------------------------------------------------------------------------
; io_write —— 原样调用 write(2)
; 入参：rdi=fd  rsi=buf  rdx=len   返回：rax=写入字节数（负数表示出错）
; ---------------------------------------------------------------------------
io_write:
    mov rax, SYS_write
    syscall
    ret

; ---------------------------------------------------------------------------
; io_print —— 输出字符串到 stdout（不自动换行）
; 入参：rsi=buf  rdx=len
; ---------------------------------------------------------------------------
io_print:
    mov rax, SYS_write
    mov rdi, STDOUT
    syscall
    ret

; ---------------------------------------------------------------------------
; io_println —— 输出字符串到 stdout 并补一个换行
; 入参：rsi=buf  rdx=len
; ---------------------------------------------------------------------------
io_println:
    push rdx                ; 保存调用者的 rdx（下面要借它当输出长度）
    push rsi
    call io_print

    mov  byte [rel io_one_byte], LF
    lea  rsi, [rel io_one_byte]
    mov  edx, 1
    call io_print

    pop  rsi
    pop  rdx
    ret

; ---------------------------------------------------------------------------
; io_newline —— 只输出一个换行
; ---------------------------------------------------------------------------
io_newline:
    push rdx
    mov  byte [rel io_one_byte], LF
    lea  rsi, [rel io_one_byte]
    mov  edx, 1
    call io_print
    pop  rdx
    ret

; ---------------------------------------------------------------------------
; io_putchar —— 输出单个字节
; 入参：rdi=字符（只用低 8 位）
; ---------------------------------------------------------------------------
io_putchar:
    push rdi
    push rdx
    mov  [rel io_one_byte], dil
    lea  rsi, [rel io_one_byte]
    mov  edx, 1
    call io_print
    pop  rdx
    pop  rdi
    ret

; ---------------------------------------------------------------------------
; io_exit —— 结束进程
; 入参：rdi=退出码（本函数不返回）
; ---------------------------------------------------------------------------
io_exit:
    mov rax, SYS_exit
    syscall
    ud2                     ; 理论上到不了这里；真到了就报非法指令

; ---------------------------------------------------------------------------
; io_print_uint —— 以十进制输出无符号 64 位整数
; 入参：rdi=数值
; 算法：反复除以 10，把余数（即各位数字）逆序压栈，再逐个弹出输出
; ---------------------------------------------------------------------------
io_print_uint:
    push rbx
    push rbp
    push r12
    push r13
    push rdx                ; div 会写 rdx，先把调用者的值存起来
    mov  rax, rdi
    mov  rbx, 10            ; 除数
    xor  rbp, rbp           ; 已压栈的位数

.digits:
    xor  rdx, rdx           ; 除之前必须清零 rdx（被除数的高 64 位）
    div  rbx                ; rax = rax/10, rdx = rax%10
    add  dl, '0'            ; 数字 -> ASCII
    push rdx
    inc  rbp
    test rax, rax
    jnz  .digits            ; 商不为 0 就继续

.print:
    mov  rsi, rsp           ; 栈顶就是当前最高位
    mov  edx, 1             ; 必须写 edx：写 dl 不会清零 rdx 的高 32 位
    call io_print
    add  rsp, 8
    dec  rbp
    jnz  .print

    pop  rdx
    pop  r13
    pop  r12
    pop  rbp
    pop  rbx
    ret

; ---------------------------------------------------------------------------
; io_print_int —— 以十进制输出有符号 64 位整数
; 入参：rdi=数值
; 特殊值：-9223372036854775808（INT64_MIN）也处理正确
; ---------------------------------------------------------------------------
io_print_int:
    push rdi                ; 例程契约：入参寄存器也要恢复
    push rdx
    test rdi, rdi
    js   .negative

    call io_print_uint
    jmp  .done

.negative:
    mov  rax, rdi           ; 先把原值搬到 rax（io_putchar 不会碰 rax 以外的入参）
    push rax
    mov  rdi, '-'
    call io_putchar         ; 打印负号（io_putchar 自己会恢复 rdi，不影响原值）

    pop  rax                ; 取回原值
    neg  rax                ; 取绝对值；INT64_MIN 会绕回自身，输出仍然正确
    mov  rdi, rax
    call io_print_uint

.done:
    pop  rdx
    pop  rdi
    ret

; ---------------------------------------------------------------------------
; io_print_hex —— 以 0x 前缀输出 64 位整数（去掉前导 0）
; 入参：rdi=数值
; 实现思路（比 push/pop 逐位打印更安全）：
;   在栈上开一块 24 字节的缓冲区，从缓冲区末尾往前填字符；
;   填完把整块缓冲区当成一个字符串，用一次 write 输出。
; ---------------------------------------------------------------------------
io_print_hex:
    push rbx
    push rbp
    push r12
    push r13
    push rdx
    sub  rsp, 24                ; 临时缓冲区 [rsp, rsp+24)
    lea  r12, [rsp + 24]        ; r12 指向末尾，写入时先 --r12
    mov  rax, rdi
    mov  rbx, 16

.digits:
    xor  rdx, rdx               ; div 前必须清零 rdx（被除数高 64 位）
    div  rbx                    ; rdx = rax % 16
    cmp  dl, 10
    jb   .num
    add  dl, 'a' - 10 - '0'     ; 让下一行统一加 '0' 后得到 'a'..'f'
.num:
    add  dl, '0'
    dec  r12
    mov  [r12], dl
    test rax, rax
    jnz  .digits

    dec  r12                    ; 补前缀：'x' 在前，'0' 在后
    mov  byte [r12], 'x'
    dec  r12
    mov  byte [r12], '0'

    mov  rsi, r12               ; 缓冲区起点
    lea  rdx, [rsp + 24]        ; 缓冲区终点
    sub  rdx, r12               ; 长度 = 终点 - 起点
    call io_print

    add  rsp, 24
    pop  rdx
    pop  r13
    pop  r12
    pop  rbp
    pop  rbx
    ret

; ---------------------------------------------------------------------------
; io_print_bin —— 以 0b 前缀输出 64 位整数的二进制（去掉前导 0）
; 入参：rdi=数值
; ---------------------------------------------------------------------------
io_print_bin:
    push rbx
    push rbp
    push r12
    push r13
    push rdx
    sub  rsp, 72                ; 2 + 64 位数字 = 66，开 72 字节并保持 8 对齐
    lea  r12, [rsp + 72]
    mov  rax, rdi

.bits:
    mov  rdx, rax
    and  rdx, 1
    add  dl, '0'
    dec  r12
    mov  [r12], dl
    shr  rax, 1
    test rax, rax
    jnz  .bits

    dec  r12
    mov  byte [r12], 'b'
    dec  r12
    mov  byte [r12], '0'

    mov  rsi, r12
    lea  rdx, [rsp + 72]
    sub  rdx, r12
    call io_print

    add  rsp, 72
    pop  rdx
    pop  r13
    pop  r12
    pop  rbp
    pop  rbx
    ret

%endif ; IO_INC

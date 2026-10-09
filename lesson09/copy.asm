; ===========================================================================
; copy.asm —— 第 09 课示例 1：命令行参数的拷贝工具
;
; 编译（在 lesson09 目录下）：
;   make
; 用法：
;   ./copy 源文件 目标文件
; 例子：
;   printf 'hello, file\n' > /tmp/src.txt
;   ./copy /tmp/src.txt /tmp/dst.txt
;   cat /tmp/dst.txt
;
; 用到的系统调用：
;   openat(257) 打开/创建文件
;   read(0)     读数据
;   write(1)    写数据
;   close(3)    关闭文件
;
; 本课最关键的三个新知识：
;   1. 程序启动时栈上是 [rsp]=argc, [rsp+8]=argv[0], [rsp+16]=argv[1]…
;      取参数之前不能先 push 别的东西（否则偏移全乱）；
;   2. 系统调用第 4 个参数是 r10，不是 rcx；
;   3. syscall 的返回值是负数表示出错（-errno），文件描述符也要判负。
;
; 退出码约定（test.sh 靠它判断错误类型）：
;   0 成功 / 1 参数个数不对 / 2 打不开源文件 / 3 读取失败
;   4 写入失败 / 5 关闭失败 / 6 创建不了目标文件
; ===========================================================================

; AT_FDCWD：openat 的 dirfd 参数，意思是「相对当前工作目录」
; （syscalls.inc 里没有这个常量，本节自己定义）
%define AT_FDCWD -100

section .data
    u1      db "用法: ./copy 源文件 目标文件"
    u1_len  equ $ - u1

    e_open_s db "copy: 打不开源文件: "
    e_open_s_len equ $ - e_open_s

    e_open_d db "copy: 创建不了目标文件: "
    e_open_d_len equ $ - e_open_d

    e_read  db "copy: 读取源文件出错"
    e_read_len equ $ - e_read

    e_write db "copy: 写入目标文件出错"
    e_write_len equ $ - e_write

    e_close db "copy: 关闭文件出错"
    e_close_len equ $ - e_close

    msg_ok  db "复制完成，共 "
    msg_ok_len equ $ - msg_ok

    msg_bytes db " 字节"
    msg_bytes_len equ $ - msg_bytes

    msg_to  db "  -> "
    msg_to_len equ $ - msg_to

    buf_size equ 65536          ; 每次读写 64 KiB（是 8 的倍数，保持栈对齐）

section .bss
    buf     resb buf_size       ; 数据缓冲区（.bss 不占可执行文件体积）

section .text
    global _start
default rel                             ; 数据寻址默认 RIP 相对，所有 [标签] 都自动变成 [rel 标签]
bits 64

%include "io.inc"

; ---------------------------------------------------------------------------
; _start —— 入口。第一件事就是把 argc/argv 从栈上取下来
; ---------------------------------------------------------------------------
_start:
    ; ---- 0. 取命令行参数（必须在任何 push 之前做）----------------------
    mov r12, [rsp]              ; r12 = argc
    lea r13, [rsp + 8]          ; r13 = &argv[0]

    ; ---- 1. 检查参数个数：argc >= 3（程序名 + 源 + 目标）----------------
    cmp r12, 3
    jge .args_ok
    lea rsi, [rel u1]
    mov rdx, u1_len
    call io_println
    mov rdi, 1
    call io_exit

.args_ok:
    mov r12, [r13 + 8]          ; r12 = argv[1]（源文件名）
    mov r13, [r13 + 16]         ; r13 = argv[2]（目标文件名）

    ; 把两个路径存进 .bss，后面打印/关闭时还要用
    mov [rel path_src], r12
    mov [rel path_dst], r13

    call copy_file              ; 真正的拷贝逻辑

    ; ---- 2. 打印结果：复制完成，共 N 字节  ->  目标 ---------------------
    mov r12, rax                ; r12 = 字节数（copy_file 的返回值）
    lea rsi, [rel msg_ok]
    mov rdx, msg_ok_len
    call io_print
    mov rdi, r12
    call print_u64
    lea rsi, [rel msg_bytes]
    mov rdx, msg_bytes_len
    call io_print

    lea rsi, [rel msg_to]
    mov rdx, msg_to_len
    call io_print
    mov rsi, [rel path_dst]
    call cstr_len
    mov rdx, rax
    call io_println

    xor rdi, rdi
    call io_exit

; ---------------------------------------------------------------------------
; copy_file —— 把 r12 指向的文件拷贝到 r13 指向的文件
;
;   入参：r12 = 源文件路径，r13 = 目标文件路径（都是 NUL 结尾）
;   返回：rax = 成功时拷贝的字节数；失败时打印信息并直接 exit
;
;   寄存器约定：本函数保存并恢复 rbx/rbp/r12-r15，调用者放心。
;   循环里用的 rcx/r8/r9/r10/r11 都是「调用者保存」寄存器；
;   循环内部不调用任何函数（只有 syscall），所以可以放心占用。
;
;   ⚠ 一个真实的坑：syscall 会破坏 rcx 和 r11（内核用它们存 rip/rflags），
;     所以它们只能「在两次 syscall 之间」用，不能跨 syscall 保存东西。
;     真正要跨 syscall 活得久的值（比如累计字节数），这里放在 r15 里。
; ---------------------------------------------------------------------------
copy_file:
    push rbx                    ; 6 个 push = 48 字节，成对 pop 保持栈平衡
    push rbp
    push r12
    push r13
    push r14
    push r15

    lea r14, [rel buf]          ; r14 = 数据缓冲区地址

    ; ---- 1. openat(AT_FDCWD, 源文件, O_RDONLY) --------------------------
    ; 参数顺序：rdi=dirfd, rsi=path, rdx=flags, r10=mode
    mov rax, SYS_openat
    mov rdi, AT_FDCWD           ; -100：相对当前工作目录
    mov rsi, r12                ; 路径
    mov rdx, O_RDONLY           ; 只读
    xor r10d, r10d              ; mode（没有 O_CREAT 时忽略）
    syscall

    test rax, rax
    jns .src_ok                 ; 非负 = 文件描述符
    ; 出错：打印文件名，然后退出
    lea rsi, [rel e_open_s]
    mov rdx, e_open_s_len
    call io_print
    mov rsi, r12
    call cstr_len
    mov rdx, rax
    call io_println
    mov rdi, 2
    call io_exit

.src_ok:
    mov rbx, rax                ; rbx = 源文件描述符

    ; ---- 2. openat(AT_FDCWD, 目标, O_WRONLY|O_CREAT|O_TRUNC, 0644) ------
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r13
    mov rdx, O_WRONLY | O_CREAT | O_TRUNC
    mov r10, 0o644              ; 权限（最终权限还要看 umask）
    syscall

    test rax, rax
    jns .dst_ok
    lea rsi, [rel e_open_d]
    mov rdx, e_open_d_len
    call io_print
    mov rsi, r13
    call cstr_len
    mov rdx, rax
    call io_println
    mov rdi, 6
    call io_exit

.dst_ok:
    mov rbp, rax                ; rbp = 目标文件描述符
    xor r15, r15                ; r15 = 累计拷贝的字节数

    ; ---- 3. 读-写循环 ---------------------------------------------------
.read_loop:
    ; read(源fd, buf, buf_size)
    mov rax, SYS_read
    mov rdi, rbx                ; 源 fd
    mov rsi, r14                ; 缓冲区
    mov rdx, buf_size
    syscall                     ; ⚠ 这之后 rcx、r11 都不可信了

    test rax, rax
    js .read_err                ; 负数 = 出错
    jz .done                    ; 0 = EOF，收工

    ; rcx = 本轮读到的字节数。它只能活到下一次 syscall 之前，
    ; 而下面这个写循环全是 syscall……所以先把它转存到 r9，
    ; 用 r9（跨 syscall 安全）当「本轮总数」。
    mov r9, rax                 ; r9 = 本轮读到的字节数

    ; ---- 4. 把 r9 个字节全都写出去（处理「短写」）----------------------
    ; 分工如下（这两个都要跨 syscall 保持，所以不能用 rcx/r11）：
    ;   r9  = 本轮总共要写的字节数
    ;   r10 = 本轮已经写出去的字节数
    xor r10, r10
.write_loop:
    mov rax, SYS_write
    mov rdi, rbp                ; 目标 fd
    mov rsi, r14
    add rsi, r10                ; 从还没写完的位置开始
    mov rcx, r9
    sub rcx, r10                ; 还要写多少 = 总数 - 已写
    mov rdx, rcx
    syscall

    test rax, rax
    jle .write_err              ; 负数出错；0 表示写不动了
    add r10, rax                ; 累计本轮已写
    add r15, rax                ; 累计总字节
    cmp r10, r9
    jb .write_loop              ; 短写：继续把剩下的写完
    jmp .read_loop

.done:
    ; ---- 5. 关闭两个文件 ------------------------------------------------
    mov rax, SYS_close
    mov rdi, rbx
    syscall
    test rax, rax
    js .close_err

    mov rax, SYS_close
    mov rdi, rbp
    syscall
    test rax, rax
    js .close_err

    mov rax, r15                ; 返回拷贝的字节数
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

.read_err:
    lea rsi, [rel e_read]
    mov rdx, e_read_len
    call io_println
    mov rdi, 3
    call io_exit

.write_err:
    lea rsi, [rel e_write]
    mov rdx, e_write_len
    call io_println
    mov rdi, 4
    call io_exit

.close_err:
    lea rsi, [rel e_close]
    mov rdx, e_close_len
    call io_println
    mov rdi, 5
    call io_exit

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
; print_u64 —— 把 rdi 里的无符号数按十进制打印出来
; ---------------------------------------------------------------------------
print_u64:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32                 ; 栈上缓冲区（必须在 push 之后再开）

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

section .bss
    path_src resq 1             ; 保存源文件名指针（打印用）
    path_dst resq 1             ; 保存目标文件名指针（打印用）

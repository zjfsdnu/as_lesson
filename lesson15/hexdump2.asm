; ===========================================================================
; hexdump2.asm —— hexdump 增强版：支持命令行参数指定文件名
;
; 纯系统调用风格：入口 _start，用 ld 链接，不依赖 libc。
; 输出格式和 `hexdump -C`（BSD / C 风格）完全一致（第 14 课的 hexdump 相同引擎）。
;
; 用法：
;   ./hexdump2                # 读标准输入
;   ./hexdump2 FILE...        # 依次读这些文件
;   ./hexdump2 - FILE         # "-" 表示标准输入
;   cat a b | ./hexdump2      # 等价于 ./hexdump2 a b（偏移连续）
;
; 与第 14 课 hexdump 相比多出来的东西：
;   1. 从 [rsp] / [rsp+8] 取 argc / argv，用 openat(2) 打开文件
;   2. 多个文件当成一条连续字节流（偏移不重置），最后只打印一行总偏移
;   3. 打开失败往 stderr 报告并继续处理后面的文件，最终退出码为 1
;
; 命令行入口栈布局（内核给的）：
;   [rsp]      = argc
;   [rsp + 8]  = argv[0]（程序名）
;   [rsp + 16] = argv[1]（第一个参数）
;   ...        = NULL 结尾
; 注意：取参数之前不要 push 任何东西，否则 rsp 就指偏了。
; ===========================================================================

default rel

%define AT_FDCWD -100           ; openat(2) 的“相对当前工作目录”特殊值

section .text
%include "io.inc"               ; 一次；提供 io_write / io_exit / 系统调用号常量

section .data
hexdig:     db "0123456789abcdef"
msg_prefix: db "hexdump2: "
msg_prefix_len equ $ - msg_prefix
msg_err:    db ": cannot open", 10
msg_err_len equ $ - msg_err

section .bss
inbuf:  resb 16                 ; 当前行的 16 字节
have:   resq 1                  ; 当前行已有字节数
total:  resq 1                  ; 累计偏移（所有文件连续计数）
err_flag: resq 1                ; 有文件打不开就置 1，作为退出码
line:   resb 128                ; 输出行缓冲（最长 79 字节）

section .text
global _start

; ---------------------------------------------------------------------------
; _start：解析参数 → 逐个文件 dump → 最后补一行总偏移
; ---------------------------------------------------------------------------
_start:
    mov rbx, [rsp]              ; argc（rbx 会被 dump/emit_* 保存）
    lea r12, [rsp + 8]          ; &argv[0]
    mov qword [rel total], 0
    mov qword [rel have], 0     ; 半行缓冲跨文件保留（多文件 = 一条连续字节流）
    mov qword [rel err_flag], 0

    cmp rbx, 2
    jae .files                  ; 至少有一个参数 → 按文件处理

    ; ---- 没有参数：读标准输入 --------------------------------------------
    mov rdi, STDIN
    call dump
    jmp .finish

.files:
    mov r13, 1                  ; 从 argv[1] 开始
.next_arg:
    cmp r13, rbx
    jae .finish
    mov rsi, [r12 + r13*8]      ; argv[i]
    cmp byte [rsi], '-'         ; 参数正好是 "-"？
    jne .open
    cmp byte [rsi + 1], 0
    jne .open
    mov rdi, STDIN
    call dump
    jmp .next_file

.open:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY
    xor r10d, r10d              ; 只有 O_CREAT 才需要 mode
    syscall
    test rax, rax
    js .open_error
    mov r14, rax                ; fd（dump 会保存并恢复 r14）
    mov rdi, r14
    call dump
    mov rax, SYS_close
    mov rdi, r14
    syscall
    jmp .next_file

.open_error:
    mov qword [rel err_flag], 1
    mov rsi, [r12 + r13*8]
    call report_error

.next_file:
    inc r13
    jmp .next_arg

.finish:
    ; ---- 所有输入都读完了：先把没攒满的半个行打出来 -----------------------
    cmp qword [rel have], 0
    je .offset_line
    call emit_line
    mov rax, [rel have]
    add [rel total], rax
    mov qword [rel have], 0
.offset_line:
    cmp qword [rel total], 0
    je .exit
    call emit_offset_line       ; 全部数据读完，补一行总偏移
.exit:
    mov rdi, [rel err_flag]
    call io_exit

; ---------------------------------------------------------------------------
; dump —— 把 fd 的数据接到当前行缓冲后面（多文件 = 连续字节流）
;   入参：rdi = fd      结果：更新 [have]/[total]
;   攒满 16 字节就打一行；这个 fd 读完了就返回，剩下的半行留给下一个文件接着填。
; ---------------------------------------------------------------------------
dump:
    push r14
    mov r14, rdi                ; fd
.fill:
    mov rax, SYS_read
    mov rdi, r14
    lea rsi, [rel inbuf]
    add rsi, [rel have]         ; 接着写（可能是上一个文件剩下的半行）
    mov rdx, 16
    sub rdx, [rel have]         ; 还差多少
    syscall
    test rax, rax
    jle .ret                    ; EOF 或出错：这个 fd 结束
    add [rel have], rax
    cmp qword [rel have], 16
    jb .fill
    call emit_line              ; 攒满一行
    add qword [rel total], 16
    mov qword [rel have], 0
    jmp .fill
.ret:
    pop r14
    ret

; ---------------------------------------------------------------------------
; report_error —— rsi = 文件名；把 "hexdump2: <name>: cannot open" 写到 stderr
; ---------------------------------------------------------------------------
report_error:
    push rbx
    mov rbx, rsi
    lea rsi, [rel msg_prefix]
    mov rdx, msg_prefix_len
    mov rdi, STDERR
    call io_write
    mov rdi, rbx
    call str_len                ; argv 里的字符串只保证以 NUL 结尾，长度要自己数
    mov rdx, rax
    mov rsi, rbx
    mov rdi, STDERR
    call io_write
    lea rsi, [rel msg_err]
    mov rdx, msg_err_len
    mov rdi, STDERR
    call io_write
    pop rbx
    ret

; ---------------------------------------------------------------------------
; str_len —— rdi = 字符串 → rax = 长度（不含结尾的 0）
; ---------------------------------------------------------------------------
str_len:
    xor eax, eax
.loop:
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; ---------------------------------------------------------------------------
; emit_line —— 用 [have]/[total]/inbuf 生成并输出一行
;   布局：偏移(8) 2 空格 十六进制区(49) 空格 '|' ASCII '|' '\n'
; ---------------------------------------------------------------------------
emit_line:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea r14, [rel hexdig]
    lea r15, [rel line]
    lea rbx, [rel inbuf]
    mov r13, [rel have]

    ; ---- 1) 8 位十六进制偏移 ---------------------------------------------
    mov ecx, 28
.off:
    mov rdx, [rel total]
    shr rdx, cl                 ; cl = 移位量
    and edx, 0x0f
    mov al, [r14 + rdx]
    mov [r15], al
    inc r15
    sub ecx, 4
    jns .off

    mov byte [r15], ' '
    mov byte [r15 + 1], ' '
    add r15, 2

    ; ---- 2) 16 个字节的十六进制，不足补空格 ------------------------------
    xor r12d, r12d
.bytes:
    cmp r12, r13
    jae .pad
    movzx eax, byte [rbx + r12]
    mov edx, eax
    shr edx, 4
    mov dl, [r14 + rdx]
    mov [r15], dl
    inc r15
    mov edx, eax
    and edx, 0x0f
    mov dl, [r14 + rdx]
    mov [r15], dl
    inc r15
    mov byte [r15], ' '
    inc r15
    jmp .after_byte
.pad:
    mov byte [r15], ' '
    mov byte [r15 + 1], ' '
    mov byte [r15 + 2], ' '
    add r15, 3
.after_byte:
    cmp r12, 7
    jne .next_byte
    mov byte [r15], ' '         ; 分栏：第 8 个字节后多一个空格
    inc r15
.next_byte:
    inc r12
    cmp r12, 16
    jb .bytes

    ; ---- 3) ASCII 视图 ----------------------------------------------------
    mov byte [r15], ' '
    inc r15
    mov byte [r15], '|'
    inc r15
    xor r12d, r12d
.ascii:
    cmp r12, r13
    jae .ascii_done
    movzx eax, byte [rbx + r12]
    cmp al, 0x20
    jb .dot
    cmp al, 0x7e
    ja .dot
    mov [r15], al
    jmp .ascii_next
.dot:
    mov byte [r15], '.'
.ascii_next:
    inc r15
    inc r12
    jmp .ascii
.ascii_done:
    mov byte [r15], '|'
    inc r15
    mov byte [r15], LF
    inc r15

    ; ---- 4) 一次 write 输出整行 ------------------------------------------
    lea rsi, [rel line]
    mov rdx, r15
    sub rdx, rsi
    mov rdi, STDOUT
    call io_write

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; emit_offset_line —— 打印 “总偏移” 行
; ---------------------------------------------------------------------------
emit_offset_line:
    push rbx
    push r14
    lea r14, [rel hexdig]
    lea rbx, [rel line]
    mov ecx, 28
.off:
    mov rdx, [rel total]
    shr rdx, cl
    and edx, 0x0f
    mov al, [r14 + rdx]
    mov [rbx], al
    inc rbx
    sub ecx, 4
    jns .off
    mov byte [rbx], LF
    inc rbx

    lea rsi, [rel line]
    mov rdx, rbx
    sub rdx, rsi
    mov rdi, STDOUT
    call io_write

    pop r14
    pop rbx
    ret

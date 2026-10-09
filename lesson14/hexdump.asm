; ===========================================================================
; hexdump.asm —— 模仿 `hexdump -C`（BSD / C 风格）把标准输入打印成十六进制
;
; 纯系统调用风格：入口 _start，用 ld 链接，不依赖 libc，也不用 printf。
; 输入输出用 ../include/io.inc 里的 io_write / io_exit。
;
; 输出格式（和 Linux 的 hexdump -C 一模一样）：
;   00000000  68 65 6c 6c 6f 0a                                 |hello.|
;   00000006
; 每行固定 16 字节，分两栏各 8 字节（中间多一个空格），
; 右边是 ASCII 视图：0x20~0x7e 原样显示，其它（含 0x80 以上）显示成 '.'
; 数据读完后还会单独打印一行“总偏移”。
; 输入为空（例如 make run 时的 /dev/null）时不输出任何东西，正常退出。
;
; 运行：
;   ./hexdump < 文件
;   printf 'hello\n' | ./hexdump
; ===========================================================================

default rel

section .text
%include "io.inc"               ; 只 include 一次

section .data
hexdig: db "0123456789abcdef"   ; 十六进制字符表：下标 0~15 → '0'~'f'

section .bss
inbuf:  resb 16                 ; 当前这一行的 16 字节数据
have:   resq 1                  ; 当前这一行实际读到了几个字节
total:  resq 1                  ; 已经处理过的总字节数（= 下一行的偏移）
line:   resb 128                ; 输出行缓冲区（最长 79 字节，留足余量）

section .text
global _start

; ---------------------------------------------------------------------------
; _start：主循环 —— 每次攒够 16 字节（或遇到 EOF）就交给 emit_line 打一行
; ---------------------------------------------------------------------------
_start:
    mov qword [rel total], 0

.next_line:
    mov qword [rel have], 0

    ; ---- 把这一行的数据读满（read 可能短读，所以要循环凑）----------------
.fill:
    mov rax, SYS_read
    xor edi, edi                ; fd = 0（标准输入）
    lea rsi, [rel inbuf]
    add rsi, [rel have]         ; 接着上次的位置写
    mov rdx, 16
    sub rdx, [rel have]         ; 还差几个字节
    syscall
    test rax, rax
    jle .filled                 ; 0 = EOF，负数 = 出错，都按结束处理
    add [rel have], rax
    cmp qword [rel have], 16
    jb .fill                    ; 没满 16 字节就继续读

.filled:
    cmp qword [rel have], 0
    je .finish                  ; 一个字节都没读到 → 输入结束
    call emit_line
    mov rax, [rel have]
    add [rel total], rax        ; 偏移前进
    cmp qword [rel have], 16
    jb .finish                  ; 这一行不满 16 字节说明已经读到文件末尾
    jmp .next_line

.finish:
    cmp qword [rel total], 0
    je .exit                    ; 输入为空：什么都不打印
    call emit_offset_line       ; 最后补一行“总偏移”，和 hexdump -C 一致
.exit:
    xor edi, edi
    call io_exit

; ---------------------------------------------------------------------------
; emit_line —— 用 [have]/[total]/inbuf 生成一行 hexdump -C 格式并写出
;   行布局（共 79 字节）：
;     偏移(8) 空格空格 十六进制区(8*3 + 1 + 8*3 = 49) 空格 '|' ASCII(≤16) '|' '\n'
; ---------------------------------------------------------------------------
emit_line:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea r14, [rel hexdig]       ; 字符表
    lea r15, [rel line]         ; 输出游标
    lea rbx, [rel inbuf]        ; 数据源
    mov r13, [rel have]         ; 本行有效字节数（后面循环用，省得反复读内存）

    ; ---- 1) 8 位十六进制偏移 ---------------------------------------------
    mov ecx, 28                 ; 从第 28 位（最高半字节）开始，每次右移 4 位
.off:
    mov rdx, [rel total]
    shr rdx, cl                 ; cl = 本次的移位量
    and edx, 0x0f
    mov al, [r14 + rdx]
    mov [r15], al
    inc r15
    sub ecx, 4
    jns .off                    ; 28,24,...,0 共 8 位

    mov byte [r15], ' '
    mov byte [r15 + 1], ' '
    add r15, 2

    ; ---- 2) 16 个字节的十六进制（不足的补空格）---------------------------
    xor r12d, r12d
.bytes:
    cmp r12, r13
    jae .pad
    movzx eax, byte [rbx + r12]
    mov edx, eax
    shr edx, 4                  ; 高半字节
    mov dl, [r14 + rdx]
    mov [r15], dl
    inc r15
    mov edx, eax
    and edx, 0x0f               ; 低半字节
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
    mov byte [r15], ' '         ; 第 8 个字节后额外空一格（hexdump -C 的分栏）
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
    cmp al, 0x20                ; 小于空格 → '.'
    jb .dot
    cmp al, 0x7e                ; 大于 '~'（含 0x7f~0xff）→ '.'
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
    sub rdx, rsi                ; 长度 = 游标 - 行首
    mov rdi, STDOUT
    call io_write

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; emit_offset_line —— 打印最后一行“总偏移”（8 位十六进制 + 换行）
; ---------------------------------------------------------------------------
emit_offset_line:
    push rbx
    push r12
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
    pop r12
    pop rbx
    ret

; ===========================================================================
; wordcount.asm —— 统计文件的行数 / 单词数 / 字节数（像个小型 wc）
;
; 纯系统调用风格：入口 _start，用 ld 链接，不依赖 libc。
; 输入输出只用 ../include/io.inc 里的 io_write / io_exit 和裸系统调用。
;
; 用法：
;   ./wordcount FILE...      # 一个或多个文件，多于一个时最后打印 total 行
;   ./wordcount              # 没有参数就读标准输入（不打文件名）
;   ./wordcount - FILE       # "-" 表示标准输入
;
; 输出格式与 GNU coreutils 的 `wc -l -w -c` 一致：
;   * 三列依次是 行数、单词数、字节数，用单个空格分隔
;   * 所有数字共用同一个宽度（右对齐）：普通文件按总字节数的位数算；
;     只要输入里有“非普通文件”（管道、/dev/null、"−"），最小列宽就是 7
;     —— 这是 wc 的怪癖，我们用 fstat(2) 判断文件类型，行为完全对齐
;   * 数字后面再空一格接文件名；读标准输入时没有文件名
;   * 只有一个输入时不打印 total 行
; 例：
;   $ printf 'hello world\nfoo bar baz\n' > t1.txt
;   $ ./wordcount t1.txt
;   2 5 24 t1.txt
;   $ ./wordcount t1.txt t2.txt
;      2    5   24 t1.txt
;      1    1    4 t2.txt
;      3    6   28 total
;
; 单词的定义和 wc 一样：一段连续的“非空白字符”（空白 = 空格 \t \n \v \f \r）。
; 关键点是“是否正在单词里”这个状态要跨 read 边界保留：buffer 正好断在单词中间时
; 不能把它算成两个词（下面用 r15 保存这个状态）。
; ===========================================================================

default rel

%define AT_FDCWD -100
%define MAXF     64             ; 最多同时统计 64 个文件
%define BUFSZ    65536          ; 每次读 64 KiB

section .text
%include "io.inc"               ; 一次；提供 io_write / io_exit / 常量

section .data
total_label:  db "total", 0
msg_prefix:   db "wordcount: "
msg_prefix_len equ $ - msg_prefix
msg_err:      db ": cannot open", 10
msg_err_len   equ $ - msg_err
msg_many:     db "wordcount: too many files (max 64)", 10
msg_many_len  equ $ - msg_many

section .bss
buf:        resb BUFSZ          ; 读取缓冲区
lines_arr:  resq MAXF           ; 每个文件的行数
words_arr:  resq MAXF           ; 每个文件的单词数
bytes_arr:  resq MAXF           ; 每个文件的字节数
names_arr:  resq MAXF           ; 每个文件的名字指针（0 = 标准输入，不打名字）
nfiles:     resq 1
width:      resq 1              ; 数字列宽（和 GNU wc 一样动态计算）
tlines:     resq 1
twords:     resq 1
tbytes:     resq 1
statbuf:    resb 144            ; fstat(2) 的 struct stat
nonreg:     resq 1              ; 有非普通文件输入就置 1（列宽最小 7）
cur_lines:  resq 1              ; 当前文件的统计结果
cur_words:  resq 1
cur_bytes:  resq 1
err_flag:   resq 1
linebuf:    resb 512            ; 输出行缓冲

section .text
global _start

; ---------------------------------------------------------------------------
; _start
; ---------------------------------------------------------------------------
_start:
    mov rbx, [rsp]              ; argc
    lea r12, [rsp + 8]          ; &argv[0]
    mov qword [rel nfiles], 0
    mov qword [rel err_flag], 0
    mov qword [rel nonreg], 0

    cmp rbx, 2
    jae .file_args

    ; ---- 没有参数：读标准输入 --------------------------------------------
    mov rdi, STDIN
    call count_fd
    xor r15d, r15d              ; 名字 = 0（表示不打印文件名）
    call store_result
    jmp .print_all

.file_args:
    mov r13, 1                  ; argv 下标
.next_arg:
    cmp r13, rbx
    jae .print_all
    cmp qword [rel nfiles], MAXF
    jb .arg_ok
    lea rsi, [rel msg_many]     ; 文件太多：报错并停止解析
    mov rdx, msg_many_len
    mov rdi, STDERR
    call io_write
    mov qword [rel err_flag], 1
    jmp .print_all

.arg_ok:
    mov rsi, [r12 + r13*8]      ; argv[i]
    cmp byte [rsi], '-'         ; "-" → 标准输入
    jne .open
    cmp byte [rsi + 1], 0
    jne .open
    mov rdi, STDIN
    call count_fd
    mov r15, [r12 + r13*8]      ; 名字就显示 "-"
    call store_result
    jmp .next_file

.open:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY
    xor r10d, r10d              ; mode：O_RDONLY 用不到
    syscall
    test rax, rax
    js .open_error
    mov r14, rax                ; fd
    mov rdi, r14
    call count_fd
    mov rax, SYS_close
    mov rdi, r14
    syscall
    mov r15, [r12 + r13*8]      ; 记住文件名
    call store_result
    jmp .next_file

.open_error:
    mov qword [rel err_flag], 1
    mov rsi, [r12 + r13*8]
    call report_error

.next_file:
    inc r13
    jmp .next_arg

; ---------------------------------------------------------------------------
; .print_all：先算总和与列宽，再逐行打印（和 GNU wc 一样的两步走）
; ---------------------------------------------------------------------------
.print_all:
    mov qword [rel tlines], 0
    mov qword [rel twords], 0
    mov qword [rel tbytes], 0
    xor ecx, ecx
.tot_loop:
    cmp rcx, [rel nfiles]
    jae .width_calc
    lea rax, [rel lines_arr]
    mov rdx, [rax + rcx*8]
    add [rel tlines], rdx
    lea rax, [rel words_arr]
    mov rdx, [rax + rcx*8]
    add [rel twords], rdx
    lea rax, [rel bytes_arr]
    mov rdx, [rax + rcx*8]
    add [rel tbytes], rdx
    inc rcx
    jmp .tot_loop

.width_calc:
    mov qword [rel width], 1
    xor r12d, r12d              ; 这里起 r12（原 argv）不再需要
.wloop:
    cmp r12, [rel nfiles]
    jae .w_totals
    lea rax, [rel lines_arr]
    mov rdi, [rax + r12*8]
    call num_width
    call widen
    lea rax, [rel words_arr]
    mov rdi, [rax + r12*8]
    call num_width
    call widen
    lea rax, [rel bytes_arr]
    mov rdi, [rax + r12*8]
    call num_width
    call widen
    inc r12
    jmp .wloop
.w_totals:
    mov rdi, [rel tlines]
    call num_width
    call widen
    mov rdi, [rel twords]
    call num_width
    call widen
    mov rdi, [rel tbytes]
    call num_width
    call widen
    ; ---- GNU wc 的怪癖：有非普通文件输入时列宽至少 7 ----------------------
    cmp qword [rel nonreg], 0
    je .print_lines
    cmp qword [rel width], 7
    jae .print_lines
    mov qword [rel width], 7

.print_lines:
    xor ebx, ebx                ; 下标（print_line 会保存/恢复 rbx）
.ploop:
    cmp rbx, [rel nfiles]
    jae .print_total
    lea rax, [rel lines_arr]
    mov r12, [rax + rbx*8]
    lea rax, [rel words_arr]
    mov r13, [rax + rbx*8]
    lea rax, [rel bytes_arr]
    mov r14, [rax + rbx*8]
    lea rax, [rel names_arr]
    mov r15, [rax + rbx*8]
    call print_line
    inc rbx
    jmp .ploop

.print_total:
    cmp qword [rel nfiles], 1
    jbe .exit                   ; 只有 0/1 个输入：没有 total 行
    mov r12, [rel tlines]
    mov r13, [rel twords]
    mov r14, [rel tbytes]
    lea r15, [rel total_label]
    call print_line

.exit:
    mov rdi, [rel err_flag]
    call io_exit

; ---------------------------------------------------------------------------
; count_fd —— 统计一个文件描述符
;   入参：rdi = fd
;   结果：[cur_lines] / [cur_words] / [cur_bytes]
; ---------------------------------------------------------------------------
count_fd:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; fd
    mov qword [rel cur_lines], 0
    mov qword [rel cur_words], 0
    mov qword [rel cur_bytes], 0
    xor r15d, r15d              ; 0 = 当前不在单词里（跨 read 保留）

    ; ---- 用 fstat(2) 看是不是普通文件（决定列宽是否要用最小 7）-----------
    mov rax, SYS_fstat
    mov rdi, r12
    lea rsi, [rel statbuf]
    syscall
    test rax, rax
    js .stat_done               ; 失败就当成普通文件，不设标记
    mov eax, dword [rel statbuf + 24]   ; st_mode 在 struct stat 的偏移 24
    and eax, 0xF000             ; 取文件类型位
    cmp eax, 0x8000             ; S_IFREG = 普通文件
    je .stat_done
    mov qword [rel nonreg], 1
.stat_done:

.read:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [rel buf]
    mov rdx, BUFSZ
    syscall
    test rax, rax
    jle .done                   ; 0 = EOF；负数 = 读错误，都结束
    add [rel cur_bytes], rax
    lea rbx, [rel buf]
    mov r13, rax                ; 本次读到的字节数
    xor r14d, r14d              ; 缓冲区下标
.scan:
    movzx eax, byte [rbx + r14]
    cmp al, LF
    jne .not_newline
    inc qword [rel cur_lines]
.not_newline:
    ; ---- 是不是空白字符？------------------------------------------------
    cmp al, SPACE
    je .is_space
    cmp al, TAB
    je .is_space
    cmp al, LF
    je .is_space
    cmp al, 0x0b                ; \v
    je .is_space
    cmp al, 0x0c                ; \f
    je .is_space
    cmp al, 0x0d                ; \r
    je .is_space
    ; ---- 非空白：如果刚才不在单词里，就是一个新单词的开头 ----------------
    test r15, r15
    jnz .next
    inc qword [rel cur_words]
    mov r15d, 1
    jmp .next
.is_space:
    xor r15d, r15d
.next:
    inc r14
    cmp r14, r13
    jb .scan
    jmp .read
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; store_result —— 把 cur_* 和 r15（文件名指针）追加到数组，nfiles++
; ---------------------------------------------------------------------------
store_result:
    mov rcx, [rel nfiles]
    lea rax, [rel lines_arr]
    mov rdx, [rel cur_lines]
    mov [rax + rcx*8], rdx
    lea rax, [rel words_arr]
    mov rdx, [rel cur_words]
    mov [rax + rcx*8], rdx
    lea rax, [rel bytes_arr]
    mov rdx, [rel cur_bytes]
    mov [rax + rcx*8], rdx
    lea rax, [rel names_arr]
    mov [rax + rcx*8], r15
    inc qword [rel nfiles]
    ret

; ---------------------------------------------------------------------------
; num_width —— rdi = 非负整数 → rax = 十进制位数（至少 1）
; ---------------------------------------------------------------------------
num_width:
    push rbx
    mov rax, rdi
    mov rbx, 10
    mov ecx, 1
.loop:
    cmp rax, rbx
    jb .done
    xor edx, edx
    div rbx                     ; rax /= 10
    inc ecx
    jmp .loop
.done:
    mov eax, ecx
    pop rbx
    ret

; ---------------------------------------------------------------------------
; widen —— rax = 候选宽度；比 [width] 大就更新 [width]
; ---------------------------------------------------------------------------
widen:
    cmp rax, [rel width]
    jbe .done
    mov [rel width], rax
.done:
    ret

; ---------------------------------------------------------------------------
; append_num —— 把 rdi（数值）按 rsi（列宽）右对齐追加到 [rbx]，rbx 前进
; ---------------------------------------------------------------------------
append_num:
    sub rsp, 32
    lea r8, [rsp + 32]          ; 缓冲区末尾（数字从后往前填）
    mov r9, r8
    mov rax, rdi
    mov r10, 10
.digits:
    xor edx, edx
    div r10                     ; rax /= 10，rdx = 余数
    add dl, '0'
    dec r9
    mov [r9], dl
    test rax, rax
    jnz .digits
    ; 位数 = r8 - r9；需要补的空格 = 宽度 - 位数
    mov rcx, r8
    sub rcx, r9
    mov rax, rsi
    sub rax, rcx
    jle .copy
.pad:
    mov byte [rbx], ' '
    inc rbx
    dec rax
    jnz .pad
.copy:
    mov rcx, r8
    sub rcx, r9
.copy_loop:
    mov dl, [r9]
    mov [rbx], dl
    inc r9
    inc rbx
    dec rcx
    jnz .copy_loop
    add rsp, 32
    ret

; ---------------------------------------------------------------------------
; print_line —— 打印一行：行数 / 单词数 / 字节数 / 文件名
;   入参：r12=行数 r13=单词数 r14=字节数 r15=文件名指针（0 = 不打印）
; ---------------------------------------------------------------------------
print_line:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea rbx, [rel linebuf]
    mov rdi, r12
    mov rsi, [rel width]
    call append_num
    mov byte [rbx], ' '
    inc rbx
    mov rdi, r13
    mov rsi, [rel width]
    call append_num
    mov byte [rbx], ' '
    inc rbx
    mov rdi, r14
    mov rsi, [rel width]
    call append_num
    test r15, r15
    jz .no_name
    mov byte [rbx], ' '
    inc rbx
.name_loop:
    mov al, [r15]
    test al, al
    jz .no_name
    mov [rbx], al
    inc rbx
    inc r15
    jmp .name_loop
.no_name:
    mov byte [rbx], LF
    inc rbx
    lea rsi, [rel linebuf]
    mov rdx, rbx
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
; report_error —— rsi = 文件名；stderr 输出 "wordcount: <name>: cannot open"
; ---------------------------------------------------------------------------
report_error:
    push rbx
    mov rbx, rsi
    lea rsi, [rel msg_prefix]
    mov rdx, msg_prefix_len
    mov rdi, STDERR
    call io_write
    mov rdi, rbx
    call str_len
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
; str_len —— rdi = 字符串 → rax = 长度
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

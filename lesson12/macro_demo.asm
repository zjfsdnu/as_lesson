; ===========================================================================
; 第 12 课示例 1：macro_demo.asm
;   NASM 预处理：%define、%macro/%endmacro、带参数的宏、%rep、%ifdef/%if
;
; ★ 入口说明：本文件是**纯系统调用程序**（文件名没有 lc_ 前缀）：
;   入口是 _start，用 nasm + ld 链接，输出走 ../include/io.inc。
;
; 编译运行：
;   nasm -f elf64 -g -F dwarf -I ../include -o macro_demo.o macro_demo.asm
;   ld -o macro_demo macro_demo.o
;   ./macro_demo
;
; 本课最重要的一个概念：
;   所有 % 开头的东西（%define/%macro/%rep/%if/%include/%assign…）都在
;   **汇编期**由 NASM 的预处理器处理，它们自己不生成任何机器码。
;   生成机器码的是预处理完之后剩下的那些指令。
;   所以：
;       %rep 3        不是循环，是「把这段源码抄 3 遍」；
;       %ifdef DEBUG  不是运行时判断，是「条件不满足就根本不汇编这段」。
; ===========================================================================

default rel                             ; 数据寻址默认 RIP 相对，所有 [标签] 都自动变成 [rel 标签]
bits 64

%include "syscalls.inc"                 ; 提供 SYS_write / STDOUT / SYS_exit
%include "io.inc"                       ; 提供 io_print / io_print_uint / io_newline / io_exit
                                        ; （io.inc 里已经 %include 了 syscalls.inc，重复 include 无害）

; ---------------------------------------------------------------------------
; 一、%define：定义「单行宏」，也就是汇编期的文本替换
;     它没有类型、不占存储空间，展开发生在源码文本层面。
; ---------------------------------------------------------------------------
%define VERSION_MAJOR   12
%define VERSION_MINOR   0
%define VERSION_STR     "12.0"
%define BUF_SIZE        64              ; 试试改成 8 或 128，看输出怎么变
%define NEWLINE         10

%define DEBUG                           ; 保留这行 -> 走 Debug 分支
                                        ; 注释掉它   -> 那段代码根本不出现在可执行文件里

; 一个小检查：条件不满足时直接让汇编失败，比运行时出错更省事
%if BUF_SIZE < 8
    %error "BUF_SIZE 至少要 8 个字节"
%endif

; ---------------------------------------------------------------------------
; 二、%macro/%endmacro：带参数的宏
;     宏体里用 %1、%2… 引用参数，%0 是参数个数。
;     %1 是纯文本替换：
;       * 想当字符串用（塞进 db "..."）   -> 用 %defstr 再引用
;       * 想当数字算                        -> 用 %assign / %if 里直接写
;     宏没有 call 开销（因为压根没有 call），代价是每展开一次就复制一份代码。
; ---------------------------------------------------------------------------

; ---- 写文件描述符 %1，缓冲区 %2，长度 %3 ----
; Linux 64 位：系统调用号在 rax，参数依次 rdi/rsi/rdx/r10/r8/r9
%macro SYS_WRITE3 3
    mov  rax, SYS_write
    mov  rdi, %1
    mov  rsi, %2
    mov  rdx, %3
    syscall                             ; syscall 会破坏 rcx 和 r11
%endmacro

; ---- 往 stdout 写一段字符串并换行 ----
; %1 是 "带引号的字符串字面量"。
; 标签用 %% 前缀（%%name）：每次宏展开都会生成唯一的名字，不会重复定义。
; 注意：这里不能用 %$name —— %$ 属于「宏上下文（%push 建立的 context）」机制，
; 没有 %push 直接用会报 `%$tag': context stack is empty，所以教学示例用 %% 更合适。
%macro PRINT_LINE 1
    jmp  short %%past                   ; 先跳过内嵌的数据，别让 CPU 执行到它
%%tag:  db %1
%%len_tag equ $ - %%tag
%%nl_tag: db NEWLINE
%%past:
    mov  rax, SYS_write
    mov  rdi, STDOUT
    lea  rsi, [rel %%tag]
    mov  rdx, %%len_tag
    syscall
    mov  rax, SYS_write
    mov  rdi, STDOUT
    lea  rsi, [rel %%nl_tag]
    mov  rdx, 1
    syscall
%endmacro

; ---- 用 %strlen 在汇编期拿到字符串长度 ----
; 注意：不要写成 %defstr %%s %1 —— 参数里只要出现非 ASCII 字符（中文），
; NASM 在 %defstr 里会把多字节当成字符常量处理而报
; "character constant too long"；直接对带引号的参数用 %strlen 就没这个问题。
%macro SHOW_STR_INFO 1
    %strlen %%n %1                      ; 汇编期算出「字符串的字节数」
    jmp  short %%body                   ; ⚠ 必须先跳过下面的字符串数据
%%s: db %1                              ; 数据就摆在代码段里，不跳过会被当指令执行
%%body:
    mov  rax, SYS_write
    mov  rdi, STDOUT
    lea  rsi, [rel %%s]
    mov  rdx, %%n
    syscall
%endmacro

; ---------------------------------------------------------------------------
; 三、%rep：把一段源码重复抄 N 遍（N 是汇编期常量或表达式）
;     这里用它生成一条 60 个 '-' 的分隔线：db 60 个重复字节
; ---------------------------------------------------------------------------
%macro SEP 0
    mov  rax, SYS_write
    mov  rdi, STDOUT
    lea  rsi, [rel %%line]
    mov  rdx, 61
    syscall
    jmp  short %%after
%%line: db "------------------------------------------------------------", NEWLINE
%%after:
%endmacro

section .data
    m_title     db "=== NASM 宏 / 条件汇编演示 ===", 10
    m_title_len equ $ - m_title
    m_l1a       db "本文件由第 "
    m_l1a_len   equ $ - m_l1a
    m_l1b       db " 课的宏生成", 10
    m_l1b_len   equ $ - m_l1b
    m_ver       db VERSION_STR, 10     ; VERSION_STR 是宏，这里直接展开成 "12.0"
    m_ver_len   equ $ - m_ver

    m_sec1      db "--- 1. %define：汇编期常量，不占空间 ---", 10
    m_sec1_len  equ $ - m_sec1
    m_sec2      db "--- 2. %macro：带参数的宏 ---", 10
    m_sec2_len  equ $ - m_sec2
    m_sec3      db "--- 3. %rep：源码重复 ---", 10
    m_sec3_len  equ $ - m_sec3
    m_sec4      db "--- 4. %ifdef / %if / %ifidn：条件汇编 ---", 10
    m_sec4_len  equ $ - m_sec4
    m_sec5      db "--- 5. 宏叠宏：PRINT_NUM 只是把参数转发给一个例程 ---", 10
    m_sec5_len  equ $ - m_sec5

    m_dbg_on    db "[DEBUG] DEBUG 已定义，这段代码真的被汇编进来了", 10
    m_dbg_on_len equ $ - m_dbg_on
    m_dbg_off   db "[DEBUG] 没有定义 DEBUG，这段不会出现在可执行文件里", 10
    m_dbg_off_len equ $ - m_dbg_off
    m_small     db "BUF_SIZE < 32：走小缓冲分支", 10
    m_small_len equ $ - m_small
    m_big       db "BUF_SIZE >= 32：走大缓冲分支", 10
    m_big_len   equ $ - m_big
    m_eq        db '%ifidn 判断 VERSION_STR 与 "12.0" 文本相同', 10
    m_eq_len    equ $ - m_eq
    m_neq       db '%ifidn 判断 VERSION_STR 与 "12.0" 文本不同', 10
    m_neq_len   equ $ - m_neq
    m_num       db "PRINT_NUM 输出："
    m_num_len   equ $ - m_num
    m_end       db "宏演示结束", 10
    m_end_len   equ $ - m_end

section .bss
    buf     resb BUF_SIZE               ; BUF_SIZE 是 %define 出来的，可以直接算大小
    num_buf resb 24
    one_byte resb 1                     ; 输出单个换行用的 1 字节缓冲区

section .text
    global _start

; ---------------------------------------------------------------------------
; 这些是普通例程（不是宏），用来演示「宏可以把参数转发给例程」
; io.inc 里的例程签名：io_print(rsi=buf, rdx=len)、io_print_uint(rdi=n)
; ---------------------------------------------------------------------------
%macro PRINT 2                          ; %1 = 缓冲区/标签，%2 = 长度
    lea  rsi, [rel %1]
    mov  rdx, %2
    call io_print
%endmacro

%macro PRINT_NUM 1                      ; %1 = 数字（也可以是 VERSION_MAJOR 这种宏）
    mov  rdi, %1
    call io_print_uint
    call io_newline
%endmacro

_start:
    PRINT m_title, m_title_len

    ; 「本文件由第 12 课的宏生成」—— 12 就是 VERSION_MAJOR 展开的结果
    PRINT m_l1a, m_l1a_len
    mov  rdi, VERSION_MAJOR
    call io_print_uint
    PRINT m_l1b, m_l1b_len

    ; ======================= 1. %define =============================
    PRINT m_sec1, m_sec1_len
    PRINT m_ver, m_ver_len              ; 版本号 "12.0" 由 %define 拼出来

    ; ======================= 2. %macro ==============================
    PRINT m_sec2, m_sec2_len

    ; SYS_WRITE3 的三个参数：fd、缓冲区、长度
    SYS_WRITE3 STDOUT, m_l1a, m_l1a_len

    ; PRINT_LINE：字符串直接内嵌在代码段里，宏里的 jmp 跳过了它
    PRINT_LINE "PRINT_LINE 宏：字符串内嵌在代码段，靠 jmp 跳过"
    PRINT_LINE "换个参数就换一段文本，标签由 %% 保证唯一"

    ; SHOW_STR_INFO 用 %defstr/%strlen 在汇编期拿到长度
    SHOW_STR_INFO "SHOW_STR_INFO：长度是汇编期用 %strlen 算出来的"
    mov  rax, SYS_write
    mov  rdi, STDOUT
    mov  byte [rel one_byte], NEWLINE   ; 用 .bss 里的静态缓冲区，不要把 rsi 指向栈顶
    lea  rsi, [rel one_byte]
    mov  rdx, 1
    syscall

    ; ======================= 3. %rep ================================
    PRINT m_sec3, m_sec3_len

    %rep 3                              ; 这三行在汇编期就变成了 3 份 SEP
        SEP
    %endrep

    ; ======================= 4. 条件汇编 ============================
    PRINT m_sec4, m_sec4_len

%ifdef DEBUG
    PRINT m_dbg_on, m_dbg_on_len
%else
    PRINT m_dbg_off, m_dbg_off_len
%endif

%if BUF_SIZE < 32
    PRINT m_small, m_small_len
%else
    PRINT m_big, m_big_len
%endif

; %ifidn 比较的是「文本」而不是「数值」：
; 这里判断 VERSION_STR（展开成 "12.0"）和字面量 "12.0" 是否完全一样。
; 想忽略大小写就用 %ifidni。注意千万别拿没定义过的宏去比较 ——
; 那会直接报 "symbol not defined"。
%ifidn VERSION_STR, "12.0"
    PRINT m_eq, m_eq_len
%else
    PRINT m_neq, m_neq_len
%endif

    ; ======================= 5. 宏叠宏 ==============================
    PRINT m_sec5, m_sec5_len
    PRINT m_num, m_num_len
    PRINT_NUM 123456                    ; 宏里 call 例程；换成 VERSION_MAJOR 也行
    mov  rdi, VERSION_MAJOR
    call io_print_uint
    call io_newline

    PRINT m_end, m_end_len

    mov  rdi, 0
    call io_exit

; ===========================================================================
; debug_target.asm —— 第 14 课的“调试靶子”：一个平均值计算程序
;
; 纯系统调用风格：文件名不以 lc_ 开头、入口 _start、用 ld 直接链接（不链 libc）。
; 输入输出用 ../include/io.inc 里的小工具（io_print / io_print_int / io_newline）。
;
; ★ 默认构建（不加 -DBUGGY_VERSION）是「已经修好」的版本，能正常跑完：
;     make && ./debug_target
;
; ★ 故意写错的版本用条件汇编包着，需要用 -DBUGGY_VERSION 显式打开：
;     nasm -f elf64 -g -F dwarf -DBUGGY_VERSION -I ../include -o debug_target.o debug_target.asm
;     ld -o debug_target_buggy debug_target.o
;     ./debug_target_buggy
;   错版本不会崩溃、也不会死循环，但会打印出明显不对的 count/sum/avg，
;   README 里用 gdb + objdump 一步步演示怎么定位这两个 bug。
;
; 两个 bug（都在下面用 BUG 1 / BUG 2 标出）：
;   BUG 1  循环条件用 jbe（<=）而不是 jb（<）→ 多循环一次，读了数组后面一个元素
;   BUG 2  累加器用 32 位 eax、读内存也只读 dword → 高位丢掉（本例正好丢成 0）
; ===========================================================================

default rel

section .text
%include "io.inc"               ; 只能 include 一次；它自己会打开 section .text

section .data
COUNT   equ 8                   ; 数组元素个数

; 8 个元素，每个 0x20000000 = 536870912：
;   正确的 64 位和 = 8 * 0x20000000 = 0x100000000 = 4294967296
;   用 32 位累加就会截断成 0
arr:
    dq 0x20000000, 0x20000000, 0x20000000, 0x20000000
    dq 0x20000000, 0x20000000, 0x20000000, 0x20000000

; 紧跟在数组后面的一块数据（哨兵）。它在 .data 里，所以就算被越界读也不会段错误，
; 但会让结果对不上 —— 这正是我们希望 gdb 暴露出来的现象。
sentinel:
    dq 0x40000000

msg_count:  db "count = "
msg_count_len equ $ - msg_count
msg_sum:    db "sum   = "
msg_sum_len equ $ - msg_sum
msg_avg:    db "avg   = "
msg_avg_len equ $ - msg_avg

section .text
global _start

_start:
    lea rbx, [rel arr]          ; rbx = 数组基址（rbx 是被调用者保存，跨 io_* 调用安全）

%ifdef BUGGY_VERSION
    ; ------------------------- 有 bug 的版本 -----------------------------
    xor eax, eax                ; BUG 2：累加器只用 32 位
    xor ecx, ecx
.sum_loop:
    add eax, dword [rbx + rcx*8]    ; BUG 2：只读低 4 字节，高 4 字节丢掉
    inc rcx
    cmp rcx, COUNT
    jbe .sum_loop               ; BUG 1：应该是 jb（rcx < COUNT）
%else
    ; ------------------------- 正确版本 -----------------------------------
    xor rax, rax                ; 64 位累加器
    xor ecx, ecx
.sum_loop:
    add rax, [rbx + rcx*8]      ; 一次读满 8 字节
    inc rcx
    cmp rcx, COUNT
    jb .sum_loop                ; rcx < COUNT 才继续 → 正好 8 次
%endif

    mov r13, rcx                ; 循环次数 = 元素个数（正确 8，错误 9）
    mov r12, rax                ; 求和结果

    ; ---- 打印 count --------------------------------------------------------
    lea rsi, [rel msg_count]
    mov rdx, msg_count_len
    call io_print
    mov rdi, r13
    call io_print_int
    call io_newline

    ; ---- 打印 sum ----------------------------------------------------------
    lea rsi, [rel msg_sum]
    mov rdx, msg_sum_len
    call io_print
    mov rdi, r12
    call io_print_int
    call io_newline

    ; ---- avg = sum / count -------------------------------------------------
    mov rax, r12
    xor rdx, rdx                ; div 之前必须清零 rdx（被除数的高 64 位）
    div r13                     ; rax = 商
    mov r14, rax

    lea rsi, [rel msg_avg]
    mov rdx, msg_avg_len
    call io_print
    mov rdi, r14
    call io_print_int
    call io_newline

    xor edi, edi
    call io_exit                ; 结束进程（纯 syscall 程序不能 ret 到不存在的调用者）

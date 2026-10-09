; ===========================================================================
; regs.asm —— 第 02 课：通用寄存器的宽度（64/32/16/8 位别名）
;
; 这个程序演示三件事：
;   1. rax / eax / ax / al / ah 指的是同一个物理寄存器，只是"窗口"大小不同
;   2. 写 32 位（eax）会自动把高 32 位清零；写 16/8 位（ax/al/ah）不会
;   3. movzx（零扩展）与 movsx（符号扩展）的区别
;
; 构建/运行：
;   make && ./regs
; ===========================================================================

default rel

section .data
    banner      db  "=== 第 02 课：寄存器宽度演示 ===", 10
    banner_len  equ $ - banner

    s1      db  "1) mov rax, 0x1122334455667788          -> rax = "
    s1_len  equ $ - s1
    s2      db  "2) 再 mov ax, 0xaabb（只动低 16 位）    -> rax = "
    s2_len  equ $ - s2
    s3      db  "3) 重来再 mov al, 0xcc（只动低 8 位）   -> rax = "
    s3_len  equ $ - s3
    s4      db  "4) 重来 mov eax, 0xdeadbeef（清高 32）  -> rax = "
    s4_len  equ $ - s4
    s5      db  "5) 接上一步 mov ah, 0x77（第 2 字节）   -> rax = "
    s5_len  equ $ - s5
    s6a     db  "6) rax = -1，当有符号数看               -> "
    s6a_len equ $ - s6a
    s6b     db  "   rax = -1，当无符号数看               -> "
    s6b_len equ $ - s6b
    s7a     db  "7) mov al,0xFF 后 movzx rax,al          -> "
    s7a_len equ $ - s7a
    s7b     db  "   mov al,0xFF 后 movsx rax,al          -> "
    s7b_len equ $ - s7b

section .text
    global _start
    %include "io.inc"

_start:
    ; ---------------- 标题 ----------------
    lea     rsi, [rel banner]
    mov     rdx, banner_len
    call    io_print

    ; ---------------- 1. 64 位写入 ----------------
    lea     rsi, [rel s1]
    mov     rdx, s1_len
    call    io_print                    ; 先输出说明文字
    mov     rax, 0x1122334455667788      ; 64 位立即数（NASM 会用 movabs 编码）
    mov     rdi, rax                    ; io_print_hex 的参数在 rdi
    call    io_print_hex                ; 0x1122334455667788
    call    io_newline

    ; ---------------- 2. 只写低 16 位 ----------------
    lea     rsi, [rel s2]
    mov     rdx, s2_len
    call    io_print

    mov     rax, 0x1122334455667788      ; 先恢复初值
    mov     ax, 0xaabb                  ; 只改最低 16 位，高 48 位不动
    mov     rdi, rax
    call    io_print_hex                ; 0x112233445566aabb
    call    io_newline

    ; ---------------- 3. 只写低 8 位 ----------------
    lea     rsi, [rel s3]
    mov     rdx, s3_len
    call    io_print

    mov     rax, 0x1122334455667788
    mov     al, 0xcc                    ; 只改最低 8 位
    mov     rdi, rax
    call    io_print_hex                ; 0x11223344556677cc
    call    io_newline

    ; ---------------- 4. 写 32 位会清零高 32 位 ----------------
    lea     rsi, [rel s4]
    mov     rdx, s4_len
    call    io_print

    mov     rax, 0x1122334455667788
    mov     eax, 0xdeadbeef             ; 写 eax ⇒ rax 的高 32 位自动变成 0
    mov     rdi, rax
    call    io_print_hex                ; 0xdeadbeef
    call    io_newline

    ; ---------------- 5. ah 是第 2 个字节 ----------------
    lea     rsi, [rel s5]
    mov     rdx, s5_len
    call    io_print

    mov     rax, 0x1122334455667788
    mov     eax, 0xdeadbeef
    mov     ah, 0x77                    ; ah = rax 的 bit8..bit15
    mov     rdi, rax
    call    io_print_hex                ; 0xdead77ef
    call    io_newline

    ; ---------------- 6. 同一个位模式，两种解释 ----------------
    lea     rsi, [rel s6a]
    mov     rdx, s6a_len
    call    io_print

    mov     rax, -1                     ; 64 个二进制 1
    mov     rdi, rax
    call    io_print_int                ; 有符号解释：-1
    call    io_newline

    lea     rsi, [rel s6b]
    mov     rdx, s6b_len
    call    io_print

    mov     rax, -1
    mov     rdi, rax
    call    io_print_uint               ; 无符号解释：18446744073709551615
    call    io_newline

    ; ---------------- 7. movzx 与 movsx ----------------
    lea     rsi, [rel s7a]
    mov     rdx, s7a_len
    call    io_print

    mov     rax, 0x1122334455667788
    mov     al, 0xFF                    ; al = 0xFF，rax 其余位还是原来那堆
    movzx   rax, al                     ; 零扩展：高 56 位全部清零
    mov     rdi, rax
    call    io_print_int                ; 255
    call    io_newline

    lea     rsi, [rel s7b]
    mov     rdx, s7b_len
    call    io_print

    mov     rax, 0x1122334455667788
    mov     al, 0xFF
    movsx   rax, al                     ; 符号扩展：0xFF 当成 -1
    mov     rdi, rax
    call    io_print_int                ; -1
    call    io_newline

    ; ---------------- 结束 ----------------
    xor     edi, edi                    ; 退出码 0
    call    io_exit                     ; io_exit 不会返回

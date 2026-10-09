; ===========================================================================
; mem.asm —— 第 02 课：程序里的三种数据位置
;
;   1) .data  已初始化数据：有初值，初值会写进可执行文件
;   2) .bss   未初始化数据：可执行文件里只记"要多少字节"，加载时被清零
;   3) 栈     运行期的临时空间：sub rsp, N 开出来，add rsp, N 还回去
;
; 构建/运行：
;   make && ./mem
; ===========================================================================

default rel

; ---------------------------------------------------------------------------
; 已初始化数据段
; ---------------------------------------------------------------------------
section .data
    banner      db  "=== 第 02 课：三种数据位置 .data / .bss / 栈 ===", 10
    banner_len  equ $ - banner

    d_val       dq  0x1122334455667788      ; 8 字节，有初值
    d_msg       db  "d_msg：我在 .data，初值已经写进可执行文件", 10
    d_msg_len   equ $ - d_msg

    t1      db  "[.data] d_val 的初值               = "
    t1_len  equ $ - t1
    t2      db  "[.data] d_msg 的内容               : "
    t2_len  equ $ - t2
    t3      db  "[.bss ] b_num 没赋过值，读出来是   = "
    t3_len  equ $ - t3
    t4      db  "[.bss ] 往 b_num 写 0x2a 再读      = "
    t4_len  equ $ - t4
    t5      db  "[.bss ] b_buf[0] 当数字看          = "
    t5_len  equ $ - t5
    t6      db  "[.bss ] b_buf 当字符串看           = "
    t6_len  equ $ - t6
    t7      db  "[栈   ] sub rsp,16 之后 [rsp]      = "
    t7_len  equ $ - t7
    t8      db  "[栈   ] 同一块空间的 [rsp+8]       = "
    t8_len  equ $ - t8
    t9      db  "[栈   ] add rsp,16 后 (备份rsp-rsp)= "
    t9_len  equ $ - t9
    t9_tail db  "   ← 0 表示栈指针已经复原"
    t9_tail_len equ $ - t9_tail

    ta      db  "[地址 ] d_val(.data) = "
    ta_len  equ $ - ta
    tb      db  "   b_num(.bss) = "
    tb_len  equ $ - tb
    tc      db  "   rsp(栈顶) = "
    tc_len  equ $ - tc
    tnote   db  "（地址每次运行都可能不同，这是正常的）", 10
    tnote_len equ $ - tnote

; ---------------------------------------------------------------------------
; 未初始化数据段：只声明"要多少字节"，不占可执行文件的体积
; ---------------------------------------------------------------------------
section .bss
    b_num   resq 1                  ; 8 字节（1 个 qword）
    b_buf   resb 8                  ; 8 字节

section .text
    global _start
    %include "io.inc"

_start:
    lea     rsi, [rel banner]
    mov     rdx, banner_len
    call    io_print

    ; ======================= .data =======================
    lea     rsi, [rel t1]
    mov     rdx, t1_len
    call    io_print
    mov     rdi, [rel d_val]            ; 从 .data 里读 8 字节
    call    io_print_hex
    call    io_newline

    lea     rsi, [rel t2]
    mov     rdx, t2_len
    call    io_print
    lea     rsi, [rel d_msg]
    mov     rdx, d_msg_len
    call    io_print                    ; d_msg 自带换行，不用再补

    ; ======================= .bss ========================
    lea     rsi, [rel t3]
    mov     rdx, t3_len
    call    io_print
    mov     rdi, [rel b_num]            ; 从来没写过，读出来一定是 0
    call    io_print_hex
    call    io_newline

    mov     qword [rel b_num], 0x2a     ; 往 .bss 里写 8 字节
    lea     rsi, [rel t4]
    mov     rdx, t4_len
    call    io_print
    mov     rdi, [rel b_num]
    call    io_print_hex
    call    io_newline

    mov     byte [rel b_buf], 0x41      ; 'A'
    mov     byte [rel b_buf + 1], 0x42  ; 'B'
    mov     byte [rel b_buf + 2], 0     ; 字符串结尾的 0

    lea     rsi, [rel t5]
    mov     rdx, t5_len
    call    io_print
    movzx   rdi, byte [rel b_buf]       ; 只读 1 个字节
    call    io_print_hex                ; 0x41
    call    io_newline

    lea     rsi, [rel t6]
    mov     rdx, t6_len
    call    io_print
    lea     rsi, [rel b_buf]
    mov     edx, 2                      ; 只打印 "AB" 这 2 个字节
    call    io_print
    call    io_newline

    ; ======================= 栈 ==========================
    mov     r12, rsp                    ; 备份 rsp（r12 不会被 io.inc 破坏）
    sub     rsp, 16                     ; 在栈上开 16 字节的临时空间

    mov     qword [rsp], 0x1111         ; 第 1 个 8 字节槽
    mov     qword [rsp + 8], 0x2222     ; 第 2 个 8 字节槽

    lea     rsi, [rel t7]
    mov     rdx, t7_len
    call    io_print
    mov     rdi, [rsp]                  ; 从栈上读回来
    call    io_print_hex                ; 0x1111
    call    io_newline

    lea     rsi, [rel t8]
    mov     rdx, t8_len
    call    io_print
    mov     rdi, [rsp + 8]              ; 也读回来
    call    io_print_hex                ; 0x2222
    call    io_newline

    add     rsp, 16                     ; 把栈还回去（sub/add 必须成对）

    lea     rsi, [rel t9]
    mov     rdx, t9_len
    call    io_print
    mov     rax, r12                    ; 备份的 rsp
    sub     rax, rsp                    ; 减去当前 rsp
    mov     rdi, rax
    call    io_print_hex                ; 差是 0x0 就说明复原了
    lea     rsi, [rel t9_tail]
    mov     rdx, t9_tail_len
    call    io_print
    call    io_newline

    ; ======================= 地址对比 ====================
    lea     rsi, [rel ta]
    mov     rdx, ta_len
    call    io_print
    lea     rdi, [rel d_val]            ; .data 里 d_val 的地址
    call    io_print_hex

    lea     rsi, [rel tb]
    mov     rdx, tb_len
    call    io_print
    lea     rdi, [rel b_num]            ; .bss 里 b_num 的地址
    call    io_print_hex

    lea     rsi, [rel tc]
    mov     rdx, tc_len
    call    io_print
    mov     rdi, rsp                    ; 当前栈顶
    call    io_print_hex
    call    io_newline

    lea     rsi, [rel tnote]
    mov     rdx, tnote_len
    call    io_print

    xor     edi, edi
    call    io_exit

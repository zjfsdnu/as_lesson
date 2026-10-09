; ===========================================================================
; data.asm —— 第 03 课：数据定义 db / dw / dd / dq / equ / times
;
;   db = Define Byte      （1 字节）
;   dw = Define Word      （2 字节，注意 x86 里 "word" 是 2 字节不是 4 字节）
;   dd = Define Doubleword（4 字节）
;   dq = Define Quadword  （8 字节）
;   equ  = 汇编期常量，不占内存
;   times = 把同一份数据重复 N 次
;
; 构建/运行：
;   make && ./data
; ===========================================================================

default rel

section .data
    banner      db  "=== 第 03 课：数据定义 db/dw/dd/dq/equ/times ===", 10
    banner_len  equ $ - banner

    ; ---- db：一个字节一个字节地摆 ----
    b1      db  0x41, 0x42, 'C', 10     ; 'A' 'B' 'C' 换行（0x41 == 65 == 'A'）
    b1_len  equ $ - b1                  ; = 4（含那个换行）

    ; ---- dw：2 字节 ----
    w1      dw  0x1234

    ; ---- dd：4 字节 ----
    d1      dd  0x89abcdef

    ; ---- dq：8 字节 ----
    q1      dq  0x1122334455667788
q1_end:                                 ; 紧跟在 q1 后面，用来算大小
    Q1_LEN  equ q1_end - q1             ; = 8

    ; ---- 字符串 + 结尾 0，长度用 equ 算出来 ----
    str1        db  "abc", 0
    str1_len    equ $ - str1 - 1        ; = 3（不减 1 会把结尾的 0 也算进去）

    ; ---- times：重复 ----
    stars   times 8 db 0x2a             ; 8 个 '*'（0x2a == 42 == '*'）
    pair    times 3 db "ab"             ; "ab" 重复 3 次 = "ababab"（6 字节）

    ; ---- 下面都是输出用的小标签 ----
    t_db    db  "[db   ] b1 的 4 个字节原样输出   : "
    t_db_len equ $ - t_db
    t_db0   db  "[db   ] b1[0] 当数字看           = "
    t_db0_len equ $ - t_db0
    t_dw    db  "[dw   ] w1（2 字节）             = "
    t_dw_len equ $ - t_dw
    t_dd    db  "[dd   ] d1（4 字节，mov edi 读） = "
    t_dd_len equ $ - t_dd
    t_dd2   db  "[dd   ] d1 当有符号 32 位看      = "
    t_dd2_len equ $ - t_dd2
    t_dq    db  "[dq   ] q1（8 字节）             = "
    t_dq_len equ $ - t_dq
    t_equ   db  "[equ  ] Q1_LEN = q1_end - q1     = "
    t_equ_len equ $ - t_equ
    t_str   db  "[str  ] str1 的内容              = "
    t_str_len equ $ - t_str
    t_str2  db  "  长度 = "
    t_str2_len equ $ - t_str2
    t_tm1   db  "[times] stars = 8 个 0x2a        = "
    t_tm1_len equ $ - t_tm1
    t_tm2   db  '[times] pair   = 3 组 "ab"       = '  ; NASM 没有 "" 转义，改用单引号
    t_tm2_len equ $ - t_tm2

section .text
    global _start
    %include "io.inc"

_start:
    lea     rsi, [rel banner]
    mov     rdx, banner_len
    call    io_print

    ; ---------------- db：原样输出 4 个字节 ----------------
    lea     rsi, [rel t_db]
    mov     rdx, t_db_len
    call    io_print
    lea     rsi, [rel b1]
    mov     rdx, b1_len
    call    io_print                    ; 输出 "ABC" 加上 b1 里自带的换行

    ; db 的字节也能当数字用
    lea     rsi, [rel t_db0]
    mov     rdx, t_db0_len
    call    io_print
    movzx   rdi, byte [rel b1]          ; 只取 1 个字节，零扩展成 64 位
    call    io_print_int                ; 65
    call    io_newline

    ; ---------------- dw ----------------
    lea     rsi, [rel t_dw]
    mov     rdx, t_dw_len
    call    io_print
    movzx   rdi, word [rel w1]          ; 取 2 个字节
    call    io_print_hex                ; 0x1234
    call    io_newline

    ; ---------------- dd ----------------
    lea     rsi, [rel t_dd]
    mov     rdx, t_dd_len
    call    io_print
    mov     edi, [rel d1]               ; 读 4 字节到 edi，高 32 位自动补 0
    call    io_print_hex                ; 0x89abcdef
    call    io_newline

    ; 同样 4 字节，按"有符号"扩展到 64 位就是另一个数
    lea     rsi, [rel t_dd2]
    mov     rdx, t_dd2_len
    call    io_print
    movsxd  rdi, dword [rel d1]         ; 符号扩展
    call    io_print_int                ; -1985229329
    call    io_newline

    ; ---------------- dq ----------------
    lea     rsi, [rel t_dq]
    mov     rdx, t_dq_len
    call    io_print
    mov     rdi, [rel q1]               ; 读 8 字节
    call    io_print_hex                ; 0x1122334455667788
    call    io_newline

    ; ---------------- equ：汇编期常量，不占内存 ----------------
    lea     rsi, [rel t_equ]
    mov     rdx, t_equ_len
    call    io_print
    mov     rdi, Q1_LEN                 ; 汇编时就被替换成 8
    call    io_print_int                ; 8
    call    io_newline

    ; ---------------- 字符串与它的长度 ----------------
    lea     rsi, [rel t_str]
    mov     rdx, t_str_len
    call    io_print
    lea     rsi, [rel str1]
    mov     rdx, str1_len
    call    io_print                    ; abc
    lea     rsi, [rel t_str2]
    mov     rdx, t_str2_len
    call    io_print
    mov     rdi, str1_len
    call    io_print_int                ; 3
    call    io_newline

    ; ---------------- times ----------------
    lea     rsi, [rel t_tm1]
    mov     rdx, t_tm1_len
    call    io_print
    lea     rsi, [rel stars]
    mov     edx, 8
    call    io_print                    ; ********
    call    io_newline

    lea     rsi, [rel t_tm2]
    mov     rdx, t_tm2_len
    call    io_print
    lea     rsi, [rel pair]
    mov     edx, 6
    call    io_print                    ; ababab
    call    io_newline

    xor     edi, edi
    call    io_exit

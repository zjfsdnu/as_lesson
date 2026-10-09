; ===========================================================================
; 第 11 课示例 2：simd_strlen.asm
;   用 pcmpeqb + pmovmskb + bsf 一次查 16 个字节找字符串结尾，
;   和「逐字节比较」的做法对比。
;
; ★ 入口说明：本文件是**纯系统调用程序**，不是 libc 程序。
;   * 入口是 _start（不是 main），文件名也没有 lc_ 前缀 —— 这正是项目约定：
;     文件名不以 lc_ 开头的示例用 nasm + ld 链接，入口必须是 _start。
;   * 输出用 ../include/io.inc 里的 io_print / io_println / io_print_uint，
;     完全不碰 libc（没有 crt1.o 做初始化时直接 call printf 会崩）。
;   * 第 11 课的两个示例故意一个用 libc（lc_simd_intro.asm，入口 main）、
;     一个用纯系统调用（本文件，入口 _start），正好复习第 1 课讲的
;     「两种风格绝不能混」。
;
; 编译运行：
;   nasm -f elf64 -g -F dwarf -I ../include -o simd_strlen.o simd_strlen.asm
;   ld -o simd_strlen simd_strlen.o
;   ./simd_strlen
;
; 用到的指令（全部 SSE2）：
;   pxor      xmm, xmm          把 xmm 清零
;   movdqu    xmm, [mem]        一次读 16 字节
;   movdqa    xmm, [mem]        一次读 16 字节（要求地址 16 字节对齐）
;   pcmpeqb   xmm, xmm          16 个字节逐字节比较，相等则那个字节变 0xFF
;   pmovmskb  r32, xmm          把 16 个字节的最高位收成一个 16 位掩码
;   bsf       r32, r32          找最低位的 1 在哪一位（bit scan forward）
;     掩码的第 i 位 = 1 表示第 i 个字节是 '\0'，bsf 一下就得到它的下标
; ===========================================================================

default rel                             ; 数据寻址默认 RIP 相对
bits 64

%include "io.inc"                       ; ⚠ 一个程序里只能 %include 一次

section .data
    s1      db "Hello, SIMD!", 0
    s2      db "x", 0
    s3      db "SIMD 让 16 个字节一次比完", 0
    s4      db "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", 0

    m_head  db "=== strlen: 逐字节 vs SIMD ==="
    m_head_len equ $ - m_head
    m_cmp   db "  两种实现结果一致: "
    m_cmp_len equ $ - m_cmp
    m_yes   db "是", 10
    m_yes_len equ $ - m_yes
    m_no    db "否（有 bug！）", 10
    m_no_len equ $ - m_no
    m_s     db "  串: ["
    m_s_len equ $ - m_s
    m_e     db "]", 10
    m_e_len equ $ - m_e
    m_l1    db "  逐字节比较 strlen: "
    m_l1_len equ $ - m_l1
    m_l2    db "        SIMD strlen: "
    m_l2_len equ $ - m_l2

section .text
    global _start

; ===========================================================================
; strlen_byte —— 教科书式逐字节实现
; 入参：rdi = 字符串首地址
; 返回：rax = 长度（不含结尾的 '\0'）
; 特点：每读 1 个字节判断一次，长度为 N 就要循环 N 次。
; ===========================================================================
strlen_byte:
    xor  rax, rax                       ; rax = 已经数过的字节数
.loop:
    cmp  byte [rdi + rax], 0            ; 当前字节是 '\0' 吗？
    je   .done
    inc  rax
    jmp  .loop
.done:
    ret

; ===========================================================================
; strlen_simd —— 一次处理 16 字节
; 入参：rdi = 字符串首地址
; 返回：rax = 长度
;
; 主循环：把字符串按「相对 rdi 的偏移」切成 16 字节块。
;   每块先用 movdqu 读进来，pcmpeqb 和全 0 比较（相等的字节变 0xFF），
;   再用 pmovmskb 把 16 个字节的最高位收成 16 位掩码：
;       bit i = 1  表示第 i 个字节是 '\0'
;   掩码为 0 说明这 16 字节里没有 '\0'，偏移加 16 继续。
;   掩码不为 0，bsf 找出最低的那个 1，长度 = 偏移 + 位号。
;
; 收尾：如果这个 16 字节块会越过字符串末尾（连带 '\0' 一起读会跨页），
;   就退回到「16 字节对齐块」的安全做法：
;     1. 把 rdi 向下对齐到 16 字节边界，整块用 movdqa 读 16 字节；
;        这样读的地址永远在字符串所在的那一页里，不会踩到未映射页。
;     2. 但块里可能包含字符串起点之前的字节，它们也可能碰巧是 0，
;        会给掩码贡献一些「假」的 1。把它们清掉：
;        对于对齐块内的下标 p，它对应的绝对偏移是 base+p；
;        只有 base+p ≥ rdi 才是字符串自己的字节。
;        用 1<<p 生成每一位，并从低位往高位累加，就能把
;        「绝对偏移 < rdi」的位全部去掉，只保留 ≥ rdi 的位。
;     3. bsf 找最低的 1，长度 = 对齐起点 + p - rdi。
; ===========================================================================
strlen_simd:
    pxor xmm0, xmm0                     ; xmm0 = 全 0
    xor  r10, r10                       ; r10 = 相对 rdi 的偏移
    mov  r11, rdi
    and  r11, -4096                     ; r11 = 起点所在页的首地址
    add  r11, 4096                      ; r11 = 下一页的首地址（本页的上界）

.chunk:
    ; 安全检查：这个 16 字节块会不会跨过页尾？
    ; 会跨页就退回 .tail —— 否则 movdqu 可能读到下一页，触发段错误。
    lea  rax, [rdi + r10 + 15]          ; 本块最后一个字节的地址
    cmp  rax, r11
    jae  .tail                          ; 已经到下一页了，别读
    movdqu xmm1, [rdi + r10]
    pcmpeqb xmm1, xmm0
    pmovmskb ecx, xmm1
    test ecx, ecx
    jnz  .found
    add  r10, 16
    jmp  .chunk

.found:
    bsf  ecx, ecx
    lea  rax, [r10 + rcx]               ; 长度 = 块偏移 + 位号
    ret

.tail:
    ; 把 rdi 向下对齐到 16 字节边界，整块用 movdqa 读 —— 地址永远在
    ; 字符串起点所在的页里（起点本身一定合法），不会踩到未映射页。
    mov  r9, rdi
    and  r9, -16                        ; r9 = 对齐后的地址
    movdqa xmm1, [r9]
    pcmpeqb xmm1, xmm0
    pmovmskb ecx, xmm1                  ; 对齐块里所有 '\0' 的位置

    ; 对齐块里可能包含字符串起点之前的字节，它们也可能为 0，
    ; 会给掩码贡献「假」的 1。把绝对位置 < rdi 的那些位清掉：
    ; 第 p 位对应的绝对位置是 r9 + p，要求 r9 + p ≥ rdi。
    mov  r10, rdi
    sub  r10, r9                        ; r10 = rdi 在块内的下标（0..15）
    mov  eax, 1                         ; eax = 1<<p
    xor  r8d, r8d                       ; r8 = 允许保留的位
    xor  edx, edx                       ; edx = p
.keep:
    cmp  rdx, r10
    jae  .kept
    or   r8d, eax                       ; p < 起点下标：这个位置的对齐字节是
    add  eax, eax                       ; 「假」的，不能算进掩码
    inc  rdx
    jmp  .keep
.kept:
    test r10, r10
    jz   .have_mask                     ; 起点本来就 16 字节对齐：块内没有假位
    and  ecx, r8d                       ; 否则去掉绝对位置 < rdi 的假位
.have_mask:
    test ecx, ecx                       ; 字符串的 '\0' 一定在这块里，理论上不会为 0
    jz   .zero
    bsf  ecx, ecx
    lea  rax, [r9 + rcx]
    sub  rax, rdi                       ; 长度 = 绝对位置 - 起点
    ret
.zero:
    xor  eax, eax
    ret

; ===========================================================================
; print_one —— 打印一个字符串，再用两种实现各算一次长度并比较
; 入参：rdi = 字符串
; 说明：io_* 例程只破坏 rax/rcx/r11，其余寄存器调用前后不变（见 io.inc 头注释），
;       所以这里可以用 r14/r15 保存中间结果，不必反复压栈。
; ===========================================================================
print_one:
    mov  r14, rdi                       ; r14 = 字符串首地址

    ; ---- 第 1 行：串: [xxxxx] ----
    lea  rsi, [rel m_s]
    mov  rdx, m_s_len
    call io_print
    mov  rdi, r14
    call strlen_byte
    mov  r15, rax                       ; r15 = 逐字节算出的长度（后面比较用）
    mov  rsi, r14
    mov  rdx, r15
    call io_print
    lea  rsi, [rel m_e]
    mov  rdx, m_e_len
    call io_print

    ; ---- 第 2 行：逐字节比较 strlen: n ----
    lea  rsi, [rel m_l1]
    mov  rdx, m_l1_len
    call io_print
    mov  rdi, r15
    call io_print_uint
    call io_newline

    ; ---- 第 3 行：SIMD strlen: n ----
    lea  rsi, [rel m_l2]
    mov  rdx, m_l2_len
    call io_print
    mov  rdi, r14
    call strlen_simd
    mov  r12, rax                       ; r12 = SIMD 算出的长度
    mov  rdi, rax
    call io_print_uint
    call io_newline

    ; ---- 比较两者是否一致 ----
    lea  rsi, [rel m_cmp]
    mov  rdx, m_cmp_len
    call io_print
    cmp  r12, r15
    jne  .mismatch
    lea  rsi, [rel m_yes]
    mov  rdx, m_yes_len
    call io_print
    ret
.mismatch:
    lea  rsi, [rel m_no]
    mov  rdx, m_no_len
    call io_print
    ret

_start:
    lea  rsi, [rel m_head]
    mov  rdx, m_head_len
    call io_println
    call io_newline

    lea  rdi, [rel s1]
    call print_one
    call io_newline

    lea  rdi, [rel s2]
    call print_one
    call io_newline

    lea  rdi, [rel s3]
    call print_one
    call io_newline

    lea  rdi, [rel s4]
    call print_one

    mov  rdi, 0
    call io_exit

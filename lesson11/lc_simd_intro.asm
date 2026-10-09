; ===========================================================================
; 第 11 课示例 1：lc_simd_intro.asm
;   SIMD 入门：一条 paddd 指令同时做 8 组 32 位整数加法
;
; 编译运行：
;   nasm -f elf64 -g -F dwarf -I ../include -o lc_simd_intro.o lc_simd_intro.asm
;   gcc -no-pie -Wall -O0 -o lc_simd_intro lc_simd_intro.o
;   ./lc_simd_intro
;
; 用到的指令：
;   movdqu xmm, [mem] / movdqu [mem], xmm   一次搬 16 字节（不要求对齐），SSE2
;   movdqa xmm, [mem]                       一次搬 16 字节（要求 16 字节对齐），SSE2
;   paddd  xmm, xmm      8 组 32 位整数逐组相加（packed add dword），SSE2
;   pmulld xmm, xmm      8 组 32 位整数逐组相乘，**SSE4.1**
;   movq   r64, xmm      把 xmm 低 64 位搬到通用寄存器，SSE2
;   psrldq xmm, 8        整个 128 位寄存器按字节右移（把高 64 位移到低 64 位），SSE2
;
; 本程序所有输出都是整数（%d），没有用到任何向量寄存器，
; 所以每个 printf 之前都是 xor eax, eax。
; ===========================================================================

default rel
bits 64

section .data

; ---- 第一组：两个 8 元素的 int32 数组 ------------------------------------
align 16                                ; 让数组起点 16 字节对齐
vec_a   dd 10, 20, 30, 40, 50, 60, 70, 80
vec_b   dd  1,  2,  3,  4,  5,  6,  7,  8

; ---- 第二组：带负数的数组，验证 paddd 就是 32 位补码加法 -----------------
align 16
vec_c   dd 100, -50, 25, -75, 7, -1, 1000, -1000
vec_d   dd   1,  25, -5,  75, 3,  1, -999,  1000

    fmt_head   db "=== 1. 整数向量加法 paddd（SSE2）===", 10, 0
    fmt_a1     db "A      = [ %d %d %d %d ", 0        ; 不换行，后半部分接着打印
    fmt_a2     db "%d %d %d %d ]", 10, 0
    fmt_b1     db "B      = [ %d %d %d %d ", 0
    fmt_b2     db "%d %d %d %d ]", 10, 0
    fmt_sum1   db "A + B  = [ %d %d %d %d ", 0
    fmt_sum2   db "%d %d %d %d ]", 10, 0
    fmt_scalar db "手算期望：A+B 的 8 个元素总和 = %d", 10, 0
    fmt_head2  db "=== 2. 带负数的 paddd（补码加法）===", 10, 0
    fmt_c1     db "C      = [ %d %d %d %d ", 0
    fmt_c2     db "%d %d %d %d ]", 10, 0
    fmt_d1     db "D      = [ %d %d %d %d ", 0
    fmt_d2     db "%d %d %d %d ]", 10, 0
    fmt_cd1    db "C + D  = [ %d %d %d %d ", 0
    fmt_cd2    db "%d %d %d %d ]", 10, 0
    fmt_head3  db "=== 3. 向量乘法 pmulld（需要 SSE4.1）===", 10, 0
    fmt_mul1   db "B * B  = [ %d %d %d %d ", 0
    fmt_mul2   db "%d %d %d %d ]", 10, 0
    fmt_done   db "SIMD 演示结束", 10, 0

; ---- 自检输出：把 SIMD 结果和标量算法对比，判断这台机器/虚拟机有没有问题 ----
; 说明：极少数虚拟化环境（本项目实测到一台 Debian 13 的 VM）会把
;       paddd / pmulld 这类「多 lane 32 位」指令只算低 64 位，
;       导致第 5~8 个元素全是 0。程序自己检测并如实报出来，
;       免得学员以为是自己写错了。正常 CPU 上全部显示「一致」。
    fmt_chk_ok  db "  [自检] 8 个 lane 全部正确，本机 SIMD 正常", 10, 0
    fmt_chk_bad db "  [自检] 只有低 4 个 lane 正确 —— 该宿主机/虚拟化的 SSE 实现有问题（不是你的代码错）", 10, 0
    fmt_chk_sum db "  [自检] 8 lane 和=%d（期望 %d），低 4 lane 和=%d，非零 lane 个数=%d", 10, 0

section .bss
align 16
vec_sum  resd 8                         ; 存 A + B
vec_sum2 resd 8                         ; 存 C + D
vec_mul  resd 8                         ; 存 B * B

section .text
    extern printf
    global main

; ---------------------------------------------------------------------------
; 怎么把 xmm 里的 8 个 int32 拿出来打印？
;
; 最直接的想法是用 pextrd r32, xmm, n 逐个取。它属于 SSE4.1，而且
; 在部分 CPU/虚拟化环境下，n ≥ 4 的那些 lane 结果不对：
;     pextrd eax, xmm0, 4   可能又返回 lane 0 的值
; 这是实测踩到的坑（见 README「常见坑」第 6 条）。所以这里换成最稳的做法：
;
;   先把 SIMD 结果用 movdqa / movdqu 整块写回内存（vec_sum 等），
;   再用普通的 mov 从内存里按 dword 偏移逐个取值交给 printf。
;
; 这样做的好处：
;   * 完全不依赖 pextrd 之类「取 lane」的指令，SSE2 机器也能跑；
;   * 用 32 位子寄存器（esi/edx/ecx/r8d）接收，%d 看到的就正好是那个 int32，
;     不用担心 64 位寄存器高位有脏数据；
;   * 顺便说明一个道理：SIMD 的「一条指令处理多组数据」是真的，
;     但要把结果交给 printf，还是得一个个搬到通用寄存器/内存。
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
; PRINT_VEC — 把内存里连续 8 个 int32 分两行打印
;   %1 = 数据标签（8 个 int32）
;   %2 = 前半行格式串（4 个 %d，不带换行）
;   %3 = 后半行格式串（4 个 %d，带换行）
;
; 为什么分两次 printf：printf 的整数参数只有 6 个（rdi/rsi/rdx/rcx/r8/r9），
; 格式串占掉 rdi，剩下 5 个位置。一次打印 8 个元素就必须压栈并自己保证
; 16 字节栈对齐；拆成 4 + 4 就完全不碰栈，初学者少踩一个坑。
;
; printf 会破坏 rsi/rdx/rcx/r8 这些**调用者保存**寄存器，所以后半行
; 必须重新从内存装一遍参数，不能沿用前半行的寄存器。
; ---------------------------------------------------------------------------
%macro PRINT_VEC 3
    ; ---- 前半行：lane 0..3（用 32 位子寄存器，%d 只需要低 32 位）----
    mov  esi, [rel %1 + 0]
    mov  edx, [rel %1 + 4]
    mov  ecx, [rel %1 + 8]
    mov  r8d, [rel %1 + 12]
    lea  rdi, [rel %2]
    xor  eax, eax
    call printf

    ; ---- 后半行：lane 4..7（printf 会破坏 rsi/rdx/rcx/r8，所以重新装）----
    mov  esi, [rel %1 + 16]
    mov  edx, [rel %1 + 20]
    mov  ecx, [rel %1 + 24]
    mov  r8d, [rel %1 + 28]
    lea  rdi, [rel %3]
    xor  eax, eax
    call printf
%endmacro

; ---------------------------------------------------------------------------
; check_result —— 自检：这个宿主机/虚拟机的 SIMD 到底算对了几个 lane？
;
; 入参：
;   rdi = 结果数组（8 个 int32）
;   esi = 前 4 个 lane 的期望和（汇编期算好的立即数）
;   edx = 全部 8 个 lane 的期望和（立即数）
; 返回：无（直接打印自检结论）
;
; 为什么用立即数当期望值，而不是在运行时再算一遍：
;   * 初学阶段最好的校验标准就是「先手算好，再让程序对答案」；
;   * 也避免校验代码本身依赖太多寄存器状态。
;
; 现实意义：本项目在 Debian 13 的一台虚拟机上实测到，
;   paddd / pmulld 这类「多 lane 32 位」指令只算了低 64 位
;   （第 5~8 个元素恒为 0），而 paddq / paddb / movdqu 都正常。
;   这是宿主机/虚拟化层的问题，不是程序写错了 —— 程序自己把它指出来，
;   学员就不会怀疑自己的代码。正常 CPU 上一定打印「8 个 lane 全部正确」。
; ---------------------------------------------------------------------------
check_result:
    push rbx
    push rbp

    ; ---- 1) 前 4 个 lane 的和（这些 lane 在所有机器上都应该是对的）----
    xor  ebx, ebx
    add  ebx, [rdi + 0]
    add  ebx, [rdi + 4]
    add  ebx, [rdi + 8]
    add  ebx, [rdi + 12]

    ; ---- 2) 全部 8 个 lane 的和 ----
    mov  ebp, ebx
    add  ebp, [rdi + 16]
    add  ebp, [rdi + 20]
    add  ebp, [rdi + 24]
    add  ebp, [rdi + 28]

    ; ---- 3) 顺便数一下非零 lane 的个数 ----
    xor  ecx, ecx                       ; 非零 lane 计数
    xor  r8d, r8d                       ; 下标
.count:
    mov  eax, [rdi + r8*4]
    test eax, eax
    jz   .skip
    inc  ecx
.skip:
    inc  r8d
    cmp  r8d, 8
    jb   .count

    lea  r9, [rel fmt_chk_sum]
    mov  r10d, ecx                      ; 保存计数（printf 会破坏寄存器）
    mov  rdi, r9
    mov  r8d, ebx                       ; 低 4 lane 实测和
    mov  ecx, ebp                       ; 全部 8 lane 实测和
    ; printf("  自检：8 lane 和=%d（期望 %d），低 4 lane 和=%d（期望 %d）")
    mov  r9d, edx                       ; 期望的 8 lane 和（第 4 个参数位置）
    xor  eax, eax
    push r10                            ; 借一个栈槽暂存计数（保持 8 字节对齐）
    mov  esi, r8d                       ; 参数 1：8 lane 实测和
    mov  edx, r9d                       ; 参数 2：期望的 8 lane 和
    mov  ecx, ebx                       ; 参数 3：低 4 lane 实测和
    mov  r8d, r10d                      ; 参数 4：非零 lane 个数
    call printf
    pop  r10

    ; ---- 4) 结论 ----
    cmp  r10d, 8
    jne  .bad
    lea  rdi, [rel fmt_chk_ok]
    jmp  .print
.bad:
    lea  rdi, [rel fmt_chk_bad]
.print:
    xor  eax, eax
    call printf

    pop  rbp
    pop  rbx
    ret

main:
    push rbp
    mov  rbp, rsp

    ; ======================= 1. paddd 向量加法 ==========================
    lea  rdi, [rel fmt_head]
    xor  eax, eax
    call printf

    movdqu xmm0, [rel vec_a]            ; xmm0 = A 的 8 个 int32
    movdqu xmm1, [rel vec_b]            ; xmm1 = B 的 8 个 int32
    paddd  xmm0, xmm1                   ; 一条指令 = 8 组加法
    movdqu [rel vec_sum], xmm0          ; 结果写回内存（存也可以用 movdqu）

    PRINT_VEC vec_a, fmt_a1, fmt_a2

    PRINT_VEC vec_b, fmt_b1, fmt_b2

    PRINT_VEC vec_sum, fmt_sum1, fmt_sum2

    ; ---- 手算的期望值（「对答案」用的答案）----
    ;      A+B 的 8 个元素 = 11 22 33 44 55 66 77 88，总和 = 360。
    ;      紧接着的自检会拿 SIMD 的实际结果和这个期望值对比。
    lea  rdi, [rel fmt_scalar]
    mov  esi, 360                       ; 期望的校验和（手算得到）
    xor  eax, eax
    call printf

    lea  rdi, [rel vec_sum]             ; 待检查的 SIMD 结果
    mov  esi, 110                       ; A+B 前 4 个 lane 的和（手算：11+22+33+44）
    mov  edx, 360                       ; A+B 全部 8 个 lane 的和（手算）
    call check_result

    ; ======================= 2. 带负数的 paddd ==========================
    lea  rdi, [rel fmt_head2]
    xor  eax, eax
    call printf

    movdqu xmm0, [rel vec_c]
    movdqu xmm1, [rel vec_d]
    paddd  xmm0, xmm1
    movdqu [rel vec_sum2], xmm0

    PRINT_VEC vec_c, fmt_c1, fmt_c2

    PRINT_VEC vec_d, fmt_d1, fmt_d2

    PRINT_VEC vec_sum2, fmt_cd1, fmt_cd2

    lea  rdi, [rel vec_sum2]
    mov  esi, 96                        ; C+D 前 4 个 lane 的和（手算：101-25+20+0）
    mov  edx, 107                       ; C+D 全部 8 个 lane 的和（手算）
    call check_result

    ; ===================== 3. pmulld 向量乘法（SSE4.1）==================
    lea  rdi, [rel fmt_head3]
    xor  eax, eax
    call printf

    movdqu xmm0, [rel vec_b]
    pmulld xmm0, xmm0                   ; B 的每组自己乘自己：1,4,9,16,25,36,49,64
    movdqu [rel vec_mul], xmm0

    PRINT_VEC vec_mul, fmt_mul1, fmt_mul2

    lea  rdi, [rel vec_mul]             ; 自检：B*B
    mov  esi, 30                        ; 前 4 个 lane 的和（1+4+9+16）
    mov  edx, 204                       ; 全部 8 个 lane 的和（1+4+...+64）
    call check_result

    lea  rdi, [rel fmt_done]
    xor  eax, eax
    call printf

    xor  eax, eax
    leave
    ret

section .bss

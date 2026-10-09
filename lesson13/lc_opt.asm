; ===========================================================================
; lc_opt.asm —— 同一个任务两种写法：朴素 vs 优化（SSE2），并说明为什么快
;
; 文件名以 lc_ 开头 → 入口 main，用 gcc -no-pie 链接。
;
; 任务一：求 1024 个 int64 元素的和
;   sum_naive : 每轮加 1 个元素 —— 1 次内存读 + inc + cmp + 条件跳转
;   sum_simd  : 每轮加 2 个元素 —— movdqu + paddq，指令数减半、分支减半
; 任务二：统计 4096 字节的缓冲区里有多少个 'a'
;   count_a_naive : 逐字节比较 + 每字节一次条件跳转（分支预测器压力大）
;   count_a_simd  : 16 字节一次比较（pcmpeqb），把 0xFF 掩成 0x01 后 psadbw 求和
;
; 默认构建只打印“确定的结果”，方便 test.sh 比对。
; 想看真实耗时（每次都不一样，只供观察）：
;   nasm -f elf64 -g -F dwarf -DMEASURE -o lc_opt_m.o lc_opt.asm
;   gcc -no-pie -o lc_opt_m lc_opt_m.o && ./lc_opt_m
; ===========================================================================

default rel

%define SYS_clock_gettime 228
%define CLOCK_MONOTONIC   1

%define ARR_N 1024              ; 数组元素个数
%define STR_N 4096              ; 字符串字节数

extern printf               ; libc 提供的函数：用 nasm 时必须显式 extern

global main

section .data
; ---- SSE2 用的常量（movdqa 要求 16 字节对齐）------------------------------
align 16
xmm_a:      times 16 db 'a'      ; 16 个 'a'，pcmpeqb 的掩码
xmm_one:    times 16 db 1        ; 16 个 0x01，把 0xFF 掩成 0x01

; ---- arr[i] = i % 100 + 1，共 1024 个 qword ---------------------------------
; 这样 1..100 的完整循环有 10 轮（10 * 5050 = 50500），再加 1..24（= 300），
; 所以正确的和是 50800，手算就能验证。
align 8
arr:
%assign i 0
%rep ARR_N
    dq (i % 100) + 1
    %assign i i + 1
%endrep

; ---- strbuf：每 26 个字节一个 'a' ------------------------------------------
; 26 * 157 = 4082，再补 1 个 'a' 和 13 个 'b' 正好 4096 字节，
; 所以正确的 'a' 个数是 157 + 1 = 158。
strbuf:
%rep (STR_N / 26)
    db 'a'
    times 25 db 'b'
%endrep
    db 'a'
    times (STR_N - (STR_N / 26) * 26 - 1) db 'b'

; ---- 输出格式 --------------------------------------------------------------
fmt_ns:     db "naive  sum        = %ld", 10, 0
fmt_ss:     db "simd   sum        = %ld", 10, 0
fmt_nc:     db "naive  count 'a'  = %ld", 10, 0
fmt_sc:     db "simd   count 'a'  = %ld", 10, 0
fmt_ck:     db "check  : results match (%ld)", 10, 0
%ifdef MEASURE
fmt_t1:     db "measure: naive sum   = %ld ns", 10, 0
fmt_t2:     db "measure: simd  sum   = %ld ns", 10, 0
fmt_t3:     db "measure: naive count = %ld ns", 10, 0
fmt_t4:     db "measure: simd  count = %ld ns", 10, 0
%define REPS_SUM 20000          ; 求和跑 2 万遍，让耗时能被 clock_gettime 量到
%define REPS_CNT 5000           ; 统计跑 5 千遍
%endif

section .bss
%ifdef MEASURE
ts:         resq 2              ; clock_gettime 的 struct timespec {tv_sec, tv_nsec}
%endif

section .text
global sum_naive
global sum_simd
global count_a_naive
global count_a_simd

; ---------------------------------------------------------------------------
; long sum_naive(const long *arr, long n)      arr→rdi, n→rsi, 返回 rax
; ---------------------------------------------------------------------------
sum_naive:
    xor eax, eax
    test rsi, rsi
    jle .done
    xor ecx, ecx
.loop:
    add rax, [rdi + rcx*8]      ; 每轮只处理 1 个元素
    inc rcx
    cmp rcx, rsi
    jb .loop
.done:
    ret

; ---------------------------------------------------------------------------
; long sum_simd(const long *arr, long n)
;   一次处理 2 个 qword（一个 xmm 寄存器 128 位），再水平合并。
; ---------------------------------------------------------------------------
sum_simd:
    pxor xmm0, xmm0             ; 向量累加器 = 0
    xor eax, eax                ; 标量结果默认 0（没有整块时用）
    mov rcx, rsi
    shr rcx, 1                  ; 成对的个数 = n / 2
    test rcx, rcx
    jz .tail
    mov rdx, rdi
.blk:
    movdqu xmm1, [rdx]          ; 一次读 16 字节 = 2 个 qword
    paddq xmm0, xmm1            ; 64 位整数逐元素相加（不会进位串到隔壁）
    add rdx, 16
    dec rcx
    jnz .blk
    movhlps xmm1, xmm0          ; 把高 64 位搬到 xmm1 的低 64 位
    paddq xmm0, xmm1            ; 两个 64 位计数器合并
    movq rax, xmm0              ; 取低 64 位作为结果
.tail:
    test rsi, 1                 ; n 是奇数？
    jz .done
    mov rdx, rsi
    dec rdx
    add rax, [rdi + rdx*8]      ; 处理最后一个元素
.done:
    ret

; ---------------------------------------------------------------------------
; long count_a_naive(const char *s, long n)
; ---------------------------------------------------------------------------
count_a_naive:
    xor eax, eax
    test rsi, rsi
    jle .done
    xor ecx, ecx
.loop:
    cmp byte [rdi + rcx], 'a'   ; 每字节一次比较
    jne .next                   ; 每字节一次条件跳转（不可预测，很贵）
    inc rax
.next:
    inc rcx
    cmp rcx, rsi
    jb .loop
.done:
    ret

; ---------------------------------------------------------------------------
; long count_a_simd(const char *s, long n)
;   每轮 16 字节：pcmpeqb 得到 0xFF/0x00，pand 成 0x01/0x00，
;   psadbw 把 16 个字节求和，paddq 累加到 64 位计数器。
; ---------------------------------------------------------------------------
count_a_simd:
    xor eax, eax
    pxor xmm0, xmm0             ; 64 位计数器（只用到低 64 位）
    pxor xmm3, xmm3             ; 全 0，psadbw 的第二个操作数
    movdqa xmm2, [rel xmm_a]    ; 16 个 'a'
    movdqa xmm4, [rel xmm_one]  ; 16 个 0x01
    mov rcx, rsi
    shr rcx, 4                  ; 完整 16 字节块的个数 = n / 16
    test rcx, rcx
    jz .tail
    mov rdx, rdi
.blk:
    movdqu xmm1, [rdx]          ; 16 字节，不要求对齐（字符串未必对齐）
    pcmpeqb xmm1, xmm2          ; 等于 'a' 的字节 → 0xFF，其余 → 0x00
    pand xmm1, xmm4             ; 0xFF → 0x01，0x00 → 0x00
    psadbw xmm1, xmm3           ; 16 个字节的差之和 = 这一块里 'a' 的个数
    paddq xmm0, xmm1
    add rdx, 16
    dec rcx
    jnz .blk
    ; psadbw 把两个 8 字节半区的和分别放在低 64 位和高 64 位，要合并起来
    movq rax, xmm0
    psrldq xmm0, 8
    movq rcx, xmm0
    add rax, rcx
.tail:
    mov rcx, rsi
    and rcx, 15                 ; 尾部不足 16 字节的部分
    jz .done
    mov rdx, rsi
    sub rdx, rcx                ; 尾部起始下标
.tloop:
    cmp byte [rdi + rdx], 'a'
    jne .tnext
    inc rax
.tnext:
    inc rdx
    dec rcx
    jnz .tloop
.done:
    ret

%ifdef MEASURE
; ---------------------------------------------------------------------------
; now_ns() → rax：读 CLOCK_MONOTONIC，换算成纳秒
; （直接发 clock_gettime 系统调用，参数 rdi=时钟号, rsi=缓冲区）
; ---------------------------------------------------------------------------
now_ns:
    mov rax, SYS_clock_gettime
    mov edi, CLOCK_MONOTONIC
    lea rsi, [rel ts]
    syscall
    mov rax, [rel ts + 8]       ; tv_nsec
    mov rdx, [rel ts]           ; tv_sec
    imul rdx, rdx, 1000000000
    add rax, rdx
    ret
%endif

; ===========================================================================
; int main(void)
; ===========================================================================
main:
    push rbp
    mov rbp, rsp
    push r12                    ; 入口 rsp%16==8，push rbp 后 ==0，四个 push 后仍 ==0
    push r13
    push r14
    push r15

    ; ---- 两种求和实现 ------------------------------------------------------
    lea rdi, [rel arr]
    mov rsi, ARR_N
    call sum_naive
    mov r12, rax

    lea rdi, [rel arr]
    mov rsi, ARR_N
    call sum_simd
    mov r13, rax

    ; ---- 两种字符统计实现 --------------------------------------------------
    lea rdi, [rel strbuf]
    mov rsi, STR_N
    call count_a_naive
    mov r14, rax

    lea rdi, [rel strbuf]
    mov rsi, STR_N
    call count_a_simd
    mov r15, rax

    lea rdi, [rel fmt_ns]
    mov rsi, r12
    xor eax, eax
    call printf

    lea rdi, [rel fmt_ss]
    mov rsi, r13
    xor eax, eax
    call printf

    lea rdi, [rel fmt_nc]
    mov rsi, r14
    xor eax, eax
    call printf

    lea rdi, [rel fmt_sc]
    mov rsi, r15
    xor eax, eax
    call printf

    ; ---- 一致性检查：两种实现结果必须相同 ---------------------------------
    xor eax, eax
    cmp r12, r13
    jne .no
    cmp r14, r15
    jne .no
    mov eax, 1
.no:
    lea rdi, [rel fmt_ck]
    mov rsi, rax
    xor eax, eax
    call printf

%ifdef MEASURE
    ; ---- 计时：朴素求和 ----------------------------------------------------
    call now_ns
    mov r12, rax
    mov r13, REPS_SUM
.m_naive_sum:
    lea rdi, [rel arr]
    mov rsi, ARR_N
    call sum_naive
    dec r13
    jnz .m_naive_sum
    call now_ns
    sub rax, r12
    lea rdi, [rel fmt_t1]
    mov rsi, rax
    xor eax, eax
    call printf

    ; ---- 计时：SIMD 求和 ---------------------------------------------------
    call now_ns
    mov r12, rax
    mov r13, REPS_SUM
.m_simd_sum:
    lea rdi, [rel arr]
    mov rsi, ARR_N
    call sum_simd
    dec r13
    jnz .m_simd_sum
    call now_ns
    sub rax, r12
    lea rdi, [rel fmt_t2]
    mov rsi, rax
    xor eax, eax
    call printf

    ; ---- 计时：朴素统计 ----------------------------------------------------
    call now_ns
    mov r12, rax
    mov r13, REPS_CNT
.m_naive_cnt:
    lea rdi, [rel strbuf]
    mov rsi, STR_N
    call count_a_naive
    dec r13
    jnz .m_naive_cnt
    call now_ns
    sub rax, r12
    lea rdi, [rel fmt_t3]
    mov rsi, rax
    xor eax, eax
    call printf

    ; ---- 计时：SIMD 统计 ---------------------------------------------------
    call now_ns
    mov r12, rax
    mov r13, REPS_CNT
.m_simd_cnt:
    lea rdi, [rel strbuf]
    mov rsi, STR_N
    call count_a_simd
    dec r13
    jnz .m_simd_cnt
    call now_ns
    sub rax, r12
    lea rdi, [rel fmt_t4]
    mov rsi, rax
    xor eax, eax
    call printf
%endif

    pop r15
    pop r14
    pop r13
    pop r12
    xor eax, eax
    leave
    ret

; ===========================================================================
; lc_asm_lib.asm —— 用汇编写一个能被 C 调用的“小库”（System V AMD64 调用约定）
;
; 文件名以 lc_ 开头 → 这个文件是“libc 程序”风格，入口符号叫 main，
; 用 gcc -no-pie 链接（不是 ld），因为链接脚本要 crt1.o 帮忙初始化 libc。
;
; 调用约定速查（详见本课 README）：
;   整数参数 rdi, rsi, rdx, rcx, r8, r9   返回值 rax
;   浮点参数 xmm0 ~ xmm7                  返回值 xmm0
;   调用者保存（可以随便改）：rax rcx rdx rsi rdi r8 r9 r10 r11 + 全部 xmm
;   被调用者保存（改了必须还原）：rbx rbp r12 r13 r14 r15
;   本文件所有函数只用调用者保存寄存器，所以一条 push/pop 都不需要。
;
; 三个使用场景（README 里都有完整命令）：
;   1) 单独链接成可执行文件（make all 就是这么做的）：
;        nasm -f elf64 -g -F dwarf -I ../include -o lc_asm_lib.o lc_asm_lib.asm
;        gcc -no-pie -o lc_asm_lib lc_asm_lib.o
;      能成功是因为下面有一个“弱符号 main”（global main:weak）做自测。
;   2) 和 C 混编（本课主角）：
;        nasm -f elf64 -g -F dwarf -o lc_asm_lib.o lc_asm_lib.asm
;        gcc -no-pie -o mix c_driver.c lc_asm_lib.o
;      c_driver.c 里的强符号 main 会覆盖这里的弱符号 main，
;      所以既不会 duplicate symbol，也不会执行到自测那段代码。
;   3) 如果你的工具链不喜欢弱符号，可以用 -DNO_MAIN 编译出纯函数库：
;        nasm -f elf64 -g -F dwarf -DNO_MAIN -o lc_asm_lib.o lc_asm_lib.asm
;      这时 lc_asm_lib.o 里只有 asm_* 子程序，没有 main（不能单独用 gcc 链接）。
; ===========================================================================

default rel

; ---- 外部符号：printf 由 libc 提供，用 nasm 时必须显式 extern ---------------
extern printf

; ---- 导出的符号（:function 是 ELF 符号类型标注，写不写都能跑，写上更规范）--
global asm_add:function
global asm_sum_array:function
global asm_hypot:function
global asm_strlen:function
global asm_dot:function

%ifndef NO_MAIN
global main:weak            ; 弱符号：单独链接时当入口；遇到 C 的强 main 时自动让位
%endif

section .text

; ---------------------------------------------------------------------------
; long asm_add(long a, long b)
;   a → rdi, b → rsi, 返回 rax
; ---------------------------------------------------------------------------
asm_add:
    lea rax, [rdi + rsi]    ; 一条指令算完：rax = rdi + rsi，不碰内存、不碰标志位
    ret

; ---------------------------------------------------------------------------
; long asm_sum_array(const long *arr, long n)
;   arr → rdi, n → rsi, 返回 rax
;   约定：n <= 0 时返回 0
; ---------------------------------------------------------------------------
asm_sum_array:
    xor eax, eax            ; 累加器 = 0（写 eax 自动清零 rax 的高 32 位）
    test rsi, rsi
    jle .done               ; n <= 0：直接返回 0
    xor ecx, ecx            ; 下标 = 0
.loop:
    add rax, [rdi + rcx*8]  ; 取 arr[i]（8 字节）加到 rax
    inc rcx
    cmp rcx, rsi
    jb .loop                ; i < n 就继续（无符号比较，n 已确认 > 0）
.done:
    ret

; ---------------------------------------------------------------------------
; double asm_hypot(double x, double y)
;   x → xmm0, y → xmm1，返回 xmm0 = sqrt(x*x + y*y)
;   浮点参数走 xmm 寄存器，这和整数参数走 rdi/rsi 一样是约定的一部分。
; ---------------------------------------------------------------------------
asm_hypot:
    mulsd xmm0, xmm0        ; xmm0 = x*x
    mulsd xmm1, xmm1        ; xmm1 = y*y
    addsd xmm0, xmm1        ; xmm0 = x*x + y*y
    sqrtsd xmm0, xmm0       ; xmm0 = sqrt(xmm0)；sqrtsd 是“目标 = 源开方”
    ret

; ---------------------------------------------------------------------------
; long asm_strlen(const char *s)
;   s → rdi，返回 rax（不含结尾的 '\0'）
; ---------------------------------------------------------------------------
asm_strlen:
    xor eax, eax
.loop:
    cmp byte [rdi + rax], 0 ; 一次比较一个字节
    je .done
    inc rax
    jmp .loop
.done:
    ret

; ---------------------------------------------------------------------------
; double asm_dot(const double *a, const double *b, long n)
;   a → rdi, b → rsi, n → rdx，返回 xmm0 = Σ a[i]*b[i]（标量循环版）
;   C 原型：double asm_dot(const double *, const double *, long);
; ---------------------------------------------------------------------------
asm_dot:
    pxor xmm0, xmm0         ; 累加器 = 0.0（pxor 比 movsd xmm0, 0 更省事）
    test rdx, rdx
    jle .done
    xor ecx, ecx
.loop:
    movsd xmm1, [rdi + rcx*8]   ; 取 a[i]（8 字节 double）
    mulsd xmm1, [rsi + rcx*8]   ; xmm1 *= b[i]（内存操作数可以直接参与运算）
    addsd xmm0, xmm1
    inc rcx
    cmp rcx, rdx
    jb .loop
.done:
    ret

; ===========================================================================
; 下面是“单独链接”用的自测 main（弱符号）
;   与 c_driver.c 一起链接时不会用到它，只是让 make all 能通过。
;   用 -DNO_MAIN 编译时这一整段不参与汇编。
; ===========================================================================
%ifndef NO_MAIN

section .data
nums:       dq 1, 2, 3, 4, 5, 6, 7, 8
vec_a:      dq 1.0, 2.0, 3.0
vec_b:      dq 4.0, 5.0, 6.0
hello:      db "hello", 0
three:      dq 3.0
four:       dq 4.0

fmt_add:    db "asm_add(2,3)        = %ld", 10, 0
fmt_sum:    db "asm_sum_array(nums) = %ld", 10, 0
fmt_hyp:    db "asm_hypot(3,4)      = %f", 10, 0
fmt_len:    db "asm_strlen(%s)  = %ld", 10, 0
fmt_dot:    db "asm_dot(a,b)        = %f", 10, 0
fmt_head:   db "=== lc_asm_lib 自测（弱符号 main）===", 10, 0

section .text

main:
    push rbp
    mov rbp, rsp
    ; 入口处 rsp % 16 == 8（call 压了返回地址），push rbp 之后 == 0，
    ; 所以下面每次 call printf 时栈都是 16 字节对齐的。

    lea rdi, [rel fmt_head]
    xor eax, eax
    call printf

    mov rdi, 2
    mov rsi, 3
    call asm_add
    lea rdi, [rel fmt_add]
    mov rsi, rax
    xor eax, eax                ; 变参函数：al = 用到的向量寄存器个数 = 0
    call printf

    lea rdi, [rel nums]
    mov rsi, 8
    call asm_sum_array
    lea rdi, [rel fmt_sum]
    mov rsi, rax
    xor eax, eax
    call printf

    movsd xmm0, [rel three]
    movsd xmm1, [rel four]
    call asm_hypot
    lea rdi, [rel fmt_hyp]
    mov eax, 1                  ; 用到了 xmm0 → al = 1
    call printf

    lea rdi, [rel hello]
    call asm_strlen
    lea rdi, [rel fmt_len]
    lea rsi, [rel hello]
    mov rdx, rax
    xor eax, eax
    call printf

    lea rdi, [rel vec_a]
    lea rsi, [rel vec_b]
    mov rdx, 3
    call asm_dot
    lea rdi, [rel fmt_dot]
    mov eax, 1
    call printf

    xor eax, eax                ; return 0
    leave                       ; mov rsp, rbp; pop rbp
    ret

%endif ; NO_MAIN

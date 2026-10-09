# 第 07 课：函数、栈、call/ret 与调用约定

## 本课目标

* 用 `call` / `ret` 把一段代码封装成函数，理解返回地址是怎么压栈、怎么弹回来的；
* 掌握 System V AMD64 调用约定里参数寄存器（`rdi, rsi, rdx, rcx, r8, r9`）和返回值寄存器（`rax`）；
* 用 `push` / `pop` 亲手观察栈指针 `rsp` 的变化，理解「栈向下增长」和「函数帧」；
* 分清「调用者保存」和「被调用者保存」寄存器，知道什么时候必须 `push` / `pop`；
* 会用 `push rbp; mov rbp, rsp` / `leave` 建立和拆除栈帧。

## 新概念 / 新指令

| 指令 / 概念 | 一句话说明 | 小例子 |
|---|---|---|
| `call 标签` | 把下一条指令的地址（返回地址）压栈，然后跳到标签 | `call add_two` |
| `ret` | 从栈顶弹出 8 字节当作地址跳过去 | `ret` |
| 参数寄存器 | 第 1~6 个整数参数依次放 `rdi rsi rdx rcx r8 r9` | `mov rdi, 12` / `mov rsi, 30` |
| 返回值 | 整数返回值放 `rax` | `mov rax, rdi; add rax, rsi` |
| 第 7 个及以后的参数 | 放在栈上，进入函数后是 `[rsp+8]`、`[rsp+16]`… | `push qword 7` + `add rax, [rsp+8]` |
| `push 寄存器/立即数` | `rsp -= 8`，再把值写到 `[rsp]` | `push rbx` |
| `pop 寄存器` | 从 `[rsp]` 读值到寄存器，然后 `rsp += 8` | `pop rbx` |
| 函数序言 | `push rbp` + `mov rbp, rsp`，建立固定参照点 | 见 `add_four` |
| `leave` | 等价于 `mov rsp, rbp` 再 `pop rbp`，拆除栈帧 | `leave` + `ret` |
| 调用者保存 | 按 System V 约定是 `rax rcx rdx rsi rdi r8-r11`，函数可以随便改 | 循环计数器放 `rcx` 前要想一想 |
| 被调用者保存 | 按 System V 约定是 `rbx rbp r12-r15`，函数想用就得先存后恢复 | `push rbx` … `pop rbx` |
| io.inc 的实际保证 | 比 System V 更严：`rdi rsi rdx rbx rbp r12-r15` 都保持不变，只破坏 `rax rcx r11` | 见下方「常见坑」 |
| 栈对齐 | `call` 执行时 `rsp` 最好是 16 的倍数 | 见「常见坑」 |
| `add rsp, N` | 一次性弹掉 N 字节，比连写多个 `pop` 省事 | `add rsp, 16` |

## 示例 1：add_func.asm —— 第一个函数

### 完整源码

```asm
; ===========================================================================
; add_func.asm —— 第 07 课示例 1：第一个函数（call / ret / 返回值在 rax）
;
; 编译（在 lesson07 目录下）：
;   make
; 运行：
;   ./add_func
;
; 知识点：
;   * call 标签 —— 把「返回地址」压栈，然后跳到标签处执行
;   * ret       —— 从栈顶弹出返回地址，跳回去
;   * 参数按 System V 约定放在 rdi, rsi（第 1、2 个参数）
;   * 返回值放在 rax
;   * 被调用者保存（rbx/rbp/r12-r15）与调用者保存的含义
; ===========================================================================

section .data
    ; ---- 提示文字 -------------------------------------------------------
    title      db "=== add_two(a, b)：参数用 rdi/rsi，返回值用 rax ==="
    title_len  equ $ - title

    l_test     db "add_two(a_value, b_value)   = "
    l_test_len equ $ - l_test

    l_inline   db "add_two(1000, 2345)         = "
    l_inline_len equ $ - l_inline

    l_neg      db "add_two(7, -20)             = "
    l_neg_len  equ $ - l_neg

    l_wrap     db "add_two(1, -1)              = "
    l_wrap_len equ $ - l_wrap

    l_four     db "add_four(r12, rbx, 100, -5) = "
    l_four_len equ $ - l_four

    l_after    db "函数返回后 rbx（还是 22）   = "
    l_after_len equ $ - l_after

    ; ---- 演示用的操作数 -------------------------------------------------
    a_value    dq 12
    b_value    dq 30

section .text
    global _start
%include "io.inc"

; ---------------------------------------------------------------------------
; _start —— 程序入口（相当于 C 的 main）
; ---------------------------------------------------------------------------
_start:
    ; 打印标题
    lea rsi, [rel title]
    mov rdx, title_len
    call io_println

    ; ---- 第 1 个调用：参数来自内存里的变量 ------------------------------
    lea rsi, [rel l_test]
    mov rdx, l_test_len
    call io_print

    mov rdi, [rel a_value]      ; 第 1 个参数 = 12
    mov rsi, [rel b_value]      ; 第 2 个参数 = 30
    call add_two                ; 返回值在 rax
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 第 2 个调用：参数是立即数 --------------------------------------
    lea rsi, [rel l_inline]
    mov rdx, l_inline_len
    call io_print

    mov edi, 1000
    mov esi, 2345
    call add_two
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 第 3 个调用：带负数（补码加法，和 C 的 int64_t 一样） ----------
    lea rsi, [rel l_neg]
    mov rdx, l_neg_len
    call io_print

    mov rdi, 7
    mov rsi, -20                ; 有符号立即数可以直接写 -20
    call add_two
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 第 4 个调用：1 + (-1) = 0，顺便看 -1 的 64 位补码 --------------
    lea rsi, [rel l_wrap]
    mov rdx, l_wrap_len
    call io_print

    mov rdi, 1
    mov rsi, -1                 ; -1 的 64 位补码就是 0xFFFFFFFFFFFFFFFF
    call add_two
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 第 5 个调用：嵌套调用 + 被调用者保存寄存器 ---------------------
    mov r12, 20                 ; r12 是被调用者保存寄存器
    mov rbx, 22                 ; rbx 也是

    lea rsi, [rel l_four]
    mov rdx, l_four_len
    call io_print

    ; 按 rdi, rsi, rdx, rcx 的顺序放第 1..4 个参数
    mov rdi, r12
    mov rsi, rbx
    mov rdx, 100                ; 写 rdx 而不是 edx，风格统一
    mov rcx, -5                 ; ⚠ 负数千万别写 mov ecx, -5（见 README「常见坑」）
    call add_four               ; 内部会调用 add_two_rbx（故意破坏 rbx）
    mov rdi, rax
    call io_print_int
    call io_newline

    ; 如果 add_two_rbx 老老实实保存、恢复了 rbx，这里 rbx 还应该是 22
    lea rsi, [rel l_after]
    mov rdx, l_after_len
    call io_print
    mov rdi, rbx
    call io_print_int
    call io_newline

    ; ---- 正常退出：退出码 0 --------------------------------------------
    xor rdi, rdi
    call io_exit

; ---------------------------------------------------------------------------
; add_two —— 返回 rdi + rsi
;
;   入参：rdi = 第一个数，rsi = 第二个数
;   返回：rax = 两数之和
;   只用到调用者保存寄存器 rax，所以不需要 push/pop
; ---------------------------------------------------------------------------
add_two:
    mov rax, rdi
    add rax, rsi
    ret

; ---------------------------------------------------------------------------
; add_two_rbx —— 和 add_two 一样，但故意把 rbx 写坏
;
;   目的：演示「被调用者保存」的规矩 —— 谁破坏 rbx，谁负责恢复。
; ---------------------------------------------------------------------------
add_two_rbx:
    push rbx                    ; 先保存调用者的 rbx
    mov rbx, rdi
    add rbx, rsi
    mov rax, rbx
    pop rbx                     ; 返回前恢复，调用者感觉不到 rbx 被用过
    ret

; ---------------------------------------------------------------------------
; add_four —— 返回 a+b+c+d，内部调用 add_two_rbx
;
;   入参：rdi=a, rsi=b, rdx=c, rcx=d
;   返回：rax = a+b+c+d
;
;   注意栈的对齐：这里 push/pop 严格成对（2 个 push、2 个 pop），
;   add_two_rbx 内部也是 1 个 push、1 个 pop，
;   所以进每个函数时 rsp 的对齐状态一路保持不变（详见 README「栈对齐」）。
; ---------------------------------------------------------------------------
add_four:
    push rbp                    ; 标准函数序言
    mov rbp, rsp                ; rbp 指向「栈上保存的旧 rbp」
    push rbx                    ; 本函数要用 rbx，先保存
    push r12                    ; 也要用 r12，先保存（push 两个，对齐不变）

    mov r12, rdx                ; 先把 c 存进 r12（rdx 马上就要被用掉了）
    mov rbx, rcx                ; 再把 d 存进 rbx

    call add_two_rbx            ; 算 a + b（参数已经在 rdi/rsi 里）
    add rax, r12                ; 加 c
    add rax, rbx                ; 加 d

    pop r12
    pop rbx
    leave                       ; = mov rsp, rbp + pop rbp
    ret
```

### 逐段讲解

**1）`_start` 里为什么会有一堆 `call io_print`？**

`io.inc` 就是把 `write(2)` 系统调用包装成的小函数。它和我们的 `add_two` 遵循同一套调用约定：参数放 `rsi`、`rdx`，所以

```asm
lea rsi, [rel title]    ; 缓冲区地址
mov rdx, title_len      ; 长度
call io_println         ; 输出 + 换行
```

这三行就是「汇编版的 `printf` 调用」。

**2）`add_two` 只有三行，但信息量最大**

```asm
add_two:
    mov rax, rdi        ; rax = 第 1 个参数
    add rax, rsi        ; rax += 第 2 个参数
    ret                 ; 返回值就是 rax，直接返回
```

`rax` 既是「返回值寄存器」，也是普通的通用寄存器，这就是为什么每个函数返回前都往 `rax` 里写东西。`ret` 本身不看 `rax`，它只从栈顶取返回地址。

**3）`call` / `ret` 到底做了什么？**

```text
_start 执行 call add_two 时：
    [rsp-8] ← 返回地址（也就是 call 的下一条指令的地址）
    rsp    -= 8
    rip     = add_two

add_two 执行 ret 时：
    rip = [rsp]        ← 恢复成返回地址
    rsp += 8
```

所以「`call` / `ret` 必须配对」本质上就是「压进去一个地址、必须弹出来一个地址」。如果函数中间 `push` 了东西却忘了 `pop`，`ret` 就会把那个东西当返回地址，跳到莫名其妙的地方去（本课「常见坑」里有这种事故的样子）。

**4）被调用者保存寄存器：谁弄坏，谁负责修**

```asm
add_two_rbx:
    push rbx            ; 保存
    mov rbx, rdi
    add rbx, rsi
    mov rax, rbx
    pop rbx             ; 恢复
    ret
```

调用方 `add_four` 在调用前把两个数放在 `r12` 和 `rbx` 里，跨过 `call add_two_rbx` 之后它们必须还在。如果 `add_two_rbx` 不 `push` / `pop`，调用方就会莫名其妙地出错——这种 bug 特别难查，所以约定必须遵守。

**5）`add_four` 的序言和收尾**

```asm
add_four:
    push rbp
    mov rbp, rsp        ; rbp = 本函数帧的基准
    push rbx
    push r12
    ...
    pop r12
    pop rbx
    leave               ; mov rsp, rbp; pop rbp
    ret
```

`rbp` 的作用是「不管 `rsp` 中间怎么变，我都有个固定的参照点」。本函数没有局部变量，其实不建帧也能写对，但建立习惯很重要：以后要用 `[rbp-8]` 访问局部变量、用 `[rbp+16]` 访问第 7 个参数时，没有 `rbp` 就得自己数 `rsp`，非常容易错。

**6）负数为什么不能写 `mov ecx, -5`**

`mov ecx, -5` 会把 `rcx` 写成 `0x00000000FFFFFFFB`（高 32 位被清零），而 `mov rcx, -5` 才是 `0xFFFFFFFFFFFFFFFB`。`add_four` 里如果用了前者，`20+22+100+0xFFFFFFFB` 会得到 `4294967433` 而不是 `137`。这类错误在 64 位汇编里极其常见。

### 期望输出

```text
=== add_two(a, b)：参数用 rdi/rsi，返回值用 rax ===
add_two(a_value, b_value)   = 42
add_two(1000, 2345)         = 3345
add_two(7, -20)             = -13
add_two(1, -1)              = 0
add_four(r12, rbx, 100, -5) = 137
函数返回后 rbx（还是 22）   = 22
```

## 示例 2：stack_demo.asm —— 栈是向下增长的

### 完整源码

```asm
; ===========================================================================
; stack_demo.asm —— 第 07 课示例 2：栈是向下增长的
;
; 编译（在 lesson07 目录下）：
;   make
; 运行：
;   ./stack_demo
;
; 运行时会打印一串十六进制地址。这些地址和内核给的初始栈位置有关，
; 每台机器、每次运行都不一样，但有两点永远成立：
;   1. push 之后 rsp 变小，pop / add rsp 之后 rsp 变大 —— 栈往低地址方向长；
;   2. 下面打印的「相差 N 字节」在同一次运行里完全固定。
;
; 本程序把基准 rsp 存在 rbp / r15 里，靠它们算差值。
;   为什么不用 rax 存？因为 io.inc 的打印函数一律只保证
;   rax/rcx/r11 之外的寄存器不变（rbx/rbp/r12-r15 是被调用者保存），
;   拿 rax 存跨调用的值，调用一次 io_print 就被冲掉了。
; ===========================================================================

section .data
    title       db "=== 栈（stack）是向下增长的 ==="
    title_len   equ $ - title

    ; ---- 第一部分：push / pop -------------------------------------------
    s_push      db "--- push 一次，rsp 就减 8（一个 8 字节栈槽）---"
    s_push_len  equ $ - s_push

    s_rsp0      db "起始 rsp（对齐到 16）        = "
    s_rsp0_len  equ $ - s_rsp0

    s_push1     db "第 1 次 push 后的 rsp（下了 "
    s_push1_len equ $ - s_push1

    s_push2     db "第 2 次 push 后的 rsp（下了 "
    s_push2_len equ $ - s_push2

    s_end       db "全部弹干净后的 rsp             = "
    s_end_len   equ $ - s_end

    s_bytes     db " 字节） = "
    s_bytes_len equ $ - s_bytes

    s_unit      db " 字节"
    s_unit_len  equ $ - s_unit

    ; ---- 第二部分：函数帧（frame）---------------------------------------
    s_frame     db "--- 函数帧：push rbp; mov rbp, rsp; sub rsp, 16 ---"
    s_frame_len equ $ - s_frame

    s_rbp       db "函数里 rbp - rsp（局部空间） = "
    s_rbp_len   equ $ - s_rbp

    s_frame_rsp db "函数里 rsp                   = "
    s_frame_rsp_len equ $ - s_frame_rsp

    s_retaddr   db "call 压进去的返回地址槽位    = "
    s_retaddr_len equ $ - s_retaddr

    s_frame_ok  db "返回地址槽里存的确实是下一条指令的地址，"
    s_frame_ok_len equ $ - s_frame_ok
    s_frame_ok2 db "所以 ret 才能准确跳回来。"
    s_frame_ok2_len equ $ - s_frame_ok2

    ; 两个演示用的数（作为立即数 push 到栈上）
    v_one       equ 0x1111
    v_two       equ 0x2222

section .text
    global _start
%include "io.inc"

_start:
    ; 把 rsp 对齐到 16，这样打印出来的地址末尾都是 0，好对照
    and rsp, -16
    mov rbp, rsp                ; rbp = rsp0：全程不动的基准
    mov r15, rsp                ; r15 = rsp0（r15 也是被调用者保存）

    lea rsi, [rel title]
    mov rdx, title_len
    call io_println

    lea rsi, [rel s_push]
    mov rdx, s_push_len
    call io_println

    ; ---- 打印起始 rsp ---------------------------------------------------
    lea rsi, [rel s_rsp0]
    mov rdx, s_rsp0_len
    call io_print
    mov rdi, rbp
    call io_print_hex
    call io_newline

    ; ---- push 两个数 ----------------------------------------------------
    push v_one                  ; rsp = rsp0 - 8
    push v_two                  ; rsp = rsp0 - 16

    ; 第 1 次 push 后的 rsp 等于 rbp - 8
    lea rsi, [rel s_push1]
    mov rdx, s_push1_len
    call io_print
    mov rdi, 8                  ; 下了 8 字节
    call print_u64
    lea rsi, [rel s_bytes]
    mov rdx, s_bytes_len
    call io_print
    lea rdi, [rbp - 8]
    call io_print_hex
    call io_newline

    ; 现在（第 2 次 push 之后）的 rsp 就是 rsp0 - 16
    lea rsi, [rel s_push2]
    mov rdx, s_push2_len
    call io_print
    mov rdi, r15
    sub rdi, rsp                ; 下了 16 字节
    call print_u64
    lea rsi, [rel s_bytes]
    mov rdx, s_bytes_len
    call io_print
    mov rdi, rsp
    call io_print_hex
    call io_newline

    ; ---- 弹干净 ---------------------------------------------------------
    ; 效果上等于 pop 两次；这里直接用 add rsp, 16 更直观
    add rsp, 16

    lea rsi, [rel s_end]
    mov rdx, s_end_len
    call io_print
    mov rdi, rsp
    call io_print_hex
    call io_newline

    ; ---- 第二部分：函数帧 ------------------------------------------------
    lea rsi, [rel s_frame]
    mov rdx, s_frame_len
    call io_println
    call frame_probe            ; 内部把三个观测值写进 .bss

    lea rsi, [rel s_rbp]
    mov rdx, s_rbp_len
    call io_print
    mov rdi, [rel frame_size]
    call print_u64
    lea rsi, [rel s_unit]
    mov rdx, s_unit_len
    call io_print
    call io_newline

    lea rsi, [rel s_frame_rsp]
    mov rdx, s_frame_rsp_len
    call io_print
    mov rdi, [rel frame_rsp]
    call io_print_hex
    call io_newline

    lea rsi, [rel s_retaddr]
    mov rdx, s_retaddr_len
    call io_print
    mov rdi, [rel ret_slot]
    call io_print_hex
    call io_newline

    lea rsi, [rel s_frame_ok]
    mov rdx, s_frame_ok_len
    call io_println
    lea rsi, [rel s_frame_ok2]
    mov rdx, s_frame_ok2_len
    call io_println

    xor rdi, rdi
    call io_exit

; ---------------------------------------------------------------------------
; frame_probe —— 演示一个标准函数帧长什么样
;
; 刚进函数时栈上的布局（地址从高到低）：
;       [rsp + 8]   = _start 的 rbp（上一帧的帧基址）
;       [rsp]       = 返回地址（call frame_probe 压进去的）
;
; 序言执行完之后：
;       [rbp + 8]   = 返回地址
;       [rbp]       = 旧的 rbp
;       [rbp - 8]   = 局部空间的高 8 字节
;       [rbp - 16]  = 局部空间的低 8 字节  ← 函数体执行时 rsp 在这里
;
; 本函数把三个观测值记到 .bss 里：帧大小、当时的 rsp、返回地址槽的地址。
; ---------------------------------------------------------------------------
frame_probe:
    push rbp
    mov rbp, rsp
    sub rsp, 16                 ; 开 16 字节局部空间（保持 16 字节对齐）

    mov rax, rbp
    sub rax, rsp                ; 帧大小 = rbp - rsp = 16
    mov [rel frame_size], rax

    mov [rel frame_rsp], rsp

    lea rax, [rbp + 8]          ; 返回地址就在 rbp + 8 处
    mov [rel ret_slot], rax

    leave                       ; = mov rsp, rbp + pop rbp
    ret

; ---------------------------------------------------------------------------
; print_u64 —— 把 rdi 里的无符号数按十进制打印出来
;
;   本课只拿它打印「小整数」（偏移量），所以没有处理 0 之外的特殊情况，
;   但 0 也要能正确打印成 "0"（do-while 结构天然满足）。
; ---------------------------------------------------------------------------
print_u64:
    push rbx                    ; 本函数要用 rbx（被调用者保存），先存起来
    lea rbx, [rel numbuf + 24]  ; rbx 指向缓冲区末尾，从后往前填
    mov rax, rdi
    mov r8, 10                  ; 除数 10

.loop:
    xor rdx, rdx                ; div 前必须清零 rdx（被除数高 64 位）
    div r8                      ; rax = rax / 10，rdx = rax % 10
    add dl, '0'
    dec rbx
    mov [rbx], dl
    test rax, rax
    jnz .loop

    mov rsi, rbx
    lea rdx, [rel numbuf + 24]
    sub rdx, rbx
    call io_print

    pop rbx
    ret

section .bss
    frame_size  resq 1          ; 函数帧大小
    frame_rsp   resq 1          ; 函数里的 rsp
    ret_slot    resq 1          ; 返回地址槽的地址
    numbuf      resb 24         ; 十进制转换缓冲区
```

### 逐段讲解

**1）为什么开头要 `and rsp, -16`？**

进程刚启动时 `rsp` 本来就接近页边界，但具体值不确定。`and rsp, -16` 把它强行对齐到 16 的倍数，好处是打印出来的地址末尾都是 `0`，读者一眼能看出「每次 `push` 都减 8」。这一句会丢掉最多 15 个字节的栈空间，对演示无所谓。

**2）`push 0x1111` 到底压进去几个字节？**

NASM 遇到 `push 立即数` 时，如果值能放进 32 位有符号数，就生成 `push imm32`（操作码 `68`）。在 64 位模式下这条指令会**把立即数符号扩展成 64 位再压栈**，也就是说压进去的仍然是一个完整的 8 字节栈槽：

```text
push 0x1111 之后：
    [rsp] = 00 00 00 00 00 00 11 11
    rsp  -= 8
```

所以不需要先 `mov eax, 0x1111` 再 `push rax`——那是「值超过 32 位」或者「想压一个 64 位地址」时才需要的手法。

**3）为什么打印「第 1 次 push 后的 rsp」用 `[rbp - 8]`？**

因为我们无法回到过去重新读一次 `rsp`；但第一次 `push` 之后的 `rsp` 必然等于 `rsp0 - 8`，而 `rbp` 就存着 `rsp0`，所以直接用 `lea rdi, [rbp - 8]` 就能把这个历史值算出来。第二次同理，用 `mov rdi, r15; sub rdi, rsp` 直接量当前值。

**4）`frame_probe` 里的三个观测值**

```asm
sub rsp, 16
mov rax, rbp
sub rax, rsp            ; 帧大小
mov [rel frame_rsp], rsp
lea rax, [rbp + 8]      ; 返回地址槽
```

这正好对应 C 编译器为

```c
long f(void) { char buf[16]; ... }
```

生成的序言。学会看这段，以后用 `gdb` 调 C 程序的栈帧就不陌生了。

**5）`ret` 是怎么找到回家的路的**

`call frame_probe` 时返回地址被压在 `[rsp]`；序言 `push rbp` 后它变成了 `[rbp + 8]`。函数结束 `leave` 把 `rsp` 恢复，`ret` 再从栈顶读到它。所以只要 `push` / `pop` 平衡，`ret` 永远能回去。

### 期望输出

```text
=== 栈（stack）是向下增长的 ===
--- push 一次，rsp 就减 8（一个 8 字节栈槽）---
起始 rsp（对齐到 16）        = 0x7ffff01ffee0
第 1 次 push 后的 rsp（下了 8 字节） = 0x7ffff01ffed8
第 2 次 push 后的 rsp（下了 16 字节） = 0x7ffff01ffed0
全部弹干净后的 rsp             = 0x7ffff01ffee0
--- 函数帧：push rbp; mov rbp, rsp; sub rsp, 16 ---
函数里 rbp - rsp（局部空间） = 16 字节
函数里 rsp                   = 0x7ffff01ffec0
call 压进去的返回地址槽位    = 0x7ffff01ffed8
返回地址槽里存的确实是下一条指令的地址，
所以 ret 才能准确跳回来。
```

> 十六进制地址在不同机器 / 不同次运行中会变（有 ASLR 地址随机化），
> 但「下了 8 字节」「下了 16 字节」「局部空间 16 字节」这些**差值永远一样**。
> `test.sh` 只检查差值和固定文字，不检查具体地址。

## 示例 3：multi_args.asm —— 6 个参数怎么传

### 完整源码

```asm
; ===========================================================================
; multi_args.asm —— 第 07 课示例 3：6 个参数怎么传（寄存器 + 栈）
;
; 编译（在 lesson07 目录下）：
;   make
; 运行：
;   ./multi_args
;
; System V AMD64 调用约定规定，整数/指针参数按顺序放进：
;   第 1 个 rdi、第 2 个 rsi、第 3 个 rdx、第 4 个 rcx、第 5 个 r8、第 6 个 r9
; 超出的第 7、8、… 个参数才压栈（从右往左压），返回值永远在 rax。
;
; 注意返回值不够用时（比如要返回两个值），rax 只能放一个，
; 另一个就得靠「调用者传进来的内存地址」写回去（见 README 里的说明）。
; ===========================================================================

section .data
    title      db "=== sum6(a,b,c,d,e,f)：参数依次进 rdi,rsi,rdx,rcx,r8,r9 ==="
    title_len  equ $ - title

    l_head     db "  a    b    c    d    e    f   | 和"
    l_head_len equ $ - l_head

    l_case     db "sum6(1,2,3,4,5,6)      = "
    l_case_len equ $ - l_case

    l_case2    db "sum6(10,20,30,40,50,60) = "
    l_case2_len equ $ - l_case2

    l_neg      db "sum6(-1,-2,-3,-4,-5,-6) = "
    l_neg_len  equ $ - l_neg

    l_all      db "sum6(100,200,300,400,500,600) = "
    l_all_len  equ $ - l_all

    l_seven    db "sum7(a..f, 第 7 个参数在栈上) = "
    l_seven_len equ $ - l_seven

    l_stack    db "  第 7 个参数写在栈上：[rsp+8] 就是它（[rsp] 是返回地址）"
    l_stack_len equ $ - l_stack

    ; 一批演示数据（情形 2 用）
    d1         dq 10
    d2         dq 20
    d3         dq 30
    d4         dq 40
    d5         dq 50
    d6         dq 60

section .text
    global _start
%include "io.inc"

_start:
    lea rsi, [rel title]
    mov rdx, title_len
    call io_println

    lea rsi, [rel l_head]
    mov rdx, l_head_len
    call io_println

    ; ---- 情形 1：六个立即数 ---------------------------------------------
    ; 把 6 个数依次放进 6 个参数寄存器。放的顺序无所谓，
    ; 只要别用错寄存器就行。
    lea rsi, [rel l_case]
    mov rdx, l_case_len
    call io_print               ; ← 先把标题打出去，rsi/rdx 才能腾出来当参数

    mov rdi, 1
    mov rsi, 2                  ; ⚠ rsi 又被借用了，但上一行的打印已经完成
    mov rdx, 3
    mov rcx, 4
    mov r8,  5
    mov r9,  6
    call sum6
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 情形 2：六个变量 -----------------------------------------------
    lea rsi, [rel l_case2]
    mov rdx, l_case2_len
    call io_print

    mov rdi, [rel d1]
    mov rsi, [rel d2]
    mov rdx, [rel d3]
    mov rcx, [rel d4]
    mov r8,  [rel d5]
    mov r9,  [rel d6]
    call sum6
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 情形 3：全负数（再次提醒负数与标号位数）------------------------
    lea rsi, [rel l_neg]
    mov rdx, l_neg_len
    call io_print

    mov rdi, -1
    mov rsi, -2
    mov rdx, -3
    mov rcx, -4
    mov r8,  -5
    mov r9,  -6
    call sum6
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 情形 4：大一点的数 ---------------------------------------------
    lea rsi, [rel l_all]
    mov rdx, l_all_len
    call io_print

    mov rdi, 100
    mov rsi, 200
    mov rdx, 300
    mov rcx, 400
    mov r8,  500
    mov r9,  600
    call sum6
    mov rdi, rax
    call io_print_int
    call io_newline

    ; ---- 情形 5：第 7 个参数必须走栈 ------------------------------------
    lea rsi, [rel l_seven]
    mov rdx, l_seven_len
    call io_print

    mov rdi, 1
    mov rsi, 2
    mov rdx, 3
    mov rcx, 4
    mov r8,  5
    mov r9,  6
    push qword 7                ; 第 7 个参数：压栈
                                ; 压完 rsp 还是 16 的倍数，call 时就有
                                ; 「rsp+8 是 16 的倍数」这个标准状态
    call sum7
    add rsp, 8                  ; 调用完必须把参数收回来，保持 rsp 平衡
    mov rdi, rax
    call io_print_int
    call io_newline

    lea rsi, [rel l_stack]
    mov rdx, l_stack_len
    call io_println

    xor rdi, rdi
    call io_exit

; ---------------------------------------------------------------------------
; sum6 —— 返回 a+b+c+d+e+f
;
;   入参：rdi=a, rsi=b, rdx=c, rcx=d, r8=e, r9=f
;   返回：rax = 六个数的和
;
;   函数体里只碰了 rax、rdi、rsi、rdx、rcx、r8、r9，
;   全是可以随便改的「调用者保存」寄存器，所以不用 push/pop。
;   累加时特意用 add rax, rXX 一个个加，方便对照它的参数寄存器。
; ---------------------------------------------------------------------------
sum6:
    mov rax, rdi                ; rax = a
    add rax, rsi                ; + b
    add rax, rdx                ; + c
    add rax, rcx                ; + d
    add rax, r8                 ; + e
    add rax, r9                 ; + f
    ret

; ---------------------------------------------------------------------------
; sum7 —— 返回 7 个数的和，第 7 个数在栈上
;
;   入参：rdi..r9 = 前 6 个，栈上 [rsp+8] = 第 7 个（[rsp] 是返回地址）
;   返回：rax
;
;   为什么是 [rsp+8] 而不是 [rsp]？
;   因为 call sum7 先把返回地址压在了栈顶，第 7 个参数在它上面一格。
;   用 rbp 建立帧之后就是 [rbp+16]，两种写法等价（见 README）。
; ---------------------------------------------------------------------------
sum7:
    mov rax, rdi
    add rax, rsi
    add rax, rdx
    add rax, rcx
    add rax, r8
    add rax, r9
    add rax, [rsp + 8]          ; 第 7 个参数在栈上
    ret
```

### 逐段讲解

**1）参数寄存器的顺序必须记牢**

```text
第 1 个 rdi    第 2 个 rsi    第 3 个 rdx
第 4 个 rcx    第 5 个 r8     第 6 个 r9
```

注意有两个「反直觉」的地方：

* 第 4 个是 `rcx` 而不是 `r10`——`r10` 是**系统调用**的第 4 个参数，两者不一样；
* 第 5、6 个是 `r8`、`r9`，不是 `rbx`、`rbp`（后两个是被调用者保存寄存器，留给函数自己用）。

**2）`mov rsi, 2` 会覆盖前面用来传字符串地址的 `rsi`**

情形 1 里先用 `lea rsi, [rel l_case]` 打印标题，之后又把 `rsi` 当作第 2 个参数。这在汇编里完全正常——打印已经做完了，寄存器可以重用了。但顺序不能颠倒：如果你把 `mov rsi, 2` 写到 `call io_print` 前面，打印的内容就变成「地址 2 处的内存」了。

**3）第 7 个参数走栈**

```asm
push qword 7
call sum7
add rsp, 8
```

进入 `sum7` 时栈顶是返回地址，第 7 个参数在 `[rsp+8]`。如果建立帧（`push rbp; mov rbp, rsp`），它就变成 `[rbp+16]`：

```text
[rbp + 16]   第 7 个参数
[rbp + 8]    返回地址
[rbp + 0]    保存的旧 rbp      ← rbp 指这里
[rbp - 8]    局部变量……
```

**4）`add rsp, 8` 不能忘**

`push qword 7` 让 `rsp` 减了 8；如果调用完不还回去，下一次 `ret` 就会弹到错误的地址。这类「栈不平衡」是汇编新手最常见的崩溃原因。

**5）返回值只有一个 `rax`，想返回两个怎么办？**

把第二个结果写到「调用者传进来的地址」里。例如：

```asm
; 约定：rdi = 一个地址，函数把第二个结果写到那里
divmod:
    mov rax, rdi        ; 被除数
    xor rdx, rdx
    mov rcx, 10
    div rcx             ; rax = 商，rdx = 余数
    mov rcx, rsi        ; rsi 是调用者给的地址
    mov [rcx], rdx      ; 余数写到那块内存
    ret                 ; 商留在 rax
```

### 期望输出

```text
=== sum6(a,b,c,d,e,f)：参数依次进 rdi,rsi,rdx,rcx,r8,r9 ===
  a    b    c    d    e    f   | 和
sum6(1,2,3,4,5,6)      = 21
sum6(10,20,30,40,50,60) = 210
sum6(-1,-2,-3,-4,-5,-6) = -21
sum6(100,200,300,400,500,600) = 2100
sum7(a..f, 第 7 个参数在栈上) = 28
  第 7 个参数写在栈上：[rsp+8] 就是它（[rsp] 是返回地址）
```

## 编译与运行

```bash
cd lesson07
make                # 编译 add_func、stack_demo、multi_args
./add_func
./stack_demo
./multi_args
make test           # 跑自测脚本 test.sh
make clean          # 清理
```

## 动手练习

1. 给 `add_two` 加一个 `add_three(a, b, c)`（第三个参数放 `rdx`），在 `_start` 里调用并打印结果。
2. 写一个 `sum_stack` 函数，用**栈**传全部 3 个参数（调用方 `push` 三次，函数里用 `[rsp+8]`、`[rsp+16]`、`[rsp+24]` 读），验证结果和 `add_three` 一样。
3. 写一个 `mul_two(rdi, rsi)`，内部用 `imul`，故意**不**保存 `rbx` 就使用它，然后观察调用方 `rbx` 的值被破坏。再把 `push` / `pop` 补上，看值恢复正常。
4. 修改 `stack_demo`：连 `push` 三次，打印「下了 24 字节」，并用 `add rsp, 24` 一次弹干净。
5. 在 `frame_probe` 里改成 `sub rsp, 32`，看输出里「局部空间」变成多少；再想想如果把 `sub rsp, 32` 换成 `sub rsp, 24`，`rsp` 的对齐会变成什么样。
6. 思考题：如果 `add_two` 里写成 `push rbx` 却忘了 `pop`，`_start` 第一次调用它会从哪里崩？（提示：`ret` 弹到的是 `rbx` 的旧值。）

## 常见坑

* **`mov ecx, -5` 不等于 `mov rcx, -5`。** 32 位写入会把高 32 位清零，负数就变成了一个约 42 亿的正数。负数一律写 64 位寄存器。
* **`push` 与 `pop` 必须成对。** 少一个 `pop`，`ret` 就会跳到垃圾地址；多一个 `pop`，会读到别人的数据。写完函数后从头数一遍 `push` / `pop`。
* **调用 `io.inc` 的例程后，`rax`、`rcx`、`r11` 不可信。** 这些函数内部执行 `syscall`，内核会用 `rcx`、`r11` 保存返回地址和标志位。`io.inc` 的头注释写明了它的额外保证：`rdi`、`rsi`、`rdx`、`rbx`、`rbp`、`r12`-`r15` 调用前后都不变——也就是说，**只有 `rax`/`rcx`/`r11` 会被破坏**。不过为了养成好习惯，本课跨调用保存的值仍然放在 `rbx`/`rbp`/`r12`-`r15` 里；一旦你以后改用 libc 或别人写的函数，`rdi`/`rsi`/`rdx` 就不再安全了。
* **被调用者保存寄存器借了要还。** `rbx` / `rbp` / `r12`-`r15` 在任何函数里使用前都要 `push`，返回前 `pop`，否则调用方会莫名出错。
* **`call` 时栈要对齐到 16 字节。** System V 约定：`call` 指令执行的那一刻，`rsp` 应该是 16 的倍数（等价说法：进入函数体时 `rsp ≡ 8 (mod 16)`）。本课的 `io.inc` 例程不做浮点/SSE 运算，所以偶尔不对齐也能跑；但一旦以后调用 libc 的 `printf`，不对齐就会直接崩（`movaps` 触发段错误）。保持对齐的简单办法：函数序言写 `push rbp; mov rbp, rsp`，中间的 `push` 成对出现。
* **第 7 个参数在 `[rsp+8]`，不是 `[rsp]`。** `[rsp]` 是返回地址。
* **`ret` 之前别把 `rax` 当成「随便用」的临时寄存器。** 返回值就靠它。
* **本课程序的输出里地址每次都不一样**，写测试脚本时不要比对具体地址。

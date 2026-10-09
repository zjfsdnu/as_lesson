# 第 09 课：文件读写与更多系统调用

## 本课目标

* 学会从栈上取命令行参数：`[rsp]=argc`、`[rsp+8]=argv[0]`、`[rsp+16]=argv[1]`…；
* 用 `openat` / `read` / `write` / `close` 完成一次真实的文件拷贝；
* 掌握「读-写循环」要处理的三件事：短读、短写、EOF（`read` 返回 0）；
* 会检查系统调用的返回值（负数 = `-errno`），并用**退出码**把错误类型报告给调用者；
* 写一个 `wc`：统计字节数、行数、单词数，并做到「跨缓冲区边界」也正确。

## 新概念 / 新指令

| 指令 / 概念 | 一句话说明 | 小例子 |
|---|---|---|
| `argc` / `argv` | 程序入口时 `[rsp]`=参数个数，`[rsp+8]` 起是参数指针 | `mov r12, [rsp]` |
| `argv[i]` | `argv` 是「8 字节指针的数组」，`argv[1]` 就是 `[rsp+16]` | `mov rcx, [rsp+16]` |
| `openat(257)` | 打开/创建文件；第 1 个参数是目录 fd（`AT_FDCWD = -100`） | 见下 |
| `read(0)` | `rax=0, rdi=fd, rsi=buf, rdx=len`；返回读到的字节数，0 表示 EOF | `syscall` |
| `write(1)` | `rax=1, rdi=fd, rsi=buf, rdx=len`；返回实际写出的字节数 | `syscall` |
| `close(3)` | `rax=3, rdi=fd`，释放文件描述符 | `syscall` |
| `-errno` | 系统调用返回**负数**表示出错，`-rax` 就是 errno | `test rax,rax` + `js .err` |
| `AT_FDCWD` | `openat` 的 dirfd，表示「相对当前工作目录」 | `%define AT_FDCWD -100` |
| `O_RDONLY` / `O_WRONLY` / `O_CREAT` / `O_TRUNC` | 打开方式标志，可以用 `\|` 组合 | `O_WRONLY\|O_CREAT\|O_TRUNC` |
| 短读 / 短写 | `read`/`write` 返回的字节数可能小于请求值，必须循环处理 | 见 `copy_file` |
| 缓冲区分块 | 一次读一小块（本课 64 KiB）循环处理，内存占用固定 | `buf_size equ 65536` |
| `.bss` 大缓冲区 | `resb 65536` 只占地址，不占可执行文件体积 | `buf resb buf_size` |
| 退出码 | 用 `io_exit(rdi=码)` 把错误类型告诉 shell | `mov rdi, 2` + `call io_exit` |
| 单词边界 | 「分隔符 → 非分隔符」才算一个新单词，状态要跨缓冲区保存 | `rbp` 存状态 |

## 示例 1：copy.asm —— 命令行版文件拷贝

### 完整源码

```asm
; ===========================================================================
; copy.asm —— 第 09 课示例 1：命令行参数的拷贝工具
;
; 编译（在 lesson09 目录下）：
;   make
; 用法：
;   ./copy 源文件 目标文件
; 例子：
;   printf 'hello, file\n' > /tmp/src.txt
;   ./copy /tmp/src.txt /tmp/dst.txt
;   cat /tmp/dst.txt
;
; 用到的系统调用：
;   openat(257) 打开/创建文件
;   read(0)     读数据
;   write(1)    写数据
;   close(3)    关闭文件
;
; 本课最关键的三个新知识：
;   1. 程序启动时栈上是 [rsp]=argc, [rsp+8]=argv[0], [rsp+16]=argv[1]…
;      取参数之前不能先 push 别的东西（否则偏移全乱）；
;   2. 系统调用第 4 个参数是 r10，不是 rcx；
;   3. syscall 的返回值是负数表示出错（-errno），文件描述符也要判负。
;
; 退出码约定（test.sh 靠它判断错误类型）：
;   0 成功 / 1 参数个数不对 / 2 打不开源文件 / 3 读取失败
;   4 写入失败 / 5 关闭失败 / 6 创建不了目标文件
; ===========================================================================

; AT_FDCWD：openat 的 dirfd 参数，意思是「相对当前工作目录」
; （syscalls.inc 里没有这个常量，本节自己定义）
%define AT_FDCWD -100

section .data
    u1      db "用法: ./copy 源文件 目标文件"
    u1_len  equ $ - u1

    e_open_s db "copy: 打不开源文件: "
    e_open_s_len equ $ - e_open_s

    e_open_d db "copy: 创建不了目标文件: "
    e_open_d_len equ $ - e_open_d

    e_read  db "copy: 读取源文件出错"
    e_read_len equ $ - e_read

    e_write db "copy: 写入目标文件出错"
    e_write_len equ $ - e_write

    e_close db "copy: 关闭文件出错"
    e_close_len equ $ - e_close

    msg_ok  db "复制完成，共 "
    msg_ok_len equ $ - msg_ok

    msg_bytes db " 字节"
    msg_bytes_len equ $ - msg_bytes

    msg_to  db "  -> "
    msg_to_len equ $ - msg_to

    buf_size equ 65536          ; 每次读写 64 KiB（是 8 的倍数，保持栈对齐）

section .bss
    buf     resb buf_size       ; 数据缓冲区（.bss 不占可执行文件体积）

section .text
    global _start
%include "io.inc"

; ---------------------------------------------------------------------------
; _start —— 入口。第一件事就是把 argc/argv 从栈上取下来
; ---------------------------------------------------------------------------
_start:
    ; ---- 0. 取命令行参数（必须在任何 push 之前做）----------------------
    mov r12, [rsp]              ; r12 = argc
    lea r13, [rsp + 8]          ; r13 = &argv[0]

    ; ---- 1. 检查参数个数：argc >= 3（程序名 + 源 + 目标）----------------
    cmp r12, 3
    jge .args_ok
    lea rsi, [rel u1]
    mov rdx, u1_len
    call io_println
    mov rdi, 1
    call io_exit

.args_ok:
    mov r12, [r13 + 8]          ; r12 = argv[1]（源文件名）
    mov r13, [r13 + 16]         ; r13 = argv[2]（目标文件名）

    ; 把两个路径存进 .bss，后面打印/关闭时还要用
    mov [rel path_src], r12
    mov [rel path_dst], r13

    call copy_file              ; 真正的拷贝逻辑

    ; ---- 2. 打印结果：复制完成，共 N 字节  ->  目标 ---------------------
    mov r12, rax                ; r12 = 字节数（copy_file 的返回值）
    lea rsi, [rel msg_ok]
    mov rdx, msg_ok_len
    call io_print
    mov rdi, r12
    call print_u64
    lea rsi, [rel msg_bytes]
    mov rdx, msg_bytes_len
    call io_print

    lea rsi, [rel msg_to]
    mov rdx, msg_to_len
    call io_print
    mov rsi, [rel path_dst]
    call cstr_len
    mov rdx, rax
    call io_println

    xor rdi, rdi
    call io_exit

; ---------------------------------------------------------------------------
; copy_file —— 把 r12 指向的文件拷贝到 r13 指向的文件
;
;   入参：r12 = 源文件路径，r13 = 目标文件路径（都是 NUL 结尾）
;   返回：rax = 成功时拷贝的字节数；失败时打印信息并直接 exit
;
;   寄存器约定：本函数保存并恢复 rbx/rbp/r12-r15，调用者放心。
;   循环里用的 rcx/r8/r9/r10/r11 都是「调用者保存」寄存器；
;   循环内部不调用任何函数（只有 syscall），所以可以放心占用。
;
;   ⚠ 一个真实的坑：syscall 会破坏 rcx 和 r11（内核用它们存 rip/rflags），
;     所以它们只能「在两次 syscall 之间」用，不能跨 syscall 保存东西。
;     真正要跨 syscall 活得久的值（比如累计字节数），这里放在 r15 里。
; ---------------------------------------------------------------------------
copy_file:
    push rbx                    ; 6 个 push = 48 字节，成对 pop 保持栈平衡
    push rbp
    push r12
    push r13
    push r14
    push r15

    lea r14, [rel buf]          ; r14 = 数据缓冲区地址

    ; ---- 1. openat(AT_FDCWD, 源文件, O_RDONLY) --------------------------
    ; 参数顺序：rdi=dirfd, rsi=path, rdx=flags, r10=mode
    mov rax, SYS_openat
    mov rdi, AT_FDCWD           ; -100：相对当前工作目录
    mov rsi, r12                ; 路径
    mov rdx, O_RDONLY           ; 只读
    xor r10d, r10d              ; mode（没有 O_CREAT 时忽略）
    syscall

    test rax, rax
    jns .src_ok                 ; 非负 = 文件描述符
    ; 出错：打印文件名，然后退出
    lea rsi, [rel e_open_s]
    mov rdx, e_open_s_len
    call io_print
    mov rsi, r12
    call cstr_len
    mov rdx, rax
    call io_println
    mov rdi, 2
    call io_exit

.src_ok:
    mov rbx, rax                ; rbx = 源文件描述符

    ; ---- 2. openat(AT_FDCWD, 目标, O_WRONLY|O_CREAT|O_TRUNC, 0644) ------
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r13
    mov rdx, O_WRONLY | O_CREAT | O_TRUNC
    mov r10, 0o644              ; 权限（最终权限还要看 umask）
    syscall

    test rax, rax
    jns .dst_ok
    lea rsi, [rel e_open_d]
    mov rdx, e_open_d_len
    call io_print
    mov rsi, r13
    call cstr_len
    mov rdx, rax
    call io_println
    mov rdi, 6
    call io_exit

.dst_ok:
    mov rbp, rax                ; rbp = 目标文件描述符
    xor r15, r15                ; r15 = 累计拷贝的字节数

    ; ---- 3. 读-写循环 ---------------------------------------------------
.read_loop:
    ; read(源fd, buf, buf_size)
    mov rax, SYS_read
    mov rdi, rbx                ; 源 fd
    mov rsi, r14                ; 缓冲区
    mov rdx, buf_size
    syscall                     ; ⚠ 这之后 rcx、r11 都不可信了

    test rax, rax
    js .read_err                ; 负数 = 出错
    jz .done                    ; 0 = EOF，收工

    ; rcx = 本轮读到的字节数。它只能活到下一次 syscall 之前，
    ; 而下面这个写循环全是 syscall……所以先把它转存到 r9，
    ; 用 r9（跨 syscall 安全）当「本轮总数」。
    mov r9, rax                 ; r9 = 本轮读到的字节数

    ; ---- 4. 把 r9 个字节全都写出去（处理「短写」）----------------------
    ; 分工如下（这两个都要跨 syscall 保持，所以不能用 rcx/r11）：
    ;   r9  = 本轮总共要写的字节数
    ;   r10 = 本轮已经写出去的字节数
    xor r10, r10
.write_loop:
    mov rax, SYS_write
    mov rdi, rbp                ; 目标 fd
    mov rsi, r14
    add rsi, r10                ; 从还没写完的位置开始
    mov rcx, r9
    sub rcx, r10                ; 还要写多少 = 总数 - 已写
    mov rdx, rcx
    syscall

    test rax, rax
    jle .write_err              ; 负数出错；0 表示写不动了
    add r10, rax                ; 累计本轮已写
    add r15, rax                ; 累计总字节
    cmp r10, r9
    jb .write_loop              ; 短写：继续把剩下的写完
    jmp .read_loop

.done:
    ; ---- 5. 关闭两个文件 ------------------------------------------------
    mov rax, SYS_close
    mov rdi, rbx
    syscall
    test rax, rax
    js .close_err

    mov rax, SYS_close
    mov rdi, rbp
    syscall
    test rax, rax
    js .close_err

    mov rax, r15                ; 返回拷贝的字节数
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

.read_err:
    lea rsi, [rel e_read]
    mov rdx, e_read_len
    call io_println
    mov rdi, 3
    call io_exit

.write_err:
    lea rsi, [rel e_write]
    mov rdx, e_write_len
    call io_println
    mov rdi, 4
    call io_exit

.close_err:
    lea rsi, [rel e_close]
    mov rdx, e_close_len
    call io_println
    mov rdi, 5
    call io_exit

; ---------------------------------------------------------------------------
; cstr_len —— 求 rsi 指向的 NUL 结尾字符串长度
;   返回：rax = 长度
; ---------------------------------------------------------------------------
cstr_len:
    xor eax, eax
.loop:
    cmp byte [rsi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; ---------------------------------------------------------------------------
; print_u64 —— 把 rdi 里的无符号数按十进制打印出来
; ---------------------------------------------------------------------------
print_u64:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32                 ; 栈上缓冲区（必须在 push 之后再开）

    mov rax, rdi
    mov rbx, 10
    lea r12, [rsp + 32]
.loop:
    xor rdx, rdx                ; div 前清零 rdx
    div rbx
    add dl, '0'
    dec r12
    mov [r12], dl
    test rax, rax
    jnz .loop

    mov rsi, r12
    lea rdx, [rsp + 32]
    sub rdx, r12
    call io_print

    add rsp, 32
    pop r12
    pop rbx
    leave
    ret

section .bss
    path_src resq 1             ; 保存源文件名指针（打印用）
    path_dst resq 1             ; 保存目标文件名指针（打印用）
```

### 逐段讲解

**1）程序启动时栈上长什么样**

```text
高地址
      ...
      argv[2]              ← [rsp + 24]
      argv[1]              ← [rsp + 16]
      argv[0]              ← [rsp + 8]（通常就是程序路径本身）
      argc                 ← [rsp]      ← 内核把 rsp 指在这里
低地址
```

所以取参数只要三行：

```asm
    mov r12, [rsp]              ; argc
    lea r13, [rsp + 8]          ; &argv[0]
    ...
    mov r12, [r13 + 8]          ; argv[1]
    mov r13, [r13 + 16]         ; argv[2]
```

**⚠ 最重要的纪律：取完 `argc`/`argv` 之前，一个字节都不能 `push`。** 只要先 `push` 一次，`[rsp]` 就不再是 `argc` 了，所有偏移全错。所以本程序的第一条实质性指令就是读 `[rsp]`。

**2）`argc` 可能是 1，`argv[1]` 根本不存在**

```asm
    cmp r12, 3
    jge .args_ok
    lea rsi, [rel u1]
    mov rdx, u1_len
    call io_println
    mov rdi, 1
    call io_exit
```

`./copy` 不带任何参数时 `argc` 就是 1。如果不检查就直接 `mov rsi, [r13+8]`，读到的是 `argv[1]` 那格的内存——那里是 `argv` 的结束标记 `NULL`（0），把 0 当字符串指针传给 `openat` 会得到 `EFAULT`，程序虽然不一定崩，但行为完全不可控。**先判断个数，再取参数。**

**3）`openat` 的参数：第 4 个是 `r10`**

```asm
    mov rax, SYS_openat         ; 257
    mov rdi, AT_FDCWD           ; -100：相对当前工作目录
    mov rsi, r12                ; 路径
    mov rdx, O_RDONLY           ; flags
    xor r10d, r10d              ; mode（不用 O_CREAT 时忽略）
    syscall
```

系统调用的参数顺序是 `rdi, rsi, rdx, r10, r8, r9`。**第 4 个是 `r10` 而不是 `rcx`**——`rcx` 是 C 函数调用的第 4 个参数，而 `syscall` 指令自己会用 `rcx` 保存「返回地址」，所以内核把第 4 个参数挪到了 `r10`。写成本课这个顺序才不会踩坑。

创建目标文件时 `mode` 才有意义：

```asm
    mov rdx, O_WRONLY | O_CREAT | O_TRUNC
    mov r10, 0o644              ; 权限（最终还要看 umask）
```

`O_TRUNC` 表示「文件已存在就清空」，这是 `cp` 的默认行为。`0644` 是最常见的文件权限，注意汇编里八进制要写 `0o644`（NASM 也支持 `0644q` 这种写法）。

**4）返回值判负**

```asm
    test rax, rax
    jns .src_ok                 ; 非负 = 合法的文件描述符
    ; 否则 rax 是 -errno，打印错误信息并退出
```

`test rax, rax` + `jns`（jump if not sign）是「判断是不是负数」的标准写法，比 `cmp rax, 0` + `jl` 更短。文件描述符从 3 开始分配（0/1/2 已经是标准输入输出），所以「负数就是错」这个判断非常干净。

**5）读-写循环的三个要点**

```asm
.read_loop:
    mov rax, SYS_read
    mov rdi, rbx                ; 源 fd
    mov rsi, r14                ; 缓冲区
    mov rdx, buf_size
    syscall

    test rax, rax
    js .read_err                ; ① 负数 = 出错
    jz .done                    ; ② 0 = EOF，正常结束
    mov r9, rax                 ; ③ 本轮读到了多少字节
```

* **读到 0 不等于出错。** 文件读完了就是返回 0，这是**唯一**的正常结束信号，必须单独处理。
* **读到的可能少于请求的长度。** 普通文件通常会读满，但管道、终端、socket 都可能短读。所以循环必须以「返回 0」为终止条件，而不是「读满 64 KiB」。
* **`read` 的返回值放在 `r9` 里跨 syscall 使用**。因为紧跟着的写循环里还有 `syscall`，而 `syscall` 会破坏 `rcx` 和 `r11`：

```asm
    xor r10, r10                ; r10 = 本轮已写的字节数
.write_loop:
    mov rax, SYS_write
    mov rdi, rbp                ; 目标 fd
    mov rsi, r14
    add rsi, r10                ; 从还没写完的位置开始
    mov rcx, r9
    sub rcx, r10                ; 还要写多少
    mov rdx, rcx
    syscall

    test rax, rax
    jle .write_err              ; 负数出错，0 表示写不动了
    add r10, rax
    add r15, rax                ; 累计总字节
    cmp r10, r9
    jb .write_loop              ; 短写：继续把剩下的写完
    jmp .read_loop
```

**短写**就是这个 `write_loop` 存在的理由：`write` 可能只写出去一部分（磁盘满、被信号打断、管道缓冲区满……），剩下的必须继续写。

**6）用退出码报告错误**

| 退出码 | 含义 |
|---|---|
| 0 | 成功 |
| 1 | 参数个数不对 |
| 2 | 打不开源文件 |
| 3 | 读取失败 |
| 4 | 写入失败 |
| 5 | 关闭失败 |
| 6 | 创建不了目标文件 |

退出码只有低 8 位有效，所以 `io_exit` 里传 0~255 的整数最稳妥。测试脚本和 shell 都能用 `$?` 直接判断，比去解析错误文字可靠得多。

### 运行与期望输出

```bash
printf 'Hello, file!\nsecond line\n' > /tmp/src.txt
./copy /tmp/src.txt /tmp/dst.txt
cmp /tmp/src.txt /tmp/dst.txt && echo 一致
```

```text
复制完成，共 25 字节  -> /tmp/dst.txt
一致
```

没有参数时：

```text
用法: ./copy 源文件 目标文件
```

（退出码 1）

源文件不存在时：

```text
copy: 打不开源文件: /tmp/没有这个文件
```

（退出码 2）

## 示例 2：wc.asm —— 统计字节 / 行 / 单词

### 完整源码

```asm
; ===========================================================================
; wc.asm —— 第 09 课示例 2：统计文件的字节数 / 行数 / 单词数
;
; 编译（在 lesson09 目录下）：
;   make
; 用法：
;   ./wc 文件名
;   ./wc            # 不写文件名就从标准输入读
; 例子：
;   printf 'hello world\nfoo bar\n' > /tmp/t.txt
;   ./wc /tmp/t.txt
;   printf 'a b\n' | ./wc
;
; 输出三列（和系统的 wc 默认顺序一致）：
;   行数  单词数  字节数  文件名
;
; 和 copy.asm 相比，这里多学三点：
;   1. 统计要「跨缓冲区边界」仍然正确 —— 一个单词可能正好被切成两半，
;      所以「当前是否在单词里」这个状态必须保留到下一轮（存在 rbp 里）；
;   2. 不带参数时从标准输入（fd 0）读，让程序更实用；
;   3. 右对齐输出：先算数字有几位，再补空格（print_padded）。
; ===========================================================================

%define AT_FDCWD -100

section .data
    dash        db "-"
    dash_len    equ $ - dash
    dash_nul    db 0            ; ⚠ cstr_len 需要 NUL 结尾，所以单独补一个 0
                                ;   （这样 dash_len 还是 1，不会被算进去）

    e_open      db "wc: 打不开文件: "
    e_open_len  equ $ - e_open

    e_read      db "wc: 读取出错"
    e_read_len  equ $ - e_read

    buf_size    equ 65536       ; 64 KiB（8 的倍数，保持栈对齐）

section .bss
    argv_base   resq 1          ; 保存 &argv[0]（程序一开始从栈上取下来的）
    buf         resb buf_size   ; 读取缓冲区
    nbytes      resq 1          ; 字节数
    nlines      resq 1          ; 行数
    nwords      resq 1          ; 单词数

section .text
    global _start
%include "io.inc"

_start:
    ; ---- 0. 取 argc / argv（必须在任何 push 之前）-----------------------
    mov r12, [rsp]              ; r12 = argc
    lea rax, [rsp + 8]
    mov [rel argv_base], rax    ; 把 &argv[0] 存到 .bss
                                ; （不用寄存器存它：r12-r15 下面都有正经用途）

    mov rbx, STDIN              ; rbx = 要读的文件描述符，默认标准输入
    lea r14, [rel dash]         ; r14 = 显示用的文件名，默认 "-"（NUL 结尾）
                                ;       （很多工具的惯例：stdin 显示成 -）

    cmp r12, 2                  ; 有给文件名吗？
    jl .count                   ; argc < 2：从标准输入读

    mov rax, [rel argv_base]
    mov r14, [rax + 8]          ; r14 = argv[1]，也就是文件名

    ; openat(AT_FDCWD, 文件名, O_RDONLY)
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rsi, r14                ; 路径
    mov rdx, O_RDONLY
    xor r10d, r10d
    syscall

    test rax, rax
    jns .opened
    ; 打开失败：打印错误并退出（退出码 2）
    lea rsi, [rel e_open]
    mov rdx, e_open_len
    call io_print
    mov rsi, r14
    call cstr_len
    mov rdx, rax
    call io_println
    mov rdi, 2
    call io_exit

.opened:
    mov rbx, rax                ; rbx = 真正的文件描述符

.count:
    ; ---- 1. 初始化计数器 ------------------------------------------------
    mov qword [rel nbytes], 0
    mov qword [rel nlines], 0
    mov qword [rel nwords], 0
    xor ebp, ebp                ; rbp = 「当前是否在单词里」：0 不在 / 1 在

    ; ---- 2. 读-统计循环 -------------------------------------------------
.read_loop:
    mov rax, SYS_read
    mov rdi, rbx                ; 读哪个 fd
    lea rsi, [rel buf]          ; 缓冲区
    mov rdx, buf_size
    syscall                     ; ⚠ 这之后 rcx、r11 不可信

    test rax, rax
    js .read_err                ; 负数 = 出错
    jz .report                  ; 0 = EOF，统计完了

    add [rel nbytes], rax       ; 字节数直接累加

    mov r15, rax                ; r15 = 本轮读到的字节数（跨下面的调用保持）
    xor ecx, ecx                ; rcx = 本轮已处理的下标
                                ;     本轮里没有 syscall，所以用它没问题

.byte_loop:
    lea rsi, [rel buf]
    movzx eax, byte [rsi + rcx] ; 取第 rcx 个字节

    ; ---- 2.1 行数：数 '\n' 的个数 ---------------------------------------
    cmp al, LF
    jne .word_part
    inc qword [rel nlines]

    ; ---- 2.2 单词边界：分隔符 -> 非分隔符 才算一个新单词 ----------------
.word_part:
    xor r8d, r8d                ; r8 = 0：先假设不是分隔符
    cmp al, ' '
    je .is_sep
    cmp al, TAB
    je .is_sep
    cmp al, LF
    je .is_sep
    cmp al, 13                  ; '\r'
    je .is_sep
    cmp al, 12                  ; '\f'
    je .is_sep
    cmp al, 11                  ; '\v'
    je .is_sep
    jmp .sep_done
.is_sep:
    mov r8d, 1
.sep_done:

    test r8d, r8d
    jz .not_sep
    xor ebp, ebp                ; 是分隔符：离开单词状态
    jmp .next_byte

.not_sep:
    test rbp, rbp
    jnz .next_byte              ; 本来就在单词里，不重复计数
    inc qword [rel nwords]      ; 从「不在单词里」变成「在单词里」
    mov ebp, 1

.next_byte:
    inc rcx
    cmp rcx, r15
    jb .byte_loop               ; 本轮还没处理完
    jmp .read_loop              ; 继续读下一块

.report:
    ; ---- 3. 打开过文件就先关掉 ------------------------------------------
    cmp rbx, STDIN
    je .print
    mov rax, SYS_close
    mov rdi, rbx
    syscall                     ; 关闭失败也没关系，统计结果已经拿到了

.print:
    ; ---- 4. 三列输出，每列右对齐 7 位，最后跟文件名 ---------------------
    ; 列的顺序和系统 wc 一样：行、词、字节
    ;
    ; ⚠ 调用约定小提醒：rdi 放数值、rsi 放列宽，两个都要设对。
    ;   如果中间插了 lea rsi, [...] 之类的指令，就会把列宽冲掉。
    mov rdi, [rel nlines]
    mov rsi, 7
    call print_padded

    mov rdi, [rel nwords]
    mov rsi, 7
    call print_padded

    mov rdi, [rel nbytes]
    mov rsi, 7
    call print_padded

    mov edi, ' '
    call io_putchar
    mov rsi, r14                ; 文件名（或者 "-"）
    call cstr_len
    mov rdx, rax
    call io_println

    xor rdi, rdi
    call io_exit

.read_err:
    lea rsi, [rel e_read]
    mov rdx, e_read_len
    call io_println
    mov rdi, 3
    call io_exit

; ---------------------------------------------------------------------------
; print_padded —— 把 rdi 里的无符号数以「右对齐 rsi 列」的方式打印
;
;   入参：rdi = 数值，rsi = 列宽
;   例子：print_padded(42, 7) 会输出 "     42"（5 个空格 + 两位数字）
;   做法：先算数字有几位，再补「列宽 - 位数」个空格。
; ---------------------------------------------------------------------------
print_padded:
    push rbx                    ; 本函数要用 rbx/r12/r13，先保存
    push r12
    push r13

    mov r12, rdi                ; r12 = 要打印的数值
    mov r13, rsi                ; r13 = 列宽

    ; ---- 1. 数一数这个数有几位（0 也算 1 位）----------------------------
    ; 这段没有 syscall，用 rcx 当除数完全安全
    mov rbx, 1                  ; rbx = 位数
    mov rax, r12
.digit_count:
    cmp rax, 10
    jb .counted
    xor rdx, rdx
    mov rcx, 10
    div rcx                     ; rax /= 10
    inc rbx
    jmp .digit_count

.counted:
    mov rax, r13
    sub rax, rbx                ; rax = 需要补的空格数 = 列宽 - 位数
    mov rbx, rax                ; ⚠ 计数器放 rbx（被调用者保存）
                                ;   io_putchar 内部有 syscall，而内核会破坏 rcx；
                                ;   拿 rcx 计数会变成天文数字，最后把栈都冲掉
    test rbx, rbx
    jle .print_num              ; 不需要补空格就直接打印
.pad:
    mov edi, ' '
    call io_putchar
    dec rbx
    jnz .pad

.print_num:
    mov rdi, r12
    call print_u64

    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; cstr_len —— 求 rsi 指向的 NUL 结尾字符串长度
;   返回：rax = 长度
; ---------------------------------------------------------------------------
cstr_len:
    xor eax, eax
.loop:
    cmp byte [rsi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; ---------------------------------------------------------------------------
; print_u64 —— 无符号十进制输出（栈上开缓冲区，从末尾往前填）
;   入参：rdi = 数值
; ---------------------------------------------------------------------------
print_u64:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32                 ; 缓冲区必须在 push 之后再开

    mov rax, rdi
    mov rbx, 10
    lea r12, [rsp + 32]
.loop:
    xor rdx, rdx                ; div 前清零 rdx
    div rbx
    add dl, '0'
    dec r12
    mov [r12], dl
    test rax, rax
    jnz .loop

    mov rsi, r12
    lea rdx, [rsp + 32]
    sub rdx, r12
    call io_print

    add rsp, 32
    pop r12
    pop rbx
    leave
    ret
```

### 逐段讲解

**1）输出顺序对齐系统 `wc`**

系统 `wc` 默认输出「行数 单词数 字节数 文件名」，本课照抄这个顺序：

```text
      2      4     20 /tmp/t.txt
      0      0      0 /tmp/empty.txt
```

每列右对齐 7 位，这样多行输出能对齐、方便人眼比较。右对齐的做法是先算数字有几位，再补空格（`print_padded`）。

**2）统计三件事**

```asm
    add [rel nbytes], rax       ; ① 字节数：直接把每次读到的长度累加
```

```asm
    cmp al, LF
    jne .word_part
    inc qword [rel nlines]      ; ② 行数：数 '\n' 的个数
```

注意「行数 = `\n` 的个数」意味着**最后一行没有换行符时不计入行数**。`printf 'abc' > f; wc -l f` 得到 0，本程序也是 0。

单词数的判定是本课最需要动脑的地方：

```text
    字节序列:   a  ' '  b  '\t'  c  '\n'
    在单词里?: 0→1  1→0  0→1  1→0  0→1  1→0
    单词计数:    +1        +1         +1        = 3 个单词
```

规则就是「**当前字节不是分隔符，而前一个字节是分隔符（或还没开始）** 时，词数加一」。用一个状态位 `rbp` 记录「刚刚是否在单词里」：

```asm
.not_sep:
    test rbp, rbp
    jnz .next_byte              ; 本来就在单词里，不重复计数
    inc qword [rel nwords]
    mov ebp, 1                  ; 记住：现在在单词里了
```

什么算分隔符？本课按系统 `wc` 的默认规则取 **空格、`\t`、`\n`、`\r`、`\f`、`\v`** 六个：

```asm
    cmp al, ' '
    je .is_sep
    cmp al, TAB
    je .is_sep
    cmp al, LF
    je .is_sep
    cmp al, 13                  ; '\r'
    je .is_sep
    cmp al, 12                  ; '\f'
    je .is_sep
    cmp al, 11                  ; '\v'
    je .is_sep
```

**3）状态必须跨缓冲区保存，这是本课的核心难点**

因为一次只读 64 KiB，一个单词完全可能被切成两半。假设前一块以 `wor` 结束、后一块以 `d ` 开头，如果每读一块就把状态清零，单词数就会多算一个。所以：

* `rbp`（是否在单词里）在整个循环里**不清零**，只在 `\n`/分隔符处修改；
* 每轮统计完，`rbp` 自然带着上一轮的状态进入下一轮。

`test_wc` 里那个 900 KiB 的大文件（`big.txt`）就是专门验证这一点的：它有 30000 行、每行 6 个词，跨了十几个缓冲区，结果必须是 `30000 180000 918890`。

**4）不带参数就从标准输入读**

```asm
    mov rbx, STDIN              ; 默认读标准输入
    lea r14, [rel dash]         ; 文件名显示为 "-"（工具们的惯例）
    cmp r12, 2
    jl .count                   ; argc < 2：不打开文件，直接开始统计
```

这样 `printf 'a b\n' | ./wc` 就能用，和系统 `wc` 的行为一致。`fd = 0` 不需要 `openat`，所以这一支跳过打开步骤；`fd = 3` 以上时才需要 `close`，代码里用 `cmp rbx, STDIN` 区分。

**5）`print_padded`：右对齐输出**

```asm
    mov rbx, 1                  ; rbx = 位数
    mov rax, r12
.digit_count:
    cmp rax, 10
    jb .counted
    xor rdx, rdx
    mov rcx, 10
    div rcx
    inc rbx
    jmp .digit_count
.counted:
    mov rax, r13
    sub rax, rbx                ; 要补的空格数 = 列宽 - 位数
    mov rbx, rax
```

数位数用到 `div`，所以 `rdx` 必须清零。补空格时**计数器放在 `rbx`**：

```asm
.pad:
    mov edi, ' '
    call io_putchar
    dec rbx
    jnz .pad
```

为什么不能用 `rcx` 当计数器？因为 `io_putchar` 内部要执行 `syscall`，而**内核一定会破坏 `rcx` 和 `r11`**（用它们保存返回地址和标志位）。用 `rcx` 计数会得到一个天文数字，循环停不下来，一路 `push` 把栈冲掉——这正是本课调试时真实踩过的坑，写进「常见坑」里了。

### 运行与期望输出

```bash
printf 'hello world\nfoo bar\n' > /tmp/t.txt
./wc /tmp/t.txt
wc  /tmp/t.txt      # 可以对照系统自带 wc
```

```text
      2      4     20 /tmp/t.txt
```

从标准输入读：

```bash
printf 'a b\n' | ./wc
```

```text
      1      2      4 -
```

## 编译与运行

```bash
cd lesson09
make
./copy /etc/hostname /tmp/hostname.copy
./wc /tmp/hostname.copy
make test
```

## 动手练习

1. 给 `copy` 加一个「第 3 个参数」：如果存在就当作要拷贝的字节数上限（提示：把 `buf_size` 换成一个变量，并在循环里判断已拷贝字节数）。
2. 给 `copy` 加 `-a` 选项：检测到第 2 个参数是 `-a` 时，源文件是 `argv[2]`、目标是 `argv[3]`（提示：先用 `str_eq` 比较字符串）。
3. 修改 `wc`，让它支持多个文件参数：对每个文件输出一行，最后再输出一行 `total`（提示：用一个外层循环遍历 `argv`，把三个计数器清零）。
4. 给 `wc` 加一个 `-c` 选项：只输出字节数。注意这要求先判断 `argv[1]` 是不是 `-c`，是的话真正的文件名在 `argv[2]`。
5. 写一个 `cat`：把 `argv[1]` 的内容原样写到标准输出（比 `copy` 简单，因为不需要打开第二个文件；提示：`fd = STDOUT`）。如果 `argc < 2` 就从标准输入读到输出（这样 `./cat < f` 和 `./cat f` 行为一致）。
6. 写一个 `tail5`：打印文件的最后一行（提示：读取时只保留「最后一次遇到的 `\n` 之后的内容」；或者用 `lseek` 从文件末尾往前读，但那需要处理「文件不足 5 行」的情况）。
7. 思考题：`copy` 在「源文件和目标文件是同一个文件」时会怎样？先想清楚，再实际试一次（提示：`O_TRUNC` 会立刻把文件清空，然后 `read` 读到的是 0 字节）。
8. 思考题：如果 `write` 的目标是管道（`|`），而且管道缓冲区满了，`write` 会返回什么？为什么必须有 `write_loop`？

## 常见坑

* **在取 `argc`/`argv` 之前 `push` 了东西。** 这是本课的头号杀手。`[rsp]` 在入口时是 `argc`，只要先 `push rax`，`argc` 就跑到 `[rsp+8]` 去了。要么第一件事就读栈，要么先 `pop` 到寄存器里保存。
* **系统调用第 4 个参数是 `r10`，不是 `rcx`。** `syscall` 指令用 `rcx` 保存返回地址，所以内核规定第 4 个参数放 `r10`。写错的话 `openat` 会拿 `rcx` 当 mode、拿 `r10` 当 mode，行为错乱。
* **不检查系统调用的返回值。** 出错时 `rax` 是负数（`-errno`），不是有效的 fd。不检查就会把 `-2` 当成文件描述符传给 `read`，`read` 再返回 `-EBADF`，错误一路往后传，最后在莫名其妙的地方崩掉。
* **`argc < 2` 时直接读 `argv[1]`。** 那一格是 `NULL`，把它当路径用会得到 `EFAULT`。一定要先 `cmp argc, 2`。
* **忘了 `close`。** 短命的小工具不关文件就退出，内核会替你收尾；但如果是在循环里打开成千上万个文件（比如遍历目录），不关就会耗尽文件描述符（`EMFILE`）。
* **把「读满缓冲区」当成循环结束条件。** 结束条件只能是 `read` 返回 0。短读是合法且常见的。
* **只调用一次 `write` 就以为写完了。** `write` 可能短写，必须循环到「都已写出」。
* **用 `rcx`/`r11` 跨 `syscall` 保存数据。** 这两个寄存器每次 `syscall` 都会被内核改掉。本课里 `r9`（本轮总字节数）和 `r10`（本轮已写）就是专门为此选的「调用者保存但 syscall 不动」的寄存器。
* **缓冲区定义成 `.data` 里的未初始化数组。** `.data` 是「有初值且要写进可执行文件」的段，`buf times 65536 db 0` 会让可执行文件白白多 64 KiB。用 `section .bss` + `resb`。
* **`read`/`write` 的长度参数只写了低 8 位。** `mov dl, 64` 不会清零 `rdx` 的高 56 位，长度会变成天文数字。写 `mov edx, 64` 或 `mov rdx, 64`。
* **`io_exit` 的退出码超出 0~255。** 只有低 8 位有效，`exit(256)` 在 shell 里看到的是 0。
* **`test.sh` 里对 wc 输出别去比较具体空格数。** 不同平台、不同 `WC` 环境变量的格式略有差异，测试脚本应该先把连续空白压成一个空格再比较。

# 第 15 课：综合项目：命令行工具 + 结课回顾

## 一、本课目标

* 把前面 14 课的知识拼成**两个真正能用的命令行工具**：`hexdump2` 和 `wordcount`。
* 掌握入口栈上的 `argc` / `argv` 布局，并用 `openat(2)` 打开命令行给出的文件。
* 学会在汇编里处理**文件描述符**、**多文件**、**错误路径与退出码**。
* 学会“两遍扫描”这种工程做法：先统计、再决定列宽、最后打印（`wc` 就是这么干的）。
* 回顾 15 课的知识地图，知道接下来该往哪走。

本课文件：

| 文件 | 风格 | 说明 |
|---|---|---|
| `hexdump2.asm` | 纯 syscall（`_start` + `ld`） | `hexdump -C` 增强版：支持文件名参数，多个文件当成一条连续字节流 |
| `wordcount.asm` | 纯 syscall | 统计行数/单词数/字节数，输出格式与 GNU `wc -l -w -c` 一致 |
| `test.sh` | — | 造测试文件、喂输入、比对输出（含与真 `wc`/`hexdump` 的交叉验证） |

## 二、新概念 / 新指令

| 概念 / 指令 | 一句话说明 | 小例子 |
|---|---|---|
| 入口栈布局 | `[rsp]`=argc，`[rsp+8]`=argv[0]，`[rsp+16]`=argv[1]… | `mov rbx, [rsp]`、`lea r12, [rsp+8]` |
| `argv` 越界检查 | 参数是 `argv[1] … argv[argc-1]` | `cmp r13, rbx; jae .done` |
| `openat(2)` | 打开文件（`rax=257`），相对目录用 `AT_FDCWD = -100` | `rdi=AT_FDCWD, rsi=路径, rdx=O_RDONLY` |
| `close(2)` | 关文件描述符（`rax=3`），用完就关是好习惯 | `mov rdi, r14; syscall` |
| `fstat(2)` | 取文件信息（`rax=5`），`st_mode` 在 `struct stat` 偏移 24 | `mov eax, [statbuf+24]` |
| `S_IFREG` / `S_ISREG` | 判断是不是普通文件：`(st_mode & 0xF000) == 0x8000` | `and eax, 0xF000; cmp eax, 0x8000` |
| 标准错误 | 错误信息写 fd 2（`STDERR`），不要混进 stdout | `mov rdi, STDERR; call io_write` |
| 退出码 | 约定 `0` 成功、非 0 失败；错误信息给 stderr，退出码给调用者 | `mov rdi, 1; call io_exit` |
| 多文件 = 连续流 | `hexdump -C a b` 等价于 `cat a b \| hexdump -C`（偏移不重置） | 半行缓冲要跨文件保留 |
| 两遍扫描 | 先统计出所有数字，再决定统一列宽，最后打印 | `num_width` + `widen` |
| `div` + `and` 取位数/余数 | 数位数：反复 `div 10`；`and rcx, 15` 取低 4 位 | 见 `num_width` |

## 三、示例一：`hexdump2.asm`

```text
用法：
  ./hexdump2                 # 读标准输入
  ./hexdump2 FILE...         # 依次读这些文件
  ./hexdump2 - FILE          # "-" 表示标准输入
退出码：0 正常；有文件打不开时打印错误并继续，最后退出码 1
```

输出格式和第 14 课的 `hexdump` 完全相同（就是同一套 `emit_line`），多出来的是**参数解析**和**文件读取**。

```text
$ ./hexdump2 t1.txt
00000000  68 65 6c 6c 6f 20 77 6f  72 6c 64 0a 66 6f 6f 20  |hello world.foo |
00000010  62 61 72 20 62 61 7a 0a                           |bar baz.|
00000018
```

### 3.1 解析 `argc` / `argv` + 打开文件

```asm
_start:
    mov rbx, [rsp]              ; argc（rbx 会被 dump/emit_* 保存）
    lea r12, [rsp + 8]          ; &argv[0]
    mov qword [rel total], 0
    mov qword [rel have], 0     ; 半行缓冲跨文件保留（多文件 = 一条连续字节流）
    mov qword [rel err_flag], 0

    cmp rbx, 2
    jae .files                  ; 至少有一个参数 → 按文件处理

    ; ---- 没有参数：读标准输入 --------------------------------------------
    mov rdi, STDIN
    call dump
    jmp .finish

.files:
    mov r13, 1                  ; 从 argv[1] 开始
.next_arg:
    cmp r13, rbx
    jae .finish
    mov rsi, [r12 + r13*8]      ; argv[i]
    cmp byte [rsi], '-'         ; 参数正好是 "-"？
    jne .open
    cmp byte [rsi + 1], 0
    jne .open
    mov rdi, STDIN
    call dump
    jmp .next_file

.open:
    mov rax, SYS_openat
    mov rdi, AT_FDCWD
    mov rdx, O_RDONLY
    xor r10d, r10d              ; 只有 O_CREAT 才需要 mode
    syscall
    test rax, rax
    js .open_error
    mov r14, rax                ; fd（dump 会保存并恢复 r14）
    mov rdi, r14
    call dump
    mov rax, SYS_close
    mov rdi, r14
    syscall
    jmp .next_file

.open_error:
    mov qword [rel err_flag], 1
    mov rsi, [r12 + r13*8]
    call report_error

.next_file:
    inc r13
    jmp .next_arg
```

要点：

* **一进 `_start` 就取 `argc`/`argv`**，在 `push` 任何东西之前。栈上就是内核摆好的：`[rsp]` 是参数个数，后面是指针数组，最后一个是 `NULL`。
* `argv` 里的字符串只保证**以 `\0` 结尾**，长度要自己数（`report_error` 里的 `str_len` 就是这个用途）。
* **`openat` 而不是 `open`**：`SYS_open = 2` 在老内核上也能用，但新代码推荐 `openat`（`rax = 257`），第一个参数是目录 fd，`AT_FDCWD = -100` 表示“当前工作目录”。`O_RDONLY` 是 `0`，所以 `mov rdx, O_RDONLY` 看着像没设置，其实是对的。
* **`syscall` 的返回值是负数表示 `-errno`**：`test rax, rax; js .open_error` 一句就把错误路径分出来了。
* **错误不要 `exit` 掉**：`hexdump`/`wc` 这类工具的规矩是“报告错误、继续处理后面的文件、最后用非 0 退出码”；把失败记在 `err_flag` 里，统一在程序末尾返回。
* **`rbx`/`r12`/`r13`/`r14` 是被调用者保存寄存器**，`dump`/`emit_line` 内部 `push`/`pop` 了它们，所以循环里的 `argc`、`argv`、下标、fd 跨函数调用都活着。

### 3.2 `dump`：把一个 fd 接到“当前行”后面

```asm
dump:
    push r14
    mov r14, rdi                ; fd
.fill:
    mov rax, SYS_read
    mov rdi, r14
    lea rsi, [rel inbuf]
    add rsi, [rel have]         ; 接着写（可能是上一个文件剩下的半行）
    mov rdx, 16
    sub rdx, [rel have]         ; 还差多少
    syscall
    test rax, rax
    jle .ret                    ; EOF 或出错：这个 fd 结束
    add [rel have], rax
    cmp qword [rel have], 16
    jb .fill
    call emit_line              ; 攒满一行
    add qword [rel total], 16
    mov qword [rel have], 0
    jmp .fill
.ret:
    pop r14
    ret
```

和第 14 课相比，关键差别只有一处：**这个 fd 读完后不打印剩下的半行**，而是直接返回，把 `have` 里的字节留给下一个文件继续填。这样 `./hexdump2 a.txt b.bin` 的输出就和 `cat a.txt b.bin | hexdump -C`、以及真正的 `hexdump -C a.txt b.bin` 完全一样（我们已在 Debian 上逐字节验证过）。全部输入读完后，`_start` 的 `.finish` 才把最后那半行和总偏移行打出来。

### 3.3 报错信息写到 stderr

```asm
report_error:
    push rbx
    mov rbx, rsi
    lea rsi, [rel msg_prefix]
    mov rdx, msg_prefix_len
    mov rdi, STDERR
    call io_write
    mov rdi, rbx
    call str_len                ; argv 里的字符串只保证以 NUL 结尾，长度要自己数
    mov rdx, rax
    mov rsi, rbx
    mov rdi, STDERR
    call io_write
    lea rsi, [rel msg_err]
    mov rdx, msg_err_len
    mov rdi, STDERR
    call io_write
    pop rbx
    ret
```

`$ ./hexdump2 nope.bin` → stdout 什么都没有，stderr 是 `hexdump2: nope.bin: cannot open`，退出码 1。
把错误信息写进 stdout 是命令行工具的大忌：那会污染管道下游的数据。

## 四、示例二：`wordcount.asm`

```text
用法：
  ./wordcount FILE...        # 多于一个文件时，最后打印 total 行
  ./wordcount                # 没有参数就读标准输入（不打文件名）
  ./wordcount - FILE         # "-" 表示标准输入
```

输出格式和 GNU `wc -l -w -c` 一致：

```text
$ printf 'hello world\nfoo bar baz\n' > t1.txt
$ printf 'one\ttwo three\n'          > t2.txt
$ printf 'x y z\n'                   > t3.txt
$ ./wordcount t1.txt t2.txt t3.txt
 2  5 24 t1.txt
 1  3 14 t2.txt
 1  3  6 t3.txt
 4 11 44 total
```

### 4.1 核心统计函数 `count_fd`

```asm
count_fd:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; fd
    mov qword [rel cur_lines], 0
    mov qword [rel cur_words], 0
    mov qword [rel cur_bytes], 0
    xor r15d, r15d              ; 0 = 当前不在单词里（跨 read 保留）

    ; ---- 用 fstat(2) 看是不是普通文件（决定列宽是否要用最小 7）-----------
    mov rax, SYS_fstat
    mov rdi, r12
    lea rsi, [rel statbuf]
    syscall
    test rax, rax
    js .stat_done               ; 失败就当成普通文件，不设标记
    mov eax, dword [rel statbuf + 24]   ; st_mode 在 struct stat 的偏移 24
    and eax, 0xF000             ; 取文件类型位
    cmp eax, 0x8000             ; S_IFREG = 普通文件
    je .stat_done
    mov qword [rel nonreg], 1
.stat_done:

.read:
    mov rax, SYS_read
    mov rdi, r12
    lea rsi, [rel buf]
    mov rdx, BUFSZ
    syscall
    test rax, rax
    jle .done                   ; 0 = EOF；负数 = 读错误，都结束
    add [rel cur_bytes], rax
    lea rbx, [rel buf]
    mov r13, rax                ; 本次读到的字节数
    xor r14d, r14d              ; 缓冲区下标
.scan:
    movzx eax, byte [rbx + r14]
    cmp al, LF
    jne .not_newline
    inc qword [rel cur_lines]
.not_newline:
    ; ---- 是不是空白字符？------------------------------------------------
    cmp al, SPACE
    je .is_space
    cmp al, TAB
    je .is_space
    cmp al, LF
    je .is_space
    cmp al, 0x0b                ; \v
    je .is_space
    cmp al, 0x0c                ; \f
    je .is_space
    cmp al, 0x0d                ; \r
    je .is_space
    ; ---- 非空白：如果刚才不在单词里，就是一个新单词的开头 ----------------
    test r15, r15
    jnz .next
    inc qword [rel cur_words]
    mov r15d, 1
    jmp .next
.is_space:
    xor r15d, r15d
.next:
    inc r14
    cmp r14, r13
    jb .scan
    jmp .read
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
```

三个容易写错的点：

1. **`in_word` 状态必须跨 `read` 调用保留**（存在 `r15` 里）。如果缓冲区正好断在一个单词中间，下一次 `read` 的第一个字节是非空白——没有这个状态就会把它当成“新单词”，单词数多算一个。`big1.txt` 那种 64 KiB 全是 `'a'`（没有空白）的输入最容易暴露它。
2. **行数是数 `'\n'` 的个数**，不是数“文本行”。文件最后一行没有换行符时，`wc` 也不计它——这一点很多人误会。
3. **空白集合是 `space \t \n \v \f \r`**（等同 C 的 `isspace`）。

`fstat` 那一段是为对齐 `wc` 的一个怪癖：**只要输入里有非普通文件（管道、`/dev/null`、`-`），`wc` 的数字列宽最小就是 7**；而重定向一个普通文件时按文件大小算位数。所以 `printf 'a b\nc\n' | ./wordcount` 输出的是

```text
      2       3       6
```

而 `./wordcount < t1.txt`（标准输入是普通文件）输出的是

```text
 2  5 24
```

### 4.2 两遍扫描：先算列宽，再打印

`wc` 的输出是右对齐的，而且所有数字共用**同一个宽度**（`1 2 4` 会变成 `   1    2    4`，由最长的数字决定）。所以我们不能边数边打印，得先把所有数字拿到手：

```asm
.width_calc:
    mov qword [rel width], 1
    xor r12d, r12d              ; 这里起 r12（原 argv）不再需要
.wloop:
    cmp r12, [rel nfiles]
    jae .w_totals
    lea rax, [rel lines_arr]
    mov rdi, [rax + r12*8]
    call num_width
    call widen
    lea rax, [rel words_arr]
    mov rdi, [rax + r12*8]
    call num_width
    call widen
    lea rax, [rel bytes_arr]
    mov rdi, [rax + r12*8]
    call num_width
    call widen
    inc r12
    jmp .wloop
.w_totals:
    mov rdi, [rel tlines]
    call num_width
    call widen
    mov rdi, [rel twords]
    call num_width
    call widen
    mov rdi, [rel tbytes]
    call num_width
    call widen
    ; ---- GNU wc 的怪癖：有非普通文件输入时列宽至少 7 ----------------------
    cmp qword [rel nonreg], 0
    je .print_lines
    cmp qword [rel width], 7
    jae .print_lines
    mov qword [rel width], 7
```

* `num_width(rdi=值) → rax=十进制位数`：反复 `div 10` 直到商为 0；
* `widen`：`if (rax > width) width = rax;`；
* 每个文件的三个数字、以及 total 行的三个数字，全部参与宽度计算——所以 `total` 行看起来和别的行完全对齐。

打印部分用 `append_num`（把数字按列宽右对齐追加到行缓冲 `linebuf`），再补一个空格和文件名，最后**一次 `write`** 输出整行——和 `hexdump` 一样，避免“每个数字一次系统调用”。

### 4.3 错误处理

```asm
.open_error:
    mov qword [rel err_flag], 1
    mov rsi, [r12 + r13*8]
    call report_error
```

```text
$ ./wordcount t1.txt nope.txt t2.txt
wordcount: nope.txt: cannot open        ← 这一行走 stderr
 2  5 24 t1.txt
 1  3 14 t2.txt
 3  8 38 total
$ echo $?
1
```

打不开的文件被跳过（不计入 total，所以这次 total 只统计 2 个成功文件），错误写到 stderr——重定向 stdout 时它不会混进数据里；程序继续处理后面的文件，最后退出码为 1。

## 五、编译与运行

```bash
make                    # nasm + ld，生成 hexdump2 和 wordcount
./wordcount t1.txt
printf 'a b\nc\n' | ./wordcount
./hexdump2 t1.txt
./hexdump2 < /dev/null
make test               # 跑 test.sh
```

`test.sh` 会现场造三个测试文件、比对输出，并且：

* 有 `wc` 时用 `LC_ALL=C wc -l -w -c t1.txt t2.txt t3.txt` 交叉验证；
* 有 `hexdump` 时用 `hexdump -C t1.txt t2.txt t3.txt` 交叉验证多文件连续流。

**已知差异（故意保留，README 说明）**：对随机二进制文件统计单词数时，GNU `wc` 在 UTF-8 locale 下会按多字节字符解码（`LC_ALL=C` 时又是另一套结果），而本程序只按“ASCII 空白分隔”统计——对纯文本两者结果完全一致。`hexdump2` 则和 `hexdump -C` 逐字节一致。

## 六、结课回顾：15 课知识地图

| 课 | 主题 | 学完你应该会 |
|---|---|---|
| 01 | 环境、hello、汇编→链接→运行全流程 | 写、编译、链接、运行一个 NASM 程序；知道 `_start` 和退出系统调用 |
| 02 | 寄存器、内存、段、objdump/gdb 初探 | 认识 64 位通用寄存器、`mov` 寻址方式、`.data`/`.bss`/栈的区别 |
| 03 | 数据定义、`db/dw/dd/dq`、字符串与长度 | 在数据段放字符串/数组，用 `equ $ - 标签` 算长度 |
| 04 | 算术与逻辑指令、标志位 | 理解 `add/sub/and/or/xor/shl` 与 ZF/CF/SF/OF |
| 05 | 跳转、条件转移、`cmp`/`test` | 用有符号（`jl/jg`）和无符号（`jb/ja`）条件转移写分支 |
| 06 | 循环、数组遍历、`loop`/`jnz` | 用 `inc/cmp/jb` 写循环、遍历数组、累加 |
| 07 | 函数、栈、`call/ret`、调用约定 | 用栈传参、`push rbp/mov rbp, rsp` 建立栈帧、保护被调用者保存寄存器 |
| 08 | 字符串与数字互转、进制打印 | 手写 `itoa`/`atoi`、十进制/十六进制输出 |
| 09 | 文件读写、更全的系统调用 | `openat/read/write/close/lseek`，用命令行参数处理文件 |
| 10 | 浮点 SSE2（printf 输出，libc） | `movsd/addsd/mulsd/divsd`，用 `lc_` 风格链接 libc 打印浮点 |
| 11 | SIMD/sse/avx 入门 | `movdqu/paddq/pcmpeqb/psadbw`，向量加法与字符统计 |
| 12 | 宏、重复、条件汇编、内联汇编 | `%define/%macro/%rep/%ifdef`，C 里写 `__asm__` |
| 13 | 与 C 互调、编译混合、性能优化 | 汇编库 + C 混合编译、弱符号、SIMD 优化与实测 |
| 14 | 调试（gdb、objdump）与常见陷阱 | 断点/单步/查内存定位 bug；认出宽度和边界错误 |
| 15 | 综合项目：命令行工具 + 结课回顾 | 参数解析、文件处理、错误与退出码、对齐格式化输出 |

一句话总结这 15 课：**汇编不难在指令多，难在“每一条指令都必须自己负责”**——宽度、边界、栈、寄存器、对齐，编译器平时替你操心的东西，现在都归你了。也正因为如此，你反过来能看懂编译器生成的代码、能读懂崩溃现场、能写出 C 写不出来的临界区。

## 七、后续学习方向

1. **把系统调用/ABI 学全**：`man 2 syscalls`、`mmap`、`fork/execve/wait4`、信号（`rt_sigaction`）、线程（`clone`）、`epoll`。用汇编写一个 `cat`、`grep`、`ls` 是最好的练习。
2. **性能工程**：`perf stat` / `perf record` 看 IPC、cache miss、分支预测失败；再读 Agner Fog 的优化手册，理解为什么“少分支”常常比“少指令”更重要。
3. **更宽的 SIMD**：AVX2（`vpaddq ymm`）、AVX-512、`vpshufb`、`pclmulqdq`；用 `objdump`/`uops.info` 对照自己的实现。
4. **链接与加载**：ELF 格式、动态链接、PLT/GOT、重定位——`readelf`/`objdump` 是主要工具；搞懂“为什么 `-no-pie` 和 PIE 的汇编写法不同”。
5. **C 与汇编的现代配合方式**：编译器内联汇编（`__asm__`）、内建函数（`__builtin_*`）、intrinsics（`<immintrin.h>`）、以及“先写 C，再让编译器出汇编，最后只手工优化热点”。
6. **逆向与调试**：`gdb` + `objdump` + Ghidra/radare2；读别人的汇编是提升最快的路径之一。
7. **换一个架构**：ARM64（AArch64）的 ABI 和指令集完全不同（参数在 `x0-x7`、链接寄存器 `lr`、固定 4 字节指令），迁移过去会重新认识很多“x86 的偶然性”。

## 八、参考资源

* **Intel SDM**（Intel 64 and IA-32 Architectures Software Developer's Manual）：指令集最权威的资料，卷 2 是指令参考（可以配合 [felixcloutier 在线指令查询](https://www.felixcloutier.com/x86/) 使用）。官方入口：[Intel SDM](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)
* **AMD APM**（AMD64 Architecture Programmer's Manual）：AMD 视角的 64 位手册，讲 System V 之外的历史和细节很好用。入口：[AMD Tech Docs](https://www.amd.com/en/support/tech-docs)
* **NASM 手册**：`%macro`、`%if`、寻址语法、ELF 输出格式的官方说明：<https://www.nasm.us/doc/>
* **Linux 系统调用表**：`man 2 syscalls`（<https://man7.org/linux/man-pages/man2/syscalls.2.html>）；本机头文件 `/usr/include/x86_64-linux-gnu/asm/unistd_64.h`；本教程的 `include/syscalls.inc` 只是常用子集。
* **Agner Fog 的优化手册**（Instruction Tables / Microarchitecture / Optimizing assembly）：查每条指令的延迟、吞吐、端口：[agner.org/optimize](https://www.agner.org/optimize/)
* **System V AMD64 ABI**：参数传递、栈对齐、寄存器保存规则的标准答案：[x86-64 psABI](https://gitlab.com/x86-psABIs/x86-64-ABI)
* **uops.info**：每条 x86 指令在各代 CPU 上的实测性能数据：<https://uops.info/>
* **Compiler Explorer**：在线看 `gcc/clang` 生成的汇编，改 `-O` 等级立刻对比：<https://godbolt.org/>

## 九、动手练习

1. 给 `wordcount` 加一个 `-l` 选项（只打印行数），注意“只有一个数字时不补空格”这个规则要不要跟着改。
2. 给 `hexdump2` 加 `-n N`：只输出前 N 字节（提示：把 `16 - have` 和总字节数比较，控制 `read` 的请求长度）。
3. 写一个 `tail_lines.asm`：打印文件最后 3 行（提示：`lseek` 到文件末尾往前找 `\n`，或者一次读完再倒着扫）。
4. 用 `hexdump2` 和系统的 `hexdump` 对比一个大于 1 MB 的文件，确认偏移列的 8 位十六进制不会溢出（提示：8 位十六进制最多表示 4 GB）。
5. 把 `wordcount` 的 `BUFSZ` 改成 1（每次只读 1 字节），跑 `big1.txt`，观察“跨 read 的单词状态”为什么是必需的。
6. 用第 13 课的套路，把 `count_fd` 里的空白判断改成 SIMD 版（提示：`pcmpeqb` 比较 6 种空白字符，或者用位运算范围判断），再用 `perf stat` 比一比。

第 2 题的思路：把“每次最多读 16 字节”改成“每次最多读 `min(16 - have, 剩余上限)`”，并在总字节数达到 N 时提前 `finish`。第 5 题的关键观察是：缓冲区边界会把一个单词切成两半，只有保留 `in_word` 状态才能数对。

## 十、常见坑

1. **取 `argc`/`argv` 之前 `push` 了东西**：`[rsp]` 就不再是 `argc` 了。入口处先 `mov rbx, [rsp]`、`lea r12, [rsp+8]` 存到被调用者保存寄存器里，再干别的。
2. **忘了检查 `argc`**：`./wordcount` 不带参数时 `argv[1]` 是 `NULL`，直接拿去 `openat` 会出错（甚至崩溃）。先 `cmp rbx, 2; jb` 走标准输入分支。
3. **`openat` 的 `mode` 参数**：只有带 `O_CREAT` 时才需要 `mode`，但寄存器还是得给个值（`xor r10d, r10d`）；另外第 4 个参数是 **`r10`**，不是 `rcx`。
4. **错误信息写进 stdout**：管道下游会把错误当成数据。错误一律 `STDERR`（fd 2）。
5. **多文件时把“半行”丢掉了**：`hexdump2` 里如果每个文件读完就打印半行并清零 `have`，输出就会在文件边界处多换一行，和 `hexdump -C a b` 不一致。
6. **列宽算错**：`wc` 的规则是“所有数字（含 total）共用同一个宽度”，不是每列各算各的。先统计再打印，别边数边打。
7. **忘了 `close`**：文件描述符泄漏在小工具里看不出来，但管道/循环调用时会撞上 fd 上限。
8. **忘了处理 `read` 的错误返回值**：`read` 返回负数是错误（比如对目录 `read` 会得到 `EISDIR`），本程序统一按“没有更多数据”处理——想更严谨可以判断 `rax < 0` 并报告 `errno`。
9. **`div` 之前忘了清零 `rdx`**：`div rbx` 用的是 `rdx:rax` 这 128 位被除数，`rdx` 里残留的旧值会让商错得离谱，甚至触发除零异常（SIGFPE）。`num_width`/`append_num` 里每次除法前都有 `xor edx, edx`。

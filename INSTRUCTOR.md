# 课程编写规范（子代理共享约定）

目标读者：**有 C 语言基础、第一次学 x86-64 汇编的初学者**，环境是 Debian 13 / x86-64 / NASM 2.16.03。

## 一、硬性技术约定（违反会导致编译或运行失败）

1. 示例分两种风格，**绝不能混**：

   | | 纯系统调用程序 | libc 程序 |
   |---|---|---|
   | 文件名 | 任意（`hello.asm`、`hexdump.asm`…） | **必须以 `lc_` 开头**（`lc_printf.asm`） |
   | 入口符号 | `global _start` | `global main`（**不能写 `_start`**） |
   | 链接方式 | `nasm -f elf64 -g -F dwarf` + `ld` | nasm + `gcc -no-pie` |
   | 返回 | `mov rax, 60` / `mov rdi, 退出码` / `syscall` | `xor eax, eax` + `leave`/`ret` |

   * 原因：`gcc -no-pie` 会链入 crt1.o，它**已经定义了 `_start`**，再定义一次就是 duplicate symbol；
     而且 libc 需要 crt1.o 做完初始化，自己写 `_start` 直接 `call printf` 会段错误（实测过）。
   * 纯 syscall 程序**不要**链接 libc：用 `include/io.inc` 里的例程做输入输出。

2. 每个课的 Makefile 已统一写好（`nasm -f elf64 -g -F dwarf -I ../include`），
   **不要修改 Makefile**；只要文件名和入口符号符合上表，`make` 就能跑通。

3. 64 位 System V 调用约定（调用 libc 函数时）：
   参数依次放 `rdi, rsi, rdx, rcx, r8, r9`，浮点参数放 `xmm0..xmm7`，
   返回值 `rax`（浮点 `xmm0`）；`rbx, rbp, r12-r15` 是被调用者保存，`rax, rcx, rdx, rsi, rdi, r8-r11` 是调用者保存。
   调用**变参函数**（`printf`、`scanf`）前必须把 `eax` 置成“用到的向量寄存器个数”（不用浮点就 `xor eax, eax`）。
   **`call` 指令执行时 rsp 必须是 16 的倍数**：函数入口要 `push rbp; mov rbp, rsp`，返回用 `leave; ret`；
   在函数中间临时 push 了奇数个 8 字节要记得补回来，否则 printf 里会崩。

4. 系统调用约定（64 位）：
   号放 `rax`，参数依次 `rdi, rsi, rdx, r10, r8, r9`（**第 4 个是 r10，不是 rcx**，这点和 C 调用不同），
   `syscall` 进入内核，返回值在 `rax`（负数表示 -errno）。内核会破坏 `rcx` 和 `r11`。
   常用号写在 `../include/syscalls.inc` 里（`SYS_read`、`SYS_write`、`SYS_openat`…），直接 `%include "syscalls.inc"` 用。

5. `io.inc` 提供的例程（已实测通过，签名不要改）：
   `io_write(rdi=fd, rsi=buf, rdx=len)`、`io_print(rsi=buf, rdx=len)`、`io_println(rsi=buf, rdx=len)`、
   `io_newline()`、`io_putchar(rdi=字符)`、`io_exit(rdi=退出码)`、`io_print_int(rdi=有符号)`、
   `io_print_uint(rdi=无符号)`、`io_print_hex(rdi=值)`、`io_print_bin(rdi=值)`。
   这些例程只破坏 `rax/rcx/r11`，且**一个程序里只能 `%include "io.inc"` 一次**（它是实现不是声明）。

   ⚠ 实测踩过的坑：**不要把 `rsi` 指向正在使用的栈空间**（例如 `push rax` 之后写 `mov rsi, rsp`
   再 `call io_print`）。这种“栈当输出缓冲区”的写法在多个 Linux 内核版本上会让 `syscall write`
   返回后栈帧错乱（`ret` 弹飞、段错误），表现为“程序能打印但立刻 SIGSEGV”。
   需要单字节输出时用 `io_putchar`（内部用 `.data` 里的静态缓冲区 `io_one_byte`），
   或者自己 `section .data` 里开一个字节缓冲区。

6. NASM 细节：
   数据一律 `default rel` + `lea rsi, [rel msg]`（不写绝对地址）；
   立即数 push 要留意 `push 0x1234` 只压 4 字节，需要 8 字节栈槽时先 `mov eax, 0x1234` 再 `push rax`；
   `%define` 定义常量，`%macro` 定义带参数的宏（第 12 课专门讲）；
   写 `mov edx, 1` 而不是 `mov dl, 1` 来设置 64 位寄存器——写低 8 位不会清零高 24 位。
   立即数 64 位要写成 `mov rax, 0x1122334455667788`（NASM 会用 movabs）。

7. 每个程序必须**自己结束**（`syscall exit` 或 `ret`），运行时间 < 1 秒，绝不写死循环；
   除刻意演示 “从标准输入读数据” 的程序外，不依赖键盘输入；
   读标准输入的程序在 `make run` 时会拿到 `/dev/null`，要能优雅处理读到 0 字节（EOF）的情况。

## 二、每个课的交付物

```
lessonNN/
├── README.md        课程正文（中文，见下）
├── *.asm            2~4 个可编译示例
└── test.sh          自测脚本：编译 + 运行 + 比对期望输出，成功 exit 0
```

`test.sh` 要求：

```bash
#!/usr/bin/env bash
# 第 NN 课自测：编译并检查示例输出
set -u
cd "$(dirname "$0")"
fail=0

# 每个示例一小段：拿真实输出和期望值对比
out=$(./hello)
if [ "$out" = "Hello, World!" ]; then echo "  [OK] hello"; else echo "  [FAIL] hello: $out"; fail=1; fi

# 读标准输入的程序要喂输入
out=$(printf '5\n' | ./echo_num)

[ $fail -eq 0 ] && echo "第 NN 课全部通过" || echo "第 NN 课存在失败"
exit $fail
```

注意：`make test` 会先 `make all`，所以 test.sh 里**不要**再调 make，直接 `./程序名` 即可；
程序不存在就直接失败。不要用可能有歧义的字符串比较（比如带 NUL 的），
`$(...)` 会吃掉结尾换行，写期望值时按“去掉结尾换行”来写。

`README.md` 结构（标题用 `# 第 NN 课：标题`）：

1. **本课目标**：3~5 条，动词开头。
2. **新概念 / 新指令**：用表格列出指令或概念 + 一句话说明 + 小例子（表格里代码用反引号）。
3. **示例源码逐段讲解**：每组示例先给 ```asm 代码块（**完整可编译**，和 .asm 文件内容一致），
   再逐段解释“这几行在干什么、为什么这么写”。
4. **编译与运行**：写清 `make`、`./程序名`、期望输出（用代码块给出真实输出）。
5. **动手练习**：3~6 题，从“改一个数看输出”到“自己写一个小程序”，最后 1~2 题给简要提示或思路（不直接给完整答案）。
6. **常见坑**：本项目里真实存在的坑（例如忘了 `rel`、`dl` 与 `edx` 的区别、syscall 第 4 个参数是 r10、`call` 前栈要对齐）。

篇幅：每课 README 约 200~400 行 Markdown，写透，但不要灌水。

## 三、15 课的划分（各课必须交付的文件名已指定）

| 课 | 目录 | 主题 | 课程内示例文件（必须用这些名字） |
|---|---|---|---|
| 01 | lesson01 | 环境、hello、汇编→链接→运行全流程 | `hello.asm`（syscall 版）、`hello_exit.asm`（只退出，看退出码） |
| 02 | lesson02 | 寄存器、内存、段、objdump/gdb 初探 | `regs.asm`、`mem.asm`（.data/.bss/栈） |
| 03 | lesson03 | 数据定义、db/dw/dd/dq、字符串与长度 | `data.asm`、`strlen.asm`（自己数长度） |
| 04 | lesson04 | 算术与逻辑指令、标志位 | `arith.asm`、`flags.asm`、`bitops.asm` |
| 05 | lesson05 | 跳转、条件转移、cmp/test | `cmpjmp.asm`、`minmax.asm` |
| 06 | lesson06 | 循环、数组遍历、loop/jnz | `count.asm`、`sum_array.asm` |
| 07 | lesson07 | 函数、栈、call/ret、调用约定 | `add_func.asm`、`stack_demo.asm`、`multi_args.asm` |
| 08 | lesson08 | 字符串与数字互转、进制打印 | `num2str.asm`、`str2num.asm` |
| 09 | lesson09 | 文件读写、更全的系统调用 | `copy.asm`（拷贝文件，命令行参数）、`wc.asm`（统计行/词/字节） |
| 10 | lesson10 | 浮点 SSE2（printf 输出，libc） | `lc_float.asm`、`lc_float_div.asm` |
| 11 | lesson11 | SIMD/sse/avx 入门（向量加法、字符统计） | `lc_simd_intro.asm`、`simd_strlen.asm` |
| 12 | lesson12 | 宏、重复、条件汇编、内联汇编 | `macro_demo.asm`、`lc_inline.asm`（`__asm__`，可再配 `lc_inline.c`） |
| 13 | lesson13 | 与 C 互调、编译混合、性能优化 | `lc_asm_lib.asm` + `c_driver.c`、`lc_opt.asm` |
| 14 | lesson14 | 调试（gdb、objdump）与常见陷阱 | `debug_target.asm`（故意先写错再修好，README 讲清）、`hexdump.asm` |
| 15 | lesson15 | 综合项目：命令行工具 + 结课回顾 | `hexdump2.asm`（带命令行参数）、`wordcount.asm` |

第 13、15 课如果需要 `gcc` 参与链接（如 C 与汇编混合），
**不要改本课 Makefile**：把 C 文件写出来，并在 README 里说明额外的编译命令，
`test.sh` 里用显式命令自己编译（例如 `gcc -no-pie -o mix c_driver.c lc_asm_lib.o`），
同时保证 `make all` 仍能成功（即 `lc_*.asm` 单独也能被 `gcc -no-pie` 链接成功）。

## 四、写作风格

* 全部中文，术语首次出现给英文原名（例如“栈（stack）”“立即数（immediate）”）。
* 讲“为什么”而不是只罗列指令；每段代码后紧跟解释。
* 不写“本课内容非常丰富”“让我们一起来学习”之类的空话。
* 表格、ASCII 内存示意图、指令对照表受欢迎。
* 命令行一律给出可直接复制执行的完整命令。

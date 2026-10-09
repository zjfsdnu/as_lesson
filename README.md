# x86-64 汇编语言教程（NASM / Linux）

> 一句话定位：**给有 C 基础、第一次学汇编的人准备的 15 课实战教程**——从 `hello world` 一直写到 `hexdump` 和 `wc` 两个能用的命令行工具。

## 目标读者与环境

**目标读者**：会写 C（知道指针、数组、函数、编译链接大概怎么回事），从没写过汇编，或者写过但没搞清“栈、调用约定、系统调用”这些底层细节的人。

**环境要求**：**Linux x86-64**（本教程在 Debian 13 上完整验证过；Ubuntu 22.04/24.04 同样适用）。

```bash
# Debian / Ubuntu 一条龙安装
sudo apt update
sudo apt install -y nasm gcc binutils gdb make
```

| 工具 | 用途 | 验证命令 |
|---|---|---|
| `nasm` | 汇编器（本教程用 2.16.03） | `nasm -v` |
| `gcc` | 链接 libc 风格的程序、混合编译、看编译器输出 | `gcc --version` |
| `binutils` | `ld`（纯 syscall 程序直接链接）、`objdump`、`readelf`、`nm`、`size` | `ld -v` |
| `gdb` | 调试（第 14 课） | `gdb --version` |
| `make` | 编译驱动 | `make -v` |

可选：`sudo apt install -y bsdextrautils` 装上 `hexdump`，第 14/15 课的 `test.sh` 会和真正的 `hexdump -C` 逐字节交叉验证。

**不适合**：Windows 原生（可以用 WSL2）、macOS 原生。原因是本教程大量使用 Linux 的 64 位系统调用（`syscall`、`rax` 编号、`rdi/rsi/rdx/r10/r8/r9` 传参），macOS 的系统调用号、调用方式和 `ld` 行为都不一样，代码抄过去跑不起来。

## 为什么还要学汇编

1. **看懂“机器实际执行什么”**：`objdump -d`、崩溃栈、`perf` 报告里的东西不再是天书；C 里的未定义行为、结构体布局、栈溢出都能自己解释。
2. **调试能力质变**：段错误（SIGSEGV）在 C 里常常只能靠猜，在汇编层面可以精确到“哪条指令访问了哪个地址”。
3. **性能的最后一公里**：编译器已经很强，但自动向量化会失败、热点循环的分支会猜错。懂汇编才看得懂 Agner Fog 的表，才知道该改哪里。
4. **理解 ABI 和链接**：调用约定、栈对齐、弱符号、PLT/GOT、`-no-pie` 与 PIE 的区别——这些概念在写库、写驱动、做逆向时天天遇到。
5. **安全与逆向的基础**：漏洞利用、shellcode、CTF、恶意代码分析，入口都是汇编。

## 15 课路线图

| 课 | 主题 | 你将学会 | 示例文件 |
|---|---|---|---|
| 01 | 环境、hello、汇编→链接→运行全流程 | 写/编译/链接/运行第一个 NASM 程序；`_start` 与 `exit` 系统调用；看退出码 | `hello.asm`、`hello_exit.asm` |
| 02 | 寄存器、内存、段、objdump/gdb 初探 | 64 位通用寄存器、`mov` 的各种寻址、`.data`/`.bss`/栈的区别 | `regs.asm`、`mem.asm` |
| 03 | 数据定义、`db/dw/dd/dq`、字符串与长度 | 在数据段放字符串和数组；用 `equ $ - 标签` 算长度 | `data.asm`、`strlen.asm` |
| 04 | 算术与逻辑指令、标志位 | `add/sub/imul/div/and/or/xor/shl`；ZF/CF/SF/OF 怎么来的 | `arith.asm`、`flags.asm`、`bitops.asm` |
| 05 | 跳转、条件转移、`cmp`/`test` | 有符号（`jl/jg/jle`）和无符号（`jb/ja/jbe`）条件转移的正确选择 | `cmpjmp.asm`、`minmax.asm` |
| 06 | 循环、数组遍历、`loop`/`jnz` | 用 `inc/cmp/jb` 写循环、遍历数组、累加/查找 | `count.asm`、`sum_array.asm` |
| 07 | 函数、栈、`call/ret`、调用约定 | 栈帧（`push rbp`/`leave`）、参数与返回值、被调用者保存寄存器 | `add_func.asm`、`stack_demo.asm`、`multi_args.asm` |
| 08 | 字符串与数字互转、进制打印 | 手写 `itoa`/`atoi`；十进制/十六进制输出；进制转换里的除法与取余 | `num2str.asm`、`str2num.asm` |
| 09 | 文件读写、更全的系统调用 | `openat/read/write/close/lseek`；命令行参数；文件拷贝与统计 | `copy.asm`、`wc.asm` |
| 10 | 浮点 SSE2（printf 输出，libc） | `movsd/addsd/mulsd/divsd`；`lc_` 风格链接 libc 打印浮点 | `lc_float.asm`、`lc_float_div.asm` |
| 11 | SIMD/sse/avx 入门（向量加法、字符统计） | `movdqu/paddq/pcmpeqb/psadbw`；向量化思维与尾部处理 | `lc_simd_intro.asm`、`simd_strlen.asm` |
| 12 | 宏、重复、条件汇编、内联汇编 | `%define/%macro/%rep/%ifdef`；C 里写 `__asm__` | `macro_demo.asm`、`lc_inline.asm`（配 `lc_inline.c`） |
| 13 | 与 C 互调、编译混合、性能优化 | 汇编库 + C 混合编译（`-no-pie`）、弱符号 `main`、simd 优化与实测 | `lc_asm_lib.asm` + `c_driver.c`、`lc_opt.asm` |
| 14 | 调试（gdb、objdump）与常见陷阱 | 断点/单步/查内存；认出“32 位写错”“off-by-one”；写出 `hexdump -C` | `debug_target.asm`、`hexdump.asm` |
| 15 | 综合项目：命令行工具 + 结课回顾 | `argc/argv`、`openat`、多文件、错误与退出码、对齐输出；知识地图与后续方向 | `hexdump2.asm`、`wordcount.asm` |

每课目录里都有 `README.md`（课程正文）、若干 `.asm` 示例和 `test.sh`（自测脚本，`make test` 会调用它）。

## 目录结构

```text
asm-tutorial/
├── README.md              ← 你正在读的文件（教程总览 + FAQ）
├── INSTRUCTOR.md          ← 编写规范（技术约定、交付要求；改教程前先读它）
├── Makefile               ← 顶层总控：make / make test / make clean / make run / make list
├── include/
│   ├── io.inc             ← 纯 syscall 的输入输出小工具（io_print/io_print_int/io_exit…）
│   └── syscalls.inc       ← 系统调用号与常量（SYS_read、STDIN、O_RDONLY、LF…；注意 AT_FDCWD 不在这里，要自己定义）
├── lesson01/ … lesson15/  ← 每课一个目录：README.md + *.asm + test.sh + Makefile
│   └── Makefile           ← 每课统一的编译规则（nasm + ld / nasm + gcc -no-pie）
└── tools/
    ├── gen_makefiles.py   ← 批量生成各课 Makefile 的脚本
    ├── verify_remote.sh   ← 把教程同步到 Linux 机器上编译 + 全量测试的验证脚本
    └── _probe/            ← 编写教程时用来验证 io.inc / libc / SSE 行为的小探针程序
```

## 编译与运行

### 顶层

```bash
make            # 编译全部 15 课
make test       # 先 make all，再逐课运行 test.sh 比对输出
make run        # 顺序运行全部示例（输出很长；标准输入接 /dev/null）
make clean      # 清理所有可执行文件和 .o
make list       # 列出课目录
```

### 单课

```bash
cd lesson06
make            # 编译本课全部示例
make run        # 依次运行本课示例（< /dev/null）
make test       # 运行 ./test.sh
make clean
./sum_array     # 也可以直接跑某个程序
```

### 两种示例风格（非常重要，绝不能混）

| | 纯系统调用程序 | libc 程序 |
|---|---|---|
| 文件名 | 任意（`hello.asm`、`hexdump.asm`…） | **必须以 `lc_` 开头**（`lc_float.asm`） |
| 入口符号 | `global _start` | `global main`（**绝不能写 `_start`**） |
| 链接方式 | `nasm -f elf64 -g -F dwarf` + `ld` | `nasm` + `gcc -no-pie` |
| 返回值/退出 | `mov rax, 60` / `mov rdi, 退出码` / `syscall` | `xor eax, eax` + `leave`/`ret` |
| 能用什么 | `include/io.inc`、裸 `syscall` | `printf`/`scanf` 等 libc 函数（不要 include `io.inc`） |

**为什么必须这样区分？**

* `gcc -no-pie` 会链入 `crt1.o`，它**自己已经定义了 `_start`**。你再用 `global _start` 就是 `duplicate symbol '_start'`；反过来，libc 需要 `crt1.o` 做完初始化（设置 `stdout` 缓冲、`errno`、TLS 等），自己写 `_start` 直接 `call printf` 会段错误。
* `ld` 直链的程序**没有 libc**。这时 `printf` 不存在，只能用 `io.inc` 里基于 `write` 系统调用的例程；这样编出来的程序也最小、最“裸”，适合看清“程序就是内核 + 指令”。
* 一个程序里**不要既 include `io.inc` 又用 libc**：`io.inc` 是**实现**（不是声明），重复 include 会符号重定义，而且 libc 的启动流程和纯 syscall 入口不兼容。

`include/io.inc` 提供的例程（只破坏 `rax/rcx/r11`）：

```asm
%include "io.inc"          ; 一个程序里只 include 一次，放在 section .text 里

lea rsi, [rel msg]         ; 消息地址
mov rdx, msg_len           ; 消息长度（equ $ - msg）
call io_println            ; 输出并换行

mov rdi, 12345
call io_print_int          ; 十进制输出有符号整数
```

## 学习建议

1. **每课按顺序来**：先读 `README.md`，再看 `.asm` 源码，最后 `make && make run` 看真实输出。
2. **手敲代码，不要复制**。汇编的细节全在“宽度、方向、顺序”上，眼睛看过和手指敲过是两回事；敲错了再对照文件找差异，这个过程本身就是训练。
3. **每课都做练习题**，至少做完前 2 道（改一个数看输出）和最后 1 道（自己写个小程序）。
4. **改坏它，再修好**：把 `jb` 改成 `jbe`、把 `rax` 改成 `eax`、把 `mov edx` 改成 `mov dl`，看程序怎么错；然后用 gdb/objdump 把它找回来（第 14 课专门训练这个）。
5. **善用工具**：`objdump -d -M intel -l 程序`、`readelf -h/-S`、`nm`、`size`、`gdb`、`perf stat`。看不懂的指令去查 Intel SDM / felixcloutier。
6. **随时 `make test`**：每课的 `test.sh` 会把真实输出和期望值比对，输出对不上就是有地方和 README 讲的不一致。

## 常见问题 FAQ

**1. `nasm: fatal: unable to open input file 'hello.asm'`**

文件不在当前目录，或者文件名写错了（Linux 区分大小写）。先 `ls` 确认。如果报的是 `unable to open include file 'io.inc'`，说明你在错误的目录里直接调 `nasm`：本教程的 Makefile 用 `-I ../include` 指定头文件目录，所以要么在 `lessonNN/` 里 `make`，要么手工加 `-I ../include`：

```bash
nasm -f elf64 -g -F dwarf -I ../include -o hello.o hello.asm
```

**2. `ld: cannot find -lc` / `undefined reference to 'printf'`**

你试图用 `ld` 直链一个要调用 libc 的程序。`ld` 默认不找 libc 的路径，纯 syscall 程序也**不应该**链 libc。两种正确做法：

```bash
# 纯 syscall 程序：nasm + ld，别加 -lc
nasm -f elf64 -g -F dwarf -I ../include -o hello.o hello.asm && ld -o hello hello.o

# libc 程序：文件名以 lc_ 开头、入口 main、用 gcc 链接
nasm -f elf64 -g -F dwarf -o lc_demo.o lc_demo.asm && gcc -no-pie -o lc_demo lc_demo.o
```

**3. `ld: duplicate symbol '_start'` 或 `ld: warning: cannot find entry symbol _start`**

前者：用 `gcc`（默认会链 `crt1.o`）链接了一个自己定义了 `_start` 的程序——`crt1.o` 里已经有一个 `_start`。**libc 程序的入口符号必须叫 `main`**，文件名要用 `lc_` 前缀。
后者：用 `ld` 链接了一个只有 `main` 的 `lc_` 程序。用 `gcc -no-pie` 链接它。

**4. `duplicate symbol 'main'`（第 13 课混合编译时）**

`lc_asm_lib.asm` 里的 `main` 是**弱符号**（`global main:weak`），单独链接时充当入口，和 `c_driver.c` 的强 `main` 共存时自动让位。如果你把它改成了 `global main`（强符号），两个 `main` 就会冲突。解决办法：改回 `:weak`，或者用 `-DNO_MAIN` 编译出不含 `main` 的纯函数库：

```bash
nasm -f elf64 -g -F dwarf -DNO_MAIN -o lc_asm_lib.o lc_asm_lib.asm
gcc -no-pie -o mix c_driver.c lc_asm_lib.o
```

**5. 段错误（SIGSEGV）出现在 `printf` 里 / “`movaps` 指令崩溃”**

绝大多数是**栈对齐**问题：`call` 执行的那一刻 `rsp` 必须是 16 的倍数。函数入口写

```asm
push rbp
mov  rbp, rsp
; … 函数体 …
leave           ; 等价于 mov rsp, rbp; pop rbp
ret
```

这样 `call` 进来时 `rsp % 16 == 8`，`push rbp` 之后就是 16 的倍数。函数中间如果临时 `push` 了**奇数个** 8 字节，记得补一个 `sub rsp, 8`（或再 push 一个）再用；调用完恢复。libc 的 `printf` 内部会用 `movaps` 操作栈上的浮点数据，栈没对齐就崩。

**6. 系统调用的第 4 个参数是 `r10`，不是 `rcx`**

x86-64 系统调用约定：号在 `rax`，参数依次 `rdi, rsi, rdx, **r10**, r8, r9`。这**和 C 函数调用不同**（C 的第四个参数才在 `rcx`），因为 `syscall` 指令用 `rcx` 保存返回地址、用 `r11` 保存标志位。典型例子：

```asm
; openat(AT_FDCWD, path, O_RDONLY, 0)
mov rax, SYS_openat
mov rdi, AT_FDCWD       ; -100（这个常量要自己 %define）
lea rsi, [rel path]     ; 路径字符串的地址
mov rdx, O_RDONLY
xor r10d, r10d          ; ← 第 4 个参数用 r10，不是 rcx！
syscall
```

另外记住：`syscall` 会破坏 `rcx` 和 `r11`，返回值在 `rax`（负数表示 `-errno`）。

**7. `push` 立即数：只有 `push imm32`**

x86-64 没有 `push imm64`。`push 0x1234` 汇编成 5 字节的 `push imm32`，压栈时把 32 位**符号扩展**到 64 位；`push 0x1122334455667788` 直接汇编不过。想要一个确定的 8 字节栈槽，先过一遍寄存器：

```asm
mov eax, 0x1234                 ; 写 32 位寄存器会清零高 32 位
push rax                        ; 现在栈上是 0x0000000000001234

mov rax, 0x1122334455667788     ; NASM 自动用 movabs
push rax
```

还要记住 `push`/`pop` 会改变 `rsp`：如果后面紧跟 `call`/`syscall`，栈对齐和参数寄存器都要重新算。

**8. 写了 `mov dl, 1`，高位却没清零**

写 8 位/16 位寄存器的**不会**清零同一个 64 位寄存器的高位（只有写 32 位寄存器才会把高 32 位清零）。所以

```asm
mov dl, 1        ; 错的：rdx 的高 56 位保留旧值
mov edx, 1       ; 对的：rdx = 1（高 32 位自动清零）
```

这种 bug 在使用 `%include "io.inc"` 的 `io_print` 时特别容易犯：长度参数用 `rdx`，写成 `mov dl, 7` 就会带上垃圾高位，`write` 的长度变成天文数字（表现为“什么都不输出”或“卡住”）。

**9. `symbol 'xxx' not defined`（调用 libc 函数时）**

NASM 不认识别的目标文件里的符号，必须显式声明：

```asm
extern printf
```

反过来，你自己写的函数要给 C 调用，就写 `global 函数名`。

**10. `[rel 标签 + rcx*8]` 汇编不过**

RIP 相对寻址**不能带索引寄存器**（机器码格式不支持）。先取基址再用普通寻址：

```asm
lea rbx, [rel arr]          ; 先拿到地址
add rax, [rbx + rcx*8]      ; 再带索引
```

**11. 程序跑完不退出 / “Segmentation fault (core dumped)” 在 `ret` 时**

纯 syscall 程序（`_start`）的栈顶没有返回地址，`ret` 会跳到垃圾地址。必须用 `exit` 系统调用自己结束（或调用 `io_exit`）：

```asm
mov rax, SYS_exit
xor edi, edi
syscall
```

**12. `make run` 时程序卡住不动**

`make run` 把标准输入接的是 `/dev/null`。如果你的程序用 `read(0, …)` 读标准输入，读到 0（EOF）时必须优雅退出，不能死循环等待：

```asm
syscall                 ; read
test rax, rax
jle  .done              ; 0 = EOF，负数 = 错误，都要退出
```

同理，读键盘输入的程序在这套 Makefile 下会直接读到 EOF——练习时手工 `./程序名` 再输入，或者用管道喂数据：`printf 'hello\n' | ./程序名`。

**13. 输出和期望值差一个换行 / `test.sh` 报 `[FAIL]`**

`test.sh` 用 `$(...)` 抓输出，而命令替换会**吃掉结尾的换行**。写期望值时要按“去掉结尾换行”的字符串来写。自己排查时用 `./程序 | cat -A` 看清行尾到底是 `$`（有换行）还是缺了。

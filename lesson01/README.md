# 第 01 课：环境、Hello World、汇编→链接→运行全流程

## 一、本课目标

- 说清一个汇编程序从 `.asm` 源码到能跑的可执行文件，中间到底经历了哪几步、每步由谁完成。
- 写出并跑通第一个程序：用系统调用（system call）在屏幕上打印 `Hello, World!`。
- 学会用 `echo $?` 读出一个程序的退出码（exit status），并理解它为什么是 0~255。
- 能看懂 `readelf`、`objdump`、`size`、`file` 对一个小程序输出的是什么。
- 认识两种程序风格的区别：**纯系统调用程序**和**libc 程序**，知道本教程的文件名规则。

## 二、新概念 / 新指令

| 概念 / 指令 | 一句话说明 | 小例子 |
|---|---|---|
| `section .data` | 数据段，放有初值的数据；初值会被写进可执行文件 | `section .data` |
| `section .text` | 代码段，放 CPU 要执行的指令 | `section .text` |
| `global _start` | 声明 `_start` 是全局符号，链接器靠它决定程序从哪开始执行 | `global _start` |
| `_start:` | 真正的入口标签。内核把控制权交给它，之前没有任何初始化代码 | `_start:` |
| `db` | Define Byte，放一个字节；也可以放一串字符 | `msg db "hi", 10` |
| `equ` | 汇编期常量，不占内存，用一次替换一次 | `msg_len equ $ - msg` |
| `$` | 汇编器内置符号，表示"当前这一行的地址" | `msg_len equ $ - msg` |
| `mov 目标, 源` | 传送数据。两边宽度必须一致，不能 `mov rax, al` | `mov rax, 1` |
| `lea rsi, [rel msg]` | 把地址装进 `rsi`（不是取内容） | `lea rsi, [rel msg]` |
| `syscall` | 进入内核，按 `rax` 里的系统调用号干活 | `syscall` |
| `rax = 1` | 系统调用号 1 = `write(fd, buf, len)` | `mov rax, 1` |
| `rax = 60` | 系统调用号 60 = `exit(code)` | `mov rax, 60` |
| `xor edi, edi` | 把 `edi` 清零（`rdi` 的高 32 位也一起清零），比 `mov rdi, 0` 短 | `xor edi, edi` |
| `nasm -f elf64` | 把汇编源码汇编成 64 位 ELF 目标文件（`.o`） | `nasm -f elf64 -o hello.o hello.asm` |
| `ld -o hello hello.o` | 链接器，把目标文件变成可执行文件 | `ld -o hello hello.o` |
| `$?` | shell 变量，上一个命令的退出码 | `./hello; echo $?` |

## 三、示例源码逐段讲解

### 3.1 hello.asm —— 纯系统调用的 Hello World

```asm
; ===========================================================================
; hello.asm —— 第 01 课：最小的 "Hello, World!"（纯系统调用版，不链接 libc）
;
; 构建（本课 Makefile 里就是这么干的）：
;   nasm -f elf64 -g -F dwarf -I ../include -o hello.o hello.asm
;   ld -o hello hello.o
;
; 运行：
;   ./hello
; ===========================================================================

default rel                     ; 内存操作数默认用 RIP 相对寻址（理由见 README「常见坑」）

; ---------------------------------------------------------------------------
; 数据段：程序运行期间要用的数据。这里的数据会原样写进可执行文件。
; ---------------------------------------------------------------------------
section .data
    msg     db  "Hello, World!", 10     ; 13 个可见字符 + 1 个换行符（10 == '\n'）
    msg_len equ $ - msg                 ; 长度 = 当前地址 $ 减去 msg 的起始地址

; ---------------------------------------------------------------------------
; 代码段：CPU 真正执行的指令
; ---------------------------------------------------------------------------
section .text
    global _start                       ; 告诉链接器：程序入口符号叫 _start

_start:
    ; ---- 第 1 步：write(1, msg, msg_len) ----
    mov     rax, 1                      ; rax = 系统调用号；1 == write
    mov     rdi, 1                      ; 第 1 个参数：文件描述符 1 == stdout
    lea     rsi, [rel msg]              ; 第 2 个参数：缓冲区地址（msg 的地址）
    mov     rdx, msg_len                ; 第 3 个参数：要写多少字节（= 14）
    syscall                             ; 进入内核，内核照 rax 里的号码执行 write

    ; ---- 第 2 步：exit(0) ----
    mov     rax, 60                     ; rax = 系统调用号；60 == exit
    xor     edi, edi                    ; 第 1 个参数：退出码 0
                                        ; xor edi,edi 与 mov rdi,0 等价，但机器码更短
    syscall                             ; 退出进程，这条之后不会再有指令执行
```
逐段解释：

**`default rel`** —— 让所有 `[标签]` 形式的内存操作数默认按 RIP 相对寻址（相对当前指令的位置）来算地址，而不是绝对地址。64 位程序里绝对寻址有诸多限制，养成写它的习惯。后面的 `lea rsi, [rel msg]` 又显式写了一次 `rel`，属于"说清楚"而不是"必须"——两条都写上，读代码的人不用去猜当前模式。

**数据段的三行**

```asm
section .data
    msg     db  "Hello, World!", 10     ; 13 个可见字符 + 1 个换行符（10 == '\n'）
    msg_len equ $ - msg                 ; 长度 = 当前地址 $ 减去 msg 的起始地址
```

`db` 把字符串按字节一个挨一个摆好。注意最后那个 `10`：它就是换行符 `'\n'`（ASCII 码 10）。汇编里的字符串**不会自动补结尾的 0**，也不会自动换行——你想输出换行，就得自己把 `10` 放进数据里，或者单独调用一次输出。

`msg_len equ $ - msg` 是汇编期算术：此时 `$` 指到 `db` 之后的第一个空闲位置，减去 `msg` 的起始位置，正好是这段数据的字节数 = 13 + 1 = **14**。这样写好处是：以后你改字符串内容，长度会自动跟着变，不用手改两处。

**程序入口**

```asm
section .text
    global _start                       ; 告诉链接器：程序入口符号叫 _start

_start:
```

`global _start` 是给链接器看的声明；`_start:` 是真正的标签。两者名字必须一致。纯系统调用程序**不需要**任何启动代码：内核把程序加载进内存后，直接跳到 `_start` 开始执行，此时栈上放着 `argc`、`argv` 等（第 09 课讲命令行参数时会用到）。

**第一次系统调用：write**

```asm
    mov     rax, 1                      ; rax = 系统调用号；1 == write
    mov     rdi, 1                      ; 第 1 个参数：文件描述符 1 == stdout
    lea     rsi, [rel msg]              ; 第 2 个参数：缓冲区地址（msg 的地址）
    mov     rdx, msg_len                ; 第 3 个参数：要写多少字节（= 14）
    syscall                             ; 进入内核，内核照 rax 里的号码执行 write
```

这四行是 64 位 Linux 系统调用约定的完整演示：

| 寄存器 | 作用 | 本例 |
|---|---|---|
| `rax` | 系统调用号 | `1` = `write` |
| `rdi` | 第 1 个参数 | `1` = stdout |
| `rsi` | 第 2 个参数 | `msg` 的地址 |
| `rdx` | 第 3 个参数 | `14` |
| `r10` | 第 4 个参数（**不是 `rcx`**） | 本例用不到 |
| `r8`、`r9` | 第 5、6 个参数 | 本例用不到 |

返回值和错误码都放在 `rax` 里（负数表示 `-errno`）。另外内核执行 `syscall` 时会**破坏 `rcx` 和 `r11`**，因为这两个寄存器被用来保存返回地址和标志位。

注意 `lea rsi, [rel msg]` 用的是 `lea`（Load Effective Address）而不是 `mov`：`lea` 取的是"地址"这个数值，`mov rsi, [rel msg]` 则会去那个地址读 8 个字节的内容。这两者在 NASM 里语法只差一对方括号，含义完全不同。

**第二次系统调用：exit**

```asm
    mov     rax, 60                     ; rax = 系统调用号；60 == exit
    xor     edi, edi                    ; 第 1 个参数：退出码 0
    syscall                             ; 退出进程，这条之后不会再有指令执行
```

程序必须**自己结束**。如果 `_start` 执行完最后一条指令就让它"落下去"，CPU 会继续执行后面内存里的垃圾字节，多半是段错误（Segmentation fault）。用 `exit` 系统调用结束，退出码 0 表示成功。

`xor edi, edi` 和 `mov rdi, 0` 效果一样（寄存器自己异或自己恒为 0），机器码更短，而且**写 32 位寄存器会把对应 64 位寄存器的高 32 位一起清零**——这一点第 02 课会专门展开。

### 3.2 hello_exit.asm —— 只负责退出的小程序

```asm
; ===========================================================================
; hello_exit.asm —— 第 01 课：一个字节都不输出，只负责"退出"
;
; 用途：退出码（exit status）平时看不见，用 shell 的 $? 才能看到。
;       Linux 里退出码只有最低 8 位有效，所以 0~255。
;
; 运行：
;   ./hello_exit
;   echo $?         # 期望打印 42
; ===========================================================================

default rel

section .text
    global _start

_start:
    mov     rax, 60                 ; rax = 系统调用号；60 == exit
    mov     rdi, 42                 ; 第 1 个参数：退出码 42
    syscall                         ; 进程到此结束，shell 里用 $? 读到的就是 42
```
这个程序一个字节都不输出，只做一件事：以退出码 42 结束。它的价值在于让退出码"看得见"：

```bash
./hello_exit
echo $?          # 42
```

关于退出码有三点要注意：

1. 退出码只能在 **0~255** 范围内传递。Linux 只取 `rdi` 的最低 8 位。实测：把 `mov rdi, 42` 改成 `mov rdi, 300`，`echo $?` 打印的是 **44**（300 & 0xFF = 44）；改成 `0xff` 打印 **255**。
2. 习惯上 0 表示成功，非 0 表示失败。所以 `hello.asm` 用 0，`hello_exit.asm` 故意用 42 来演示。
3. `$?` 是 shell 的东西，程序本身不会打印退出码。

## 四、编译与运行

本课的 Makefile 已经写好了编译规则，最省事的方式：

```bash
cd lesson01
make                 # 编译出 hello 和 hello_exit
./hello
./hello_exit; echo $?
```

期望输出（真实运行结果）：

```text
$ ./hello
Hello, World!
$ ./hello_exit
$ echo $?
42
```

也可以 `make run`，它会依次运行本课所有程序并打印退出码；`make test` 会先 `make all`，再跑本课的 `test.sh` 做自动比对。

### 4.1 手工走一遍两步流程

`make` 背后其实就两条命令，建议至少手工敲一次：

```bash
nasm -f elf64 -g -F dwarf -I ../include -o hello.o hello.asm
ld -o hello hello.o
./hello
```

- `nasm -f elf64`：把文本形式的汇编源码翻译成 **ELF64 目标文件**（`.o`）。这一步只做翻译，还不知道 `_start` 最终落在哪个地址。
- `-g -F dwarf`：生成 DWARF 调试信息，这样以后用 `gdb` 能看到源码行号。文件会变大，但对学习很值。
- `-I ../include`：把 `../include` 加进 include 搜索路径，本课的 `hello.asm` 其实没用到，但后面的课要 `%include "io.inc"`。
- `ld -o hello hello.o`：链接。链接器读 `.o` 里的符号表，把 `_start` 放到最终地址上，输出可执行文件。

两个中间产物的区别值得看一眼：

```text
$ file hello.o
hello.o: ELF 64-bit LSB relocatable, x86-64, version 1 (SYSV), with debug_info, not stripped
$ file hello
hello:   ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, with debug_info, not stripped
```

一个是 `relocatable`（可重定位，地址还没定），一个是 `executable`（可执行，地址已定）。`readelf -h hello.o` 里的 `Entry point address` 是 `0x0`，而可执行文件里是 `0x401000`——入口地址是链接阶段才填进去的。

### 4.2 用工具看看编译器到底生成了什么

**`readelf -h hello`**（看 ELF 头部，节选）：

```text
Class:                             ELF64
Type:                              EXEC (Executable file)
Machine:                           Advanced Micro Devices X86-64
Entry point address:               0x401000
Number of program headers:         3
Number of section headers:         10
```

`Entry point address: 0x401000` 就是 CPU 执行的第一条指令的地址，也就是 `_start` 的地址。

**`objdump -d -M intel hello`**（反汇编，`-M intel` 让输出用 Intel 语法而不是默认的 AT&T 语法）：

```text
0000000000401000 <_start>:
  401000:	b8 01 00 00 00       	mov    eax,0x1
  401005:	bf 01 00 00 00       	mov    edi,0x1
  40100a:	48 8d 35 ef 0f 00 00 	lea    rsi,[rip+0xfef]        # 402000 <msg>
  401011:	ba 0e 00 00 00       	mov    edx,0xe
  401016:	0f 05                	syscall
  401018:	b8 3c 00 00 00       	mov    eax,0x3c
  40101d:	31 ff                	xor    edi,edi
  40101f:	0f 05                	syscall
```

三个细节比对着源码看很有意思：

- 源码里写的是 `mov rax, 1`，反汇编出来却是 `mov eax,0x1`（机器码 `b8 01 00 00 00`，5 字节）。这不是反汇编器搞错了，而是 NASM 的优化：往 `eax` 写会自动把 `rax` 高 32 位清零，效果和 `mov rax,1` 完全一样，但机器码更短。
- `lea rsi,[rip+0xfef]` 里出现了 `rip`，这正是 `default rel` 的效果：这条指令记的是"相对当前 RIP 偏移 0xfef"，而不是一个写死的绝对地址。`# 402000 <msg>` 是 objdump 帮你算出的最终地址。
- `xor edi,edi` 只占 2 字节（`31 ff`），比 `mov edi,0`（5 字节）短。

**`objdump -s -j .data hello`**（把 `.data` 段的原始字节打出来）：

```text
Contents of section .data:
 402000 48656c6c 6f2c2057 6f726c64 210a      Hello, World!.
```

`48 65 6c 6c ...` 就是 `H e l l o ...` 的 ASCII 码，最后一个 `0a` 是换行。**字符串确实是以字节形式躺在可执行文件里的**，这就是 `section .data` 的含义。

**`size hello`**：

```text
   text	   data	    bss	    dec	    hex	filename
     33	     14	      0	     47	     2f	hello
```

代码 33 字节、数据 14 字节，正好对应 8 条指令和 14 字节的 `msg`。

## 五、动手练习

1. 把 `msg` 改成 `"你好，汇编！"`，不动 `msg_len` 那一行，重新编译运行。输出对不对？为什么？（提示：一个汉字在 UTF-8 里占 3 字节，但 `equ $ - msg` 是自动算的，所以你其实什么都不用改。）

2. 把 `hello_exit.asm` 的退出码改成 `0`、`255`、`300`，每次 `make && ./hello_exit; echo $?`。把三个结果记下来，解释 300 的结果。

3. 让 `hello` 输出两行文字（第二行自己加），要求只用一次 `write` 系统调用。

4. 让 `hello_exit.asm` 在退出前往 stdout 打印一行 `bye`，退出码保持 42。

5. **只给思路**：把 `hello.asm` 里 `write` 的 `rdi` 从 `1` 改成 `2`，输出会跑到哪里去？试一下：
   `./hello > out.txt` 之后再 `cat out.txt`，对比一下不加 `2>` 和加 `2>` 的区别。

6. **只给思路**：把 `lea rsi, [rel msg]` 改成 `mov rsi, msg`（去掉方括号和 `rel`），先用 `objdump -d -M intel hello` 看机器码有什么变化，再想想为什么在非 PIE 的可执行文件里它也能跑通。

## 六、常见坑

1. **忘了 `global _start`**。链接时报 `cannot find entry symbol _start; defaulting to ...`，或者生成了一个从奇怪地址开始执行的程序。入口符号和 `global` 声明必须成对出现。

2. **纯 syscall 程序和 libc 程序的入口不能混**。本教程规定：文件名不以 `lc_` 开头的是纯系统调用程序，入口必须写 `global _start`，用 `nasm` + `ld` 链接；文件名以 `lc_` 开头的是 libc 程序，入口必须写 `global main`，用 `gcc -no-pie` 链接。`gcc -no-pie` 会链入 `crt1.o`，它**已经定义了 `_start`**，你再定义一次就是 duplicate symbol；反过来，libc 需要 `crt1.o` 做完初始化，自己写 `_start` 直接调 `printf` 会段错误。

3. **长度算错**。`msg_len` 忘记把结尾的换行 `10` 算进去，输出就会挤在一起没有换行；多算一个字节，就会多输出一个（通常是 0 或别的垃圾字节）。`equ $ - msg` 是省心的写法，但要注意 `$` 的位置——写在 `db` 后面才是数据长度。

4. **`mov dl, 1` 不等于 `mov edx, 1`**。`dl` 只是 `rdx` 的最低 8 位，写它**不会**清零高 24 位。如果之前 `rdx` 里有垃圾，长度就成了一个大得离谱的数，`write` 会写出一堆垃圾甚至报错。要设置 64 位量就写 32 位寄存器名（`mov edx, 1`），它会自动清零高 32 位。

5. **忘了写 `[rel ...]`**。在 64 位下写 `mov rsi, msg` 会按 32 位绝对地址处理，链接器可能报 `relocation R_X86_64_32S against '.data' can not be used when making a PIE object`，或者在高地址（>4GB）下直接算错。统一写 `lea rsi, [rel 标签]`。

6. **忘了调用 `exit`**。程序不会"自然结束"，`_start` 末尾之后是未定义的内容。表现通常是段错误（退出码 139）。每个程序都要有明确的结束路径。

7. **`$?` 看起来"没生效"**。只要你在 `echo $?` 之前又跑了一条别的命令（哪怕只是 `echo`），`$?` 就被覆盖了。要紧接着写。

8. **改了 `.asm` 却忘了重新 `make`**。`make` 只看时间戳：如果 `.asm` 比可执行文件新才会重新编译。改完源码直接跑旧程序，看到的还是老输出。不确定时先 `make clean && make`。

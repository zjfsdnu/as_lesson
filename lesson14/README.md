# 第 14 课：调试（gdb、objdump）与常见陷阱

## 一、本课目标

* 学会用 **gdb** 单步（`si`/`ni`）、下断点（`b`）、查内存（`x`）、看寄存器（`info registers`、`p`）来定位 bug。
* 学会用 **objdump -d -M intel** 反汇编、**readelf** 看 ELF 结构和调试信息，并对照源码找出指令级差异。
* 亲手把一个“看起来正常、结果却错”的程序修好，理解 **32 位/64 位宽度写错** 和 **循环边界 off-by-one** 这两类经典 bug。
* 综合运用前面所有知识，纯系统调用写出一个 `hexdump -C`：偏移 + 16 字节十六进制 + ASCII 视图。
* 建立排查清单：段错误、死循环、结果不对，分别先看什么。

本课文件：

| 文件 | 风格 | 说明 |
|---|---|---|
| `debug_target.asm` | 纯 syscall（`_start` + `ld`） | 求 `count/sum/avg` 的靶子。默认编译**修好**的版本；加 `-DBUGGY_VERSION` 编译出有 bug 的版本 |
| `hexdump.asm` | 纯 syscall | 从标准输入读，按 `hexdump -C` 格式输出 |
| `test.sh` | — | 两种版本的输出比对 + hexdump 固定输入比对（有 `hexdump` 时逐字节交叉验证） |

## 二、新概念 / 新命令

| 命令 | 作用 | 例子 |
|---|---|---|
| `gdb ./prog` | 打开程序准备调试 | `gdb ./debug_target_buggy` |
| `set disassembly-flavor intel` | 反汇编用 Intel 语法（和本教程一致） | 写进 `~/.gdbinit` 一劳永逸 |
| `b <位置>` | 下断点，位置可以是符号、`文件:行号`、`*地址` | `b _start`、`b debug_target.asm:60` |
| `b <位置> if <条件>` | 条件断点，命中条件才停 | `b _start.sum_loop if $rcx == 8` |
| `run` / `r` | 开始运行（可带命令行参数） | `r input.txt` |
| `x/9gx $rbx` | 从 `$rbx` 起显示 9 个 **g**iant（8 字节）**x** 进制数 | `x/9gx $rbx` |
| `x/8xb $rsp` | 从 `$rsp` 起显示 8 个 **b**yte | 入口处看 argc/argv |
| `x/i $pc` | 反汇编当前这条指令 | `x/i $pc` |
| `info registers` | 显示所有寄存器 | `info registers rcx rax` 只看两个 |
| `p/d $rax` / `p/x $rax` | 以十进制 / 十六进制打印表达式 | `p/d $rcx` |
| `disas <符号>` | 反汇编函数（`disas /r` 带机器码） | `disas /r _start` |
| `si` / `ni` | 单步一条**指令**：`si` 会进入 `call`，`ni` 不进入 | `si`、`ni` |
| `s` / `n` | 单步一条**源码行** | `n` |
| `c` | 继续运行到下一个断点 | `c` |
| `bt` | 打印调用栈 | `bt` |
| `watch <表达式>` | 设观察点，值变化时停下 | `watch $rax`（寄存器观察点靠 gdb 模拟） |
| `objdump -d -M intel prog` | 反汇编可执行文件（Intel 语法） | 加 `-l` 带源码行号 |
| `objdump -d -M intel lib.o` | 反汇编目标文件 | 看 `add rax,QWORD PTR` 这种宽度 |
| `readelf -h prog` | ELF 头（入口地址 `Entry point`） | `readelf -h debug_target` |
| `readelf -S prog` | 节表（`.text` / `.data` / `.bss` 各在哪、多大） | `readelf -S debug_target` |
| `readelf -s prog` | 符号表 | `readelf -s lc_asm_lib.o` |
| `readelf --debug-dump=info prog` | 看 DWARF 调试信息（`-g -F dwarf` 的产物） | 确认行号信息在不在 |
| `nm prog` / `size prog` | 看符号 / 看各节大小 | `nm debug_target \| grep sum` |

## 三、示例一：`debug_target.asm` —— 一个“结果不对”的程序

程序很短：给 8 个元素的数组求和，再算平均值。

```asm
COUNT   equ 8                   ; 数组元素个数
arr:
    dq 0x20000000, 0x20000000, 0x20000000, 0x20000000
    dq 0x20000000, 0x20000000, 0x20000000, 0x20000000
sentinel:
    dq 0x40000000
```

`0x20000000 = 536870912`，8 个元素的和是 `0x100000000 = 4294967296` —— 这个数字**刚好超过 32 位**（32 位最大 `0xFFFFFFFF`），所以它是暴露“宽度写错”的完美测试数据。

### 3.1 有 bug 的版本（`-DBUGGY_VERSION`）

```asm
    xor eax, eax                ; BUG 2：累加器只用 32 位
    xor ecx, ecx
.sum_loop:
    add eax, dword [rbx + rcx*8]    ; BUG 2：只读低 4 字节，高 4 字节丢掉
    inc rcx
    cmp rcx, COUNT
    jbe .sum_loop               ; BUG 1：应该是 jb（rcx < COUNT）
```

两个 bug 都在这一段：

* **BUG 1（循环边界 off-by-one）**：`cmp rcx, 8` 之后用 `jbe`（jump if below or equal）意味着 `rcx == 8` 时还会再跑一轮，于是读了 `arr[8]`——数组后面的 `sentinel`。应该是 `jb`（严格小于）。这类 bug 的可怕之处是**不崩溃**：`sentinel` 就在 `.data` 里，越界读完全合法，只是结果悄悄错掉。
* **BUG 2（寄存器宽度写错）**：累加器用 `eax`（32 位），读内存也用 `dword`（4 字节）。`add eax, …` 的结果会自动截断到 32 位，`0x100000000` 截断成 `0`。

它的输出是：

```text
count = 9
sum   = 1073741824
avg   = 119304647
```

`count` 是 9 而不是 8，已经把 BUG 1 暴露了一半；`sum` 应该是 4294967296，现在成了 `0x40000000`（8 个元素的和被截断成 0，再加越界读到的 `sentinel` 0x40000000）。

### 3.2 用 gdb 定位（真实会话）

先编译出有 bug 的版本（`-g -F dwarf` 让 gdb 能对上行号）：

```bash
nasm -f elf64 -g -F dwarf -DBUGGY_VERSION -I ../include -o debug_target.o debug_target.asm
ld -o debug_target_buggy debug_target.o
gdb -q ./debug_target_buggy
```

在 gdb 里依次执行（`(gdb)` 后面是输入的命令）：

```text
(gdb) set disassembly-flavor intel
(gdb) b _start.sum_loop if $rcx == 8
Breakpoint 1 at 0x40117c: file debug_target.asm, line 60.
(gdb) run
Breakpoint 1, _start.sum_loop () at debug_target.asm:60
60	    add eax, dword [rbx + rcx*8]    ; BUG 2：只读低 4 字节，高 4 字节丢掉
(gdb) p/d $rcx
$1 = 8
(gdb) p/x $rax
$2 = 0x0
(gdb) x/i $pc
=> 0x40117c <_start.sum_loop>:	add    eax,DWORD PTR [rbx+rcx*8]
(gdb) x/9gx $rbx
0x402000 <arr>:	0x0000000020000000	0x0000000020000000
0x402010:	0x0000000020000000	0x0000000020000000
0x402020:	0x0000000020000000	0x0000000020000000
0x402030:	0x0000000020000000	0x0000000020000000
0x402040 <sentinel>:	0x0000000040000000
(gdb) ni
61	    inc rcx
(gdb) p/x $rax
$4 = 0x40000000
(gdb) info registers rcx rax
rcx            0x8                 8
rax            0x40000000          1073741824
```

把这段“破案”过程读一遍，每个 bug 是怎么被发现的：

1. **`p/d $rcx` = 8**，但数组只有 8 个元素（下标应该是 0~7）。说明循环多跑了一轮 → BUG 1。
   能停在“最后一轮”靠的是**条件断点** `if $rcx == 8`；否则你得按 8 次 `c`。
2. **`x/9gx $rbx`** 直接看到内存：8 个 `0x20000000` 后面紧跟着 `sentinel` 的 `0x40000000`，而当前这轮循环正要读第 9 个 8 字节——越界坐实了。
3. **`x/i $pc`** 显示当前指令是 `add eax,DWORD PTR [rbx+rcx*8]`：
   * 目标是 `eax`（32 位）而不是 `rax`；
   * 从内存读的是 `DWORD PTR`（4 字节）而不是 `QWORD PTR`（8 字节）。
   这就是 BUG 2。
4. **`ni` 之后 `$rax = 0x40000000`**：一个 `0x20000000` 加进去没问题（本来就在低位），但前面 8 个元素加起来超过 32 位已经“归零”，现在只剩越界读到的那个值。

> 小技巧：`bt` 在这里显示 `#1 0x0000000000000001 in ?? ()`，因为纯 syscall 程序的入口是 `_start`，栈上没有真实的返回地址。**纯 `_start` 程序不要指望 `bt` 有意义**，从汇编角度看调用栈就是一张白纸。

### 3.3 用 objdump 对照两种编译结果

不看源码、只看机器码也能发现 BUG 2——两种版本的循环指令不一样：

```bash
objdump -d -M intel debug_target_buggy | sed -n '/sum_loop/,+5p'
```

```text
000000000040117c <_start.sum_loop>:
  40117c:	03 04 cb             	add    eax,DWORD PTR [rbx+rcx*8]
  40117f:	48 ff c1             	inc    rcx
  401182:	48 83 f9 08          	cmp    rcx,0x8
  401186:	76 f4                	jbe    40117c <_start.sum_loop>
  401188:	49 89 cd             	mov    r13,rcx
```

修好版：

```bash
objdump -d -M intel debug_target | sed -n '/sum_loop/,+5p'
```

```text
000000000040117d <_start.sum_loop>:
  40117d:	48 03 04 cb          	add    rax,QWORD PTR [rbx+rcx*8]
  401181:	48 ff c1             	inc    rcx
  401184:	48 83 f9 08          	cmp    rcx,0x8
  401188:	72 f3                	jb     40117d <_start.sum_loop>
  40118a:	49 89 cd             	mov    r13,rcx
```

对照着看：

| | 有 bug | 修好 |
|---|---|---|
| 操作数宽度 | `03`（`add r32, r/m32`）+ `DWORD PTR` | `48 03`（REX.W + `add r64`）+ `QWORD PTR` |
| 循环条件 | `76` = `jbe` | `72` = `jb` |

机器码只会忠实执行你写的东西，不会替你想“这个数会不会太大”。**写汇编时，宽度是一个必须逐条检查的属性。** 这也是 gdb/objdump 最大的价值：它把“你写的”和“实际执行的”摆在同一个屏幕上。

### 3.4 修好的版本

```asm
    xor rax, rax                ; 64 位累加器
    xor ecx, ecx
.sum_loop:
    add rax, [rbx + rcx*8]      ; 一次读满 8 字节
    inc rcx
    cmp rcx, COUNT
    jb .sum_loop                ; rcx < COUNT 才继续 → 正好 8 次
```

```bash
make                    # 默认就是修好的版本
./debug_target
```

```text
count = 8
sum   = 4294967296
avg   = 536870912
```

## 四、示例二：`hexdump.asm` —— 纯 syscall 版 `hexdump -C`

目标输出（和 Linux 的 `hexdump -C` 逐字节一致）：

```text
$ printf 'hello\n' | ./hexdump
00000000  68 65 6c 6c 6f 0a                                 |hello.|
00000006
```

一行 79 个字符，布局固定：

```text
偏移(8)  空格空格  十六进制区(49)  空格  '|'  ASCII(≤16)  '|'  '\n'
00000000  68 65 6c 6c 6f 0a                                 |hello.|
^        ^                                               ^
0        10                                              60
```

十六进制区固定 **49** 个字符 = `16 字节 × 3` + **第 8 个字节后额外 1 个空格**（这就是 `hexdump -C` 把一行分成两栏的样子）。不足 16 字节的行，缺的字节用 3 个空格补上，ASCII 区只显示真实存在的字节。数据全部读完后，还会单独打印一行总偏移（`00000006`）；输入为空时什么都不打印。

### 4.1 读入循环：处理“短读”和 EOF

```asm
_start:
    mov qword [rel total], 0

.next_line:
    mov qword [rel have], 0

    ; ---- 把这一行的数据读满（read 可能短读，所以要循环凑）----------------
.fill:
    mov rax, SYS_read
    xor edi, edi                ; fd = 0（标准输入）
    lea rsi, [rel inbuf]
    add rsi, [rel have]         ; 接着上次的位置写
    mov rdx, 16
    sub rdx, [rel have]         ; 还差几个字节
    syscall
    test rax, rax
    jle .filled                 ; 0 = EOF，负数 = 出错，都按结束处理
    add [rel have], rax
    cmp qword [rel have], 16
    jb .fill                    ; 没满 16 字节就继续读

.filled:
    cmp qword [rel have], 0
    je .finish                  ; 一个字节都没读到 → 输入结束
    call emit_line
    mov rax, [rel have]
    add [rel total], rax        ; 偏移前进
    cmp qword [rel have], 16
    jb .finish                  ; 这一行不满 16 字节说明已经读到文件末尾
    jmp .next_line

.finish:
    cmp qword [rel total], 0
    je .exit                    ; 输入为空：什么都不打印
    call emit_offset_line       ; 最后补一行“总偏移”，和 hexdump -C 一致
.exit:
    xor edi, edi
    call io_exit
```

要点：

* **`read` 不保证读满**。管道、终端甚至普通文件都可能只给你几个字节，所以必须“还差多少就请求多少，读到的累加起来，没满就再读”。`hexdump` 这种工具如果直接 `read(0, buf, 16)` 然后不管返回值就打印，遇到短读就会输出错位的行。`make run` 时标准输入是 `/dev/null`，第一次 `read` 就返回 0，程序必须优雅退出——这个循环做到了。
* `total` 是“已经处理过的总字节数”，也就是下一行的偏移；它在内存里而不是寄存器里，因为 `emit_line` 里会用到，而函数调用之间寄存器不保证保留（`rbx`/`r12-r15` 才保证）。
* 读到 `rax <= 0` 时统一按结束处理：`0` 是 EOF，负数是 `-errno`。对 `hexdump` 来说两者都“没数据可读了”。

### 4.2 生成一行：`emit_line`

```asm
emit_line:
    push rbx
    push r12
    push r13
    push r14
    push r15
    lea r14, [rel hexdig]       ; 字符表
    lea r15, [rel line]         ; 输出游标
    lea rbx, [rel inbuf]        ; 数据源
    mov r13, [rel have]         ; 本行有效字节数（后面循环用，省得反复读内存）

    ; ---- 1) 8 位十六进制偏移 ---------------------------------------------
    mov ecx, 28                 ; 从第 28 位（最高半字节）开始，每次右移 4 位
.off:
    mov rdx, [rel total]
    shr rdx, cl                 ; cl = 本次的移位量
    and edx, 0x0f
    mov al, [r14 + rdx]
    mov [r15], al
    inc r15
    sub ecx, 4
    jns .off                    ; 28,24,...,0 共 8 位

    mov byte [r15], ' '
    mov byte [r15 + 1], ' '
    add r15, 2

    ; ---- 2) 16 个字节的十六进制（不足的补空格）---------------------------
    xor r12d, r12d
.bytes:
    cmp r12, r13
    jae .pad
    movzx eax, byte [rbx + r12]
    mov edx, eax
    shr edx, 4                  ; 高半字节
    mov dl, [r14 + rdx]
    mov [r15], dl
    inc r15
    mov edx, eax
    and edx, 0x0f               ; 低半字节
    mov dl, [r14 + rdx]
    mov [r15], dl
    inc r15
    mov byte [r15], ' '
    inc r15
    jmp .after_byte
.pad:
    mov byte [r15], ' '
    mov byte [r15 + 1], ' '
    mov byte [r15 + 2], ' '
    add r15, 3
.after_byte:
    cmp r12, 7
    jne .next_byte
    mov byte [r15], ' '         ; 第 8 个字节后额外空一格（hexdump -C 的分栏）
    inc r15
.next_byte:
    inc r12
    cmp r12, 16
    jb .bytes

    ; ---- 3) ASCII 视图 ----------------------------------------------------
    mov byte [r15], ' '
    inc r15
    mov byte [r15], '|'
    inc r15
    xor r12d, r12d
.ascii:
    cmp r12, r13
    jae .ascii_done
    movzx eax, byte [rbx + r12]
    cmp al, 0x20                ; 小于空格 → '.'
    jb .dot
    cmp al, 0x7e                ; 大于 '~'（含 0x7f~0xff）→ '.'
    ja .dot
    mov [r15], al
    jmp .ascii_next
.dot:
    mov byte [r15], '.'
.ascii_next:
    inc r15
    inc r12
    jmp .ascii
.ascii_done:
    mov byte [r15], '|'
    inc r15
    mov byte [r15], LF
    inc r15

    ; ---- 4) 一次 write 输出整行 ------------------------------------------
    lea rsi, [rel line]
    mov rdx, r15
    sub rdx, rsi                ; 长度 = 游标 - 行首
    mov rdi, STDOUT
    call io_write

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
```

逐段解释：

* **偏移一位一位地取**：`shr rdx, cl` 配合 `sub ecx, 4`，从第 28 位开始每次右移 4 位取半字节，正好 8 次。`cl` 是 x86 规定的变量移位量寄存器——移位次数只能放 `cl`。
* **半字节 → 字符**：`hexdig` 是 `"0123456789abcdef"`，半字节的值就是下标。取高半字节用 `shr edx, 4`，取低半字节用 `and edx, 0x0f`。
* **补空格**：`cmp r12, r13; jae .pad` —— 下标已经超出“有效字节数”就写 3 个空格（一个字节的位置是 `xx `）。注意第 8 字节后的额外空格是**无条件**加的（`cmp r12, 7` 那一段），这样十六进制区永远是 49 字符，ASCII 区的起始列永远固定。
* **ASCII 判定**：`cmp al, 0x20; jb .dot` 和 `cmp al, 0x7e; ja .dot` 用的是**无符号**比较，所以 `0x7f~0xff` 全部落在“大于 `'~'`”里 → 显示成 `.`。这和 `hexdump -C` 一致。
* **先在内存里拼整行，再一次 `write`**：如果每个字节都 `write` 一次，`hexdump` 一个 1 MB 的文件就要 300 万次系统调用。攒成一行一次输出，是这类工具的标准做法（缓冲区大小 128 字节足够容纳最长的 79 字节行）。
* **`push` 了 5 个寄存器**：`rbx`、`r12-r15` 是被调用者保存寄存器，函数里改了就必须还原；这样调用者在 `call emit_line` 前后不用操心这些寄存器。函数里只用到 `rax/rcx/rdx` 这些调用者保存寄存器当临时工。
* **数据引用一律 `lea r14, [rel hexdig]`**：`default rel` + `rel` 让 NASM 生成 RIP 相对寻址，程序加载到哪都能跑（写死绝对地址在 PIE 下会出问题）。注意 **RIP 相对寻址不能带下标寄存器**，所以 `[rel arr + rcx*8]` 是非法写法，必须先 `lea` 拿到基址再用 `[rbx + rcx*8]`——这是本课最常踩的语法坑。

### 4.3 最后那行总偏移

`emit_offset_line` 和 `emit_line` 的前半段（打印 8 位偏移）几乎一样，只是末尾补一个换行：

```asm
emit_offset_line:
    push rbx
    push r14
    lea r14, [rel hexdig]
    lea rbx, [rel line]
    mov ecx, 28
.off:
    mov rdx, [rel total]
    shr rdx, cl
    and edx, 0x0f
    mov al, [r14 + rdx]
    mov [rbx], al
    inc rbx
    sub ecx, 4
    jns .off
    mov byte [rbx], LF
    inc rbx

    lea rsi, [rel line]
    mov rdx, rbx
    sub rdx, rsi
    mov rdi, STDOUT
    call io_write

    pop r14
    pop rbx
    ret
```

## 五、编译与运行

```bash
make                    # 编译 debug_target 和 hexdump（都是纯 syscall，nasm + ld）
./debug_target          # 运行修好的版本
./hexdump < 任意文件
printf 'hello\n' | ./hexdump
```

```text
$ ./debug_target
count = 8
sum   = 4294967296
avg   = 536870912

$ printf 'hello\n' | ./hexdump
00000000  68 65 6c 6c 6f 0a                                 |hello.|
00000006

$ ./hexdump < /dev/null      # 空输入：什么都不打印，退出码 0
```

有 bug 的版本（README 第三节用的就是这个）：

```bash
nasm -f elf64 -g -F dwarf -DBUGGY_VERSION -I ../include -o debug_target.o debug_target.asm
ld -o debug_target_buggy debug_target.o
./debug_target_buggy
```

```text
count = 9
sum   = 1073741824
avg   = 119304647
```

自测：

```bash
make test       # 等价于先 make all 再跑 ./test.sh
./test.sh
```

`test.sh` 会检查：修好版的输出、有 bug 版的输出、`hexdump` 的四组固定输入；如果系统里装了 `hexdump`，还会和 `hexdump -C` 逐字节交叉验证六组输入（含随机二进制）。

## 六、动手练习

1. 把 BUG 1 修好、BUG 2 留着（`jb` + `eax`），运行看看 `sum` 是多少，解释为什么。
2. 把 BUG 2 修好、BUG 1 留着（`jbe` + `rax`），运行看看 `sum` 和 `avg` 是多少。
3. 用 gdb 的 `watch $rax`（或 `b _start.sum_loop` 配合每轮 `p/x $rax`）观察累加器在第 8、9 轮分别变成什么。
4. 给 `hexdump.asm` 加一个 `-c` 风格的**偏移列宽度自适应**？不必——改成“每行只显示 8 字节”、十六进制区分两栏改成 4+4，看看格式哪里要跟着改（提示：49 这个常数、第 8 字节后的额外空格）。
5. 让 `hexdump.asm` 在读完数据后额外输出 `total = N bytes` 一行（提示：在 `.finish` 里调用 `io_print_int`，注意 `io_*` 例程只破坏 `rax/rcx/r11`）。
6. 写一个只输出**前 16 字节**的 `head16.asm`：读满 16 字节就打一行然后退出（提示：把 `.next_line` 循环改成一次就 `io_exit`）。

第 1、2 题的思路：先分别算出“正确结果”和“错误结果”，对照第三节的两个 bug 说清每一步丢了什么（截断 or 多读）。第 4 题的关键是：格式里所有写死的列宽都要跟着改，改完用 `hexdump -C` 对照验证。

## 七、常见坑

1. **`read` 返回值不当回事**：短读、EOF（0）、错误（负数）三种情况都要处理。`hexdump` 这类工具直接在 `/dev/null` 上跑就会立刻遇到 `0`；只判断“读了 16 字节”的写法会死循环或输出垃圾。
2. **`[rel 标签 + 索引*比例]` 是非法寻址**：RIP 相对寻址不允许再带索引寄存器。正确写法是先 `lea rbx, [rel 标签]`，再 `[rbx + rcx*8]`。
3. **`dword` / `qword` 少写或写错**：`add eax, dword [rbx]` 和 `add rax, [rbx]` 是两条完全不同的指令；跟内存操作数打交道时，尺寸要么由另一个操作数推出，要么显式写 `byte`/`word`/`dword`/`qword`。
4. **`jbe` 与 `jb` 一字之差**：`jbe` 包含“等于”，循环用它会多跑一轮。凡是 `i <= n` 形式的边界都要单独想一遍“下标最大值是多少”。
5. **`-g -F dwarf` 忘了加**：gdb 里的 `list`、断点行号、源码级单步（`n`/`s`）都会失效，只能看汇编。本课 Makefile 已经统一加上了。
6. **纯 `_start` 程序的 `bt` 没有意义**：入口就是栈顶，没有返回地址，gdb 只能打出一堆 `??`。
7. **`hexdump -C` 的“尾巴”**：数据长度正好是 16 的倍数时会多出一行纯偏移（`00000010`）；不足 16 字节的行要补空格把 ASCII 区对齐到第 60 列。想少踩这个坑，就先用 `printf 'hello\n' | hexdump -C` 看一眼真实格式。
8. **调试时改了源码但没重新编译**：gdb 显示的行号和磁盘上的源码对不上，会把人带偏。`make && gdb ./prog` 一起做。

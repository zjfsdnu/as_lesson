# 第 12 课：宏、条件汇编与内联汇编

## 本课目标

* 分清 NASM 预处理器（`%` 开头）和真正的指令：前者在**汇编期**干活，不生成机器码。
* 会用 `%define` 定义常量，用 `%macro`/`%endmacro` 定义带参数的宏，并引用 `%1`、`%2`。
* 会用 `%rep` 重复源码、用 `%ifdef`/`%if`/`%ifidn` 做条件汇编，并知道它们和 `if` 语句的区别。
* 会写 GCC 的 `__asm__ volatile` 内联汇编，说清 AT&T 与 Intel 语法的五条主要差异。
* 会做 C 与 NASM 汇编的混合编译，并正确处理两边的调用约定。

## 新概念 / 新指令

| 名称 | 一句话说明 | 小例子 |
|---|---|---|
| `%define` | 定义单行宏（文本替换），汇编期生效，不占空间 | `%define BUF_SIZE 64` |
| `%macro` / `%endmacro` | 定义带参数的宏 | `%macro P 1` … `%endmacro` |
| `%1` `%2` `%0` | 宏里的第 1、2 个参数，以及参数个数 | `mov rdi, %1` |
| `%%label` | 宏内部的**局部标签**，每次展开自动改名，不会重复定义 | `%%loop:` |
| `%%label` | 宏内部的**局部标签**，每次展开都会变唯一（跳转和数据都能用） | `%%tag: db %1` |
| `%rep N` / `%endrep` | 把一段源码重复抄 N 遍（N 是汇编期常量） | `%rep 3` … `%endrep` |
| `%ifdef` / `%ifndef` | 宏有没有定义？条件汇编 | `%ifdef DEBUG` |
| `%if` / `%elif` / `%else` | 汇编期算术/比较条件（不是运行时） | `%if BUF_SIZE < 32` |
| `%ifidn` / `%ifidni` | 两个文本是否相同（`i` 后缀 = 忽略大小写） | `%ifidn VERSION_STR, "12.0"` |
| `%error` | 汇编期直接报错，比运行时才发现问题省事 | `%error "BUF_SIZE 太小"` |
| `%assign` | 定义可重算的数值宏 | `%assign n 0` |
| `%strlen` / `%substr` | 汇编期取字符串长度/子串 | `%strlen n "hello"` |
| `%include` | 把另一个文件的内容插进来 | `%include "syscalls.inc"` |
| `__asm__ volatile` | GCC 内联汇编的关键字（**C 语言特性，NASM 没有**） | `__asm__ volatile ("addq %1, %0" : "=r"(o) : "r"(x))` |
| `"r"` / `"=r"` / `"t"` / `"=t"` | 内联汇编的操作数约束：通用寄存器 / 只写 / xmm / 只写 xmm | `: "=t" (out) : "t" (v)` |
| `"cc"` / `"memory"` | clobber 列表：告诉 gcc 标志位/内存被改了 | `: "cc"` |

### 汇编期 vs 运行期：本课最重要的一根线

```text
  源文件 (.asm)
      │
      │  NASM 预处理器处理 %define / %macro / %rep / %if / %include
      │  —— 这一步做的全是「文本替换和复制」
      ▼
  纯指令流 (经过预处理之后的文本)
      │
      │  NASM 汇编器翻译成机器码
      ▼
  目标文件 (.o)  ──链接──▶  可执行文件  ──运行──▶  CPU 一条条执行
```

所以：

* `%rep 3` **不是**循环，它让源码里出现 3 份一样的指令 —— 运行期是 3 段顺序代码。
* `%ifdef DEBUG` **不是**运行时判断，条件不满足时那一段**根本不会出现在可执行文件里**。
* `%define` **不是**变量，它没有地址、不能在运行时改。

## 示例源码逐段讲解

### 示例 1：macro_demo.asm

; ===========================================================================
; 第 12 课示例 1：macro_demo.asm
; ...（完整源码见同目录 macro_demo.asm，这里只摘出和宏有关的片段）...

%define VERSION_MAJOR   12
%define VERSION_MINOR   0
%define VERSION_STR     "12.0"
%define BUF_SIZE        64              ; 试试改成 8 或 128，看输出怎么变
%define NEWLINE         10

%define DEBUG                           ; 保留这行 -> 走 Debug 分支
                                        ; 注释掉它   -> 那段代码根本不出现在可执行文件里

; 一个小检查：条件不满足时直接让汇编失败，比运行时出错更省事
%if BUF_SIZE < 8
    %error "BUF_SIZE 至少要 8 个字节"
%endif

; %macro：带参数的宏，%1/%2/%3 就是第几号参数
%macro SYS_WRITE3 3
    mov  rax, SYS_write
    mov  rdi, %1
    mov  rsi, %2
    mov  rdx, %3
    syscall                             ; syscall 会破坏 rcx 和 r11
%endmacro

; ---- 往 stdout 写一段字符串并换行 ----
; %1 是 "带引号的字符串字面量"。
; 标签统一用 %% 前缀（%%name）：每次宏展开 NASM 都会生成唯一的名字，
; 所以同一个宏展开两次也不会「符号重复定义」。
%macro PRINT_LINE 1
    jmp  short %%past                   ; 先跳过内嵌的数据，别让 CPU 执行到它
%%tag:  db %1
%%len_tag equ $ - %%tag
%%nl_tag: db NEWLINE
%%past:
    mov  rax, SYS_write
    mov  rdi, STDOUT
    lea  rsi, [rel %%tag]
    mov  rdx, %%len_tag
    syscall
    mov  rax, SYS_write
    mov  rdi, STDOUT
    lea  rsi, [rel %%nl_tag]
    mov  rdx, 1
    syscall
%endmacro

; ---- 在汇编期拿到字符串长度 ----

; %strlen：对「带引号的参数」直接算长度（单位是字节，中文算 3 字节）
; ⚠ 不要写成 %defstr %%s %1 —— 参数里只要出现中文，NASM 2.16 会把多字节
;   当成字符常量而报 "character constant too long"，直接对 %1 用 %strlen 最稳。
%macro SHOW_STR_INFO 1
    %strlen %%n %1                      ; 汇编期算出「字符串的字节数」
    jmp  short %%body                   ; ⚠ 先跳过下面的字符串数据
%%s: db %1                              ; 数据就在代码段里，不跳过会被当指令执行
%%body:
    mov  rax, SYS_write
    mov  rdi, STDOUT
    lea  rsi, [rel %%s]
    mov  rdx, %%n
    syscall
%endmacro

; ---------------------------------------------------------------------------
; 三、%rep：把一段源码重复抄 N 遍（N 是汇编期常量或表达式）
;     这里用它生成一条 60 个 '-' 的分隔线：db 60 个重复字节
; ---------------------------------------------------------------------------

; %rep：把 SEP 这份源码抄 3 遍（不是运行期循环）
%macro SEP 0
    mov  rax, SYS_write
    mov  rdi, STDOUT
    lea  rsi, [rel %%line]
    mov  rdx, 61
    syscall
    jmp  short %%after
%%line: db "------------------------------------------------------------", NEWLINE
%%after:
%endmacro

    %rep 3
        SEP
    %endrep

; 条件汇编：满足条件才把这段汇编进去
section .text
    global _start

%ifdef DEBUG
    PRINT m_dbg_on, m_dbg_on_len
%else
    PRINT m_dbg_off, m_dbg_off_len
%endif

%if BUF_SIZE < 32
    PRINT m_small, m_small_len
%else
    PRINT m_big, m_big_len
%endif

; 宏把参数转发给例程：宏本身不展开成一大堆指令
%macro PRINT 2                          ; %1 = 缓冲区/标签，%2 = 长度
    lea  rsi, [rel %1]
    mov  rdx, %2
    call io_print
%endmacro

%macro PRINT_NUM 1                      ; %1 = 数字（也可以是 VERSION_MAJOR 这种宏）
    mov  rdi, %1
    call io_print_uint
    call io_newline
%endmacro

```

**`%%` 和 `%$` 的区别（这里踩过坑，重点看）**

* `%%label`：宏内部的**局部标签**。每次宏展开 NASM 都会给它生成唯一的名字，
  跳转（`jmp %%past`）和取地址（`lea rsi, [rel %%tag]`）都能用。
  本课的宏全部用这一种，它是宏里最实用的写法。
* `%$label`：宏**上下文（macro context）**里的局部标签，必须先 `%push` 建立
  上下文栈才能用。直接在没有 `%push` 的宏里写 `%$tag`，NASM 会报：

  ```
  error: `%$tag': context stack is empty
  ```

  所以除非你真的在用 `%push`/`%pop` 那套机制，否则**统一用 `%%`**。
  （顺带一提：数据如果用 `%defstr` 把一个含中文的字符串转成符号，
  2.16 会报 `character constant too long`；要让汇编期算长度，
  直接对带引号的参数用 `%strlen` 就没有这个问题。）

**为什么 `%if` 不是 `if`**

```asm
; 汇编期：BUF_SIZE 只可能是常量，两个分支只留一个
%if BUF_SIZE < 32
    PRINT m_small, m_small_len
%else
    PRINT m_big, m_big_len
%endif
```

把 `%define BUF_SIZE 64` 改成 `8`，重新 `make`，你会发现
生成的可执行文件里**只有小缓冲那段文字**，大缓冲那段连字节都不存在。
这就是「条件汇编」和运行时 `cmp` + `jne` 的本质区别。

### 示例 2：lc_inline.asm 与 lc_inline.c

`lc_inline.asm` 是 NASM 一侧（能单独运行，入口 `main`），
`lc_inline.c` 才是真正用 `__asm__` 写内联汇编的一侧。
两者一起编译就变成「C 调汇编、汇编调 C」的完整例子。

/* ...（完整源码见同目录 lc_inline.c）... */

static long add_two(long x)
{
    long out;
    __asm__ volatile (
        "movq  %1, %0\n\t"      /* out = x（"=r" 是只写，所以先搬一次） */
        "addq  $2, %0\n\t"      /* out += 2（立即数要写 $2） */
        : "=r" (out)
        : "r"  (x)
        : "cc"                  /* 声明改动了标志位 */
    );
    return out;
}

/* ---------------------------------------------------------------------------
 * 2) double_it(x) -> 2x
 *    这里演示「GCC 帮你搬运」：两个操作数可以落在同一个寄存器里
 *    （x 用完了就没人再要它，gcc 允许复用），于是指令数最少。
 * ------------------------------------------------------------------------- */
static double fma_like(double v)
{
    double out;
    __asm__ volatile (
        "movsd %1, %0\n\t"      /* out = v */
        "addsd %1, %0\n\t"      /* out = 2v */
        "addsd %1, %0\n\t"      /* out = 3v */
        "mulsd %1, %0\n\t"      /* out = 3v * v = 3v^2 */
        : "=t" (out)
        : "t"  (v)
    );
    return out;                 /* 2.0 -> 12.0 */
}

/* ---------------------------------------------------------------------------
 * 4) 用 GCC 的固定寄存器变量对上 SysV 调用约定
 *    register ... asm("xmm0") 告诉 gcc：这个变量请放在 xmm0。
 *    下面这个函数体里一条指令都没写，纯粹靠 gcc 把参数放进 xmm0/xmm1，
 *    正好就是 NASM 那边 scale_shift 期望的位置 —— 于是可以直接互调。
 *
 *    为什么不在内联汇编里手写 call：
 *      call 会破坏所有调用者保存寄存器，而内联汇编的输入/输出约束
 *      也可能被分配成 xmm0/xmm1，稍微写错就是「输出寄存器被调用破坏」。
 *      教学上更稳的做法是用两个小函数把寄存器搬运交给编译器 ——
 *      本函数就是那个「中转站」。
 * ------------------------------------------------------------------------- */
extern double scale_shift(double x, double s);      /* 由 lc_inline.asm 提供 */

static inline double scale_shift_native(double x, double s)
{
    register double a0 __asm__("xmm0") = x;
    register double a1 __asm__("xmm1") = s;
    __asm__ volatile ("" : "+t" (a0), "+t" (a1));   /* 只是把值钉在 xmm0/xmm1 */
    return a0 * 2.0 + a1;
}

/* ---------------------------------------------------------------------------
 * 4b) 直接用内联汇编调用 NASM 的整数函数
 *     "S" 约束 = rsi，"D" = rdi，"a" = rax。
 *     这里先显式写出寄存器搬运，再 call —— 每个操作数都算得出确切位置，
 *     不存在「输出寄存器被调用破坏」的问题。
 * ------------------------------------------------------------------------- */
extern long asm_double_int(long x);                 /* 由 lc_inline.asm 提供 */

static long call_asm_double_int(long x)
{
    long ret;
    __asm__ volatile (
        "movq  %1, %%rdi\n\t"       /* 第 1 个整数参数放 rdi */
        "call  asm_double_int\n\t"
        "movq  %%rax, %0\n\t"       /* 返回值在 rax */
        : "=r" (ret)
        : "r"  (x)
        : "rdi", "rax", "rcx", "rdx", "rsi", "r8", "r9", "r10", "r11",
          "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6",
          "xmm7", "xmm8", "xmm9", "xmm10", "xmm11", "xmm12", "xmm13",
          "xmm14", "xmm15", "cc", "memory"
    );
    return ret;
}

/* ---------------------------------------------------------------------------
 * 5) 跨文件调用 NASM 里的 asm_flag（它内部会调用 libc 的 printf）
 * ------------------------------------------------------------------------- */
extern void asm_flag(long n);

int main(void)
{
    printf("1. add_two(40)          = %ld\n", add_two(40));           /* 42 */
    printf("2. double_it(21)        = %ld\n", double_it(21));         /* 42 */
    printf("3. fma_like(2.0)        = %.6f\n", fma_like(2.0));        /* 12.0 */
    printf("4. 汇编 scale_shift(5.0, 1.5) = %.6f\n",
           scale_shift_native(5.0, 1.5));                              /* 11.5 */
    printf("5. 汇编 asm_double_int(21)    = %ld\n",
           call_asm_double_int(21));                                   /* 42 */

    asm_flag(7);                    /* 汇编函数反过来调用 printf */

    printf("7. 内联汇编演示结束\n");
    return 0;
}
```

```asm
; lc_inline.asm 里被 C 调用的两个函数

; scale_shift(x, s) -> x * 2 + s
; 入参：xmm0 = x, xmm1 = s；返回：xmm0
scale_shift:
    addsd xmm0, xmm0                    ; xmm0 = 2x
    addsd xmm0, xmm1                    ; xmm0 = 2x + s
    ret

; asm_double_int(n) -> 2n
; 入参：rdi = n；返回：rax = 2n
asm_double_int:
    lea  rax, [rdi + rdi]               ; rax = rdi * 2（lea 比 imul 更短）
    ret

; asm_flag(n) —— 汇编函数里调用 C 库的 printf
asm_flag:
    push rbp
    mov  rbp, rsp
    sub  rsp, 16                        ; 两个 8 字节栈槽：n 和填充
    mov  [rbp-8], rdi                   ; 保存 n

    lea  rdi, [rel f_flag1]             ; 第 1 个参数：格式串
    mov  rsi, [rbp-8]                   ; 第 2 个参数：n（%ld 需要整数参数）
    xor  eax, eax                       ; 没用向量寄存器
    call printf
    ...
    leave
    ret
```

**AT&T 与 Intel 语法的五条差异**

| # | 规则 | AT&T（gcc 内联汇编默认） | Intel（NASM 常用） |
|---|---|---|---|
| 1 | 操作数顺序 | `movl %eax, %ebx`（源 → 目的） | `mov ebx, eax`（目的 ← 源） |
| 2 | 寄存器前缀 | 必须写 `%`，内联汇编里自己的寄存器写 `%%` | 不写前缀 |
| 3 | 立即数前缀 | `$2` | `2` |
| 4 | 数据宽度 | 助记符后缀 `b/w/l/q`：`addl`、`addq` | 靠操作数大小推断：`add eax, ebx` |
| 5 | 内存操作数 | `(%rdi)`、`8(%rdi,%rax,4)` | `[rdi]`、`[rdi+rax*4+8]` |

`lc_inline.asm` 用 NASM 写（Intel 语法），`lc_inline.c` 的内联汇编用 AT&T 语法，
两个文件放在一起正好能对照着看。

## 编译与运行

```bash
cd lesson12
make                 # 编译 lc_inline.asm 和 macro_demo.asm
./macro_demo         # 宏演示
./lc_inline          # NASM 版对照程序（自带 main）
make test            # 自动跑上面两个，并额外编译混合程序
```

`make all` 只处理 `*.asm`。带 C 文件的例子按项目约定要自己写命令：

```bash
nasm -f elf64 -g -F dwarf -I ../include -o lc_inline.o lc_inline.asm
gcc -no-pie -Wall -O0 -o lc_inline_c lc_inline.c lc_inline.o
./lc_inline_c
```

`./macro_demo` 的期望输出：

```text
=== NASM 宏 / 条件汇编演示 ===
本文件由第 12 课的宏生成
--- 1. %define：汇编期常量，不占空间 ---
12.0
--- 2. %macro：带参数的宏 ---
本文件由第 12 课的宏生成PRINT_LINE 宏：字符串内嵌在代码段，靠 jmp 跳过
换个参数就换一段文本，标签由 %% 保证唯一
SHOW_STR_INFO：长度是汇编期用 %strlen 算出来的
--- 3. %rep：源码重复 ---
------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------
--- 4. %ifdef / %if / %ifidn：条件汇编 ---
[DEBUG] DEBUG 已定义，这段代码真的被汇编进来了
BUF_SIZE >= 32：走大缓冲分支
%ifidn 判断 VERSION_STR 与 "12.0" 文本相同
--- 5. 宏叠宏：PRINT_NUM 只是把参数转发给一个例程 ---
PRINT_NUM 输出：123456
12
宏演示结束
```

> 第 2 行 `本文件由第 12 课的宏生成PRINT_LINE 宏…` 是故意连在一起的：
> 前面那段用 `io_print`（不带换行）输出，`SYS_WRITE3` 紧接着写，
> 正好演示「宏只是把参数交给 `syscall`」。

`./lc_inline_c` 的期望输出：

```text
1. add_two(40)          = 42
2. double_it(21)        = 42
3. fma_like(2.0)        = 12.000000
4. 汇编 scale_shift(5.0, 1.5) = 11.500000
5. 汇编 asm_double_int(21)    = 42
汇编函数 asm_flag(7) 通过 printf 打印:
  [asm] n = 7
7. 内联汇编演示结束
```

## 动手练习

1. 把 `%define VERSION_MAJOR 12` 改成 `13`，重新 `make`，观察
   `本文件由第 13 课的宏生成` 和最后那个 `13`。这证明 `%define`
   就是文本替换。

2. 把 `%define BUF_SIZE 64` 改成 `BUF_SIZE 16`，重新编译运行。
   解释为什么输出从「BUF_SIZE >= 32」变成了「BUF_SIZE < 32」，
   并用 `objdump -s -j .data macro_demo | grep -i small` 之类的方法
   验证另一段文字确实不在可执行文件里。

3. 注释掉 `%define DEBUG` 那一行，重新 `make`，确认 Debug 文字变了。
   再用 `strings macro_demo | grep DEBUG` 看看被排除的那句话是否真的消失了。

4. 给 `macro_demo.asm` 加一个 `PRINT_PAIR` 宏，接受两个字符串参数，
   打印成 `a=b` 的形式（提示：先 `PRINT` 第一个，再输出 `=`
   再 `PRINT` 第二个；两个参数用 `%1`、`%2` 取）。

5. 用 `%rep` 生成一个「乘法表」：在汇编期把一个数组的 5 个元素
   各乘一个常量，运行期用 `io_print_uint` 打印。
   提示：`%assign` 可以做汇编期算术；如果真的想在运行期算，
   就用普通循环，不要用 `%rep`。

6. 给 `lc_inline.c` 加一个 `sum_first_n` 的内联汇编函数，
   用循环（`%%loop` 这个写法）把 1..n 加起来。
   提示：内联汇编里写循环要用 `1:` / `2:` 这种**数字标签**，
   `jnz 1b`（backward）或 `jnz 2f`（forward），比 `%%` 标签更常用。

7. （进阶）把 `lc_inline.c` 里 `call_asm_double_int` 的 clobber 列表
   故意删掉 `"rdi"`，想想为什么现在还能跑、什么情况下会出问题。
   提示：gcc 现在挑的输出寄存器碰巧不是 `rdi`，换个 `-O2` 或改改代码
   就可能踩到。

## 常见坑

1. **以为 `%rep` 是循环**：`%rep 3` 是「把这段源码抄 3 遍」。
   如果被抄的代码里定义了标签，三次展开会**重复定义同一个标签**，
   汇编直接报错。解决办法是用 `%%` 定义宏内部的局部标签。

2. **`%macro` 的参数是文本，不是值**：`%1` 可以是寄存器名、标签、数字，
   甚至一整段表达式。想让它在 `db` 里当字符串用，得先用 `%defstr`。

3. **`%if` 和 `if` 混用**：`%if` 是汇编期判断（只吃常量），
   `if` 是运行时指令（要吃 `cmp` 的结果）。写 `%if rax > 0` 一定报错。

4. **`.data` 里的 `%` 不要乱写**：`%define`、`%macro` 这种只能出现在
   行首（前面可以有空白）。字符串里的 `%` 完全安全，
   写 `fmt db "50%%"` 也一样没问题 —— 只有行首的 `%` 才被当成指令。

5. **宏展开的代码量爆炸**：宏是「复制粘贴」，一个 50 行的宏展开 100 次
   就是 5000 行机器码。需要重复使用又在意体积时，
   还是写成一个真正的函数用 `call` 调用。

6. **内联汇编忘写 `volatile` 被优化掉**：没有输出的内联汇编
   （比如纯 `syscall`）如果不加 `volatile`，`-O2` 下可能整段被删掉。

7. **AT&T 和 Intel 的操作数顺序搞反**：`movl %eax, %ebx` 是把 `eax`
   搬进 `ebx`；写成 Intel 的直觉 `mov ebx, eax` 是同一个意思，
   但两种语法不能混着写。在内联汇编里想搬 `%rax`，写 `%%rax`。

8. **`call` 之后忘了返回值的寄存器**：C 调用约定里整数返回值在 `rax`、
   浮点在 `xmm0`。内联汇编里 `call` 完必须显式从 `rax`/`xmm0` 取，
   而且 `call` 会破坏所有调用者保存寄存器，clobber 列表要写全，
   否则 gcc 可能把某个你想保留的值放在被破坏的寄存器里。

9. **`register double a __asm__("xmm0")` 不是万能的**：它只是「请求」，
   gcc 在寄存器不够或优化后可能不听。想强制对应，还是显式写
   `movsd`/`movq` 更可靠。

10. **混合编译时 Makefile 不管 C 文件**：`make all` 只编译 `*.asm`。
    带 C 的例子要在 README/test.sh 里给显式 `gcc -no-pie ... *.c *.o` 命令，
    同时保证 `lc_*.asm` 单独也能被 `gcc -no-pie` 链接成功
    （所以 `lc_inline.asm` 自己必须带一个 `main`）。

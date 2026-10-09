# 第 13 课：与 C 互调、编译混合、性能优化

## 一、本课目标

* 用汇编实现几个函数，让 **C 程序直接调用**（遵循 System V AMD64 调用约定）。
* 掌握 C 与汇编**混合编译**的完整流程（`nasm` 出 `.o`，`gcc -no-pie` 链接，禁止出现 duplicate symbol `_start`）。
* 学会用 `gcc -S`、`objdump -d -M intel`、`nm` 观察“编译器到底生成了什么”。
* 用 SSE2 写一个 SIMD 版本，和朴素版本对比，说清**为什么快**。
* 认识弱符号（weak symbol）`global main:weak`：让同一个 `.asm` 既能单独链接成可执行文件，又能被 C 的 `main` 顶替。

本课文件：

| 文件 | 风格 | 说明 |
|---|---|---|
| `lc_asm_lib.asm` | libc 风格（`lc_` 前缀 + `main`） | 导出 `asm_add` / `asm_sum_array` / `asm_hypot` / `asm_strlen` / `asm_dot`，末尾有一个弱符号自测 `main` |
| `c_driver.c` | C | `main` 里调用上面 5 个汇编函数并 `printf` 验证 |
| `lc_opt.asm` | libc 风格 | 同一个任务两种写法：朴素循环 vs SSE2，附 `-DMEASURE` 计时 |
| `test.sh` | — | 显式编译混合程序、运行、比对输出（不调用 make） |

## 二、新概念 / 新指令

| 概念 / 指令 | 一句话说明 | 小例子 |
|---|---|---|
| `extern` | 引用别的目标文件里的符号，nasm 必须显式声明 | `extern printf` |
| `global sym:function` | 导出符号并标注类型为函数 | `global asm_add:function` |
| `global sym:weak` | 导出**弱**符号：没有强符号时才生效 | `global main:weak` |
| `-no-pie` | 关掉位置无关可执行文件，回到传统固定基址链接 | `gcc -no-pie -o mix c_driver.c lib.o` |
| 整数参数寄存器 | 第 1~6 个整数/指针参数 | `rdi rsi rdx rcx r8 r9` |
| 浮点参数寄存器 | 第 1~8 个 `double` 参数 | `xmm0` `xmm1` … |
| `al` / `eax` 传向量个数 | 调用**变参函数**前，`al` = 用到的向量寄存器个数 | 不用浮点：`xor eax, eax`；用了 `xmm0`：`mov eax, 1` |
| 被调用者保存 | 改了必须还原的寄存器 | `rbx rbp r12–r15` |
| `paddq` | SSE2：两个 128 位寄存器按 64 位整数逐元素相加 | `paddq xmm0, xmm1` |
| `pcmpeqb` | SSE2：逐字节比较，相等给 `0xFF`，否则 `0x00` | `pcmpeqb xmm1, xmm2` |
| `pand` | SSE2：按位与（把 `0xFF` 掩成 `0x01` 再求和） | `pand xmm1, xmm4` |
| `psadbw` | SSE2：两个 8 字节半区各求“差的绝对值之和” | `psadbw xmm1, xmm3` |
| `movdqa` / `movdqu` | 对齐（16 字节）/ 非对齐的 128 位加载 | `movdqa xmm2, [rel xmm_a]` |
| `movhlps` | 把高 64 位搬到低 64 位（水平求和用） | `movhlps xmm1, xmm0` |
| `movq rax, xmm0` | 把 xmm 的低 64 位搬到通用寄存器 | `movq rax, xmm0` |
| `-DMEASURE` | nasm 的条件汇编开关，本课用它选择是否编译计时代码 | `nasm ... -DMEASURE ...` |

## 三、示例一：`lc_asm_lib.asm` —— 用汇编写一个能被 C 调用的库

### 3.1 约定先写在纸上

| 问题 | 答案 |
|---|---|
| 整数参数放哪 | `rdi, rsi, rdx, rcx, r8, r9` |
| 浮点参数放哪 | `xmm0 … xmm7` |
| 返回值 | 整数 `rax`，浮点 `xmm0` |
| 我可以随便破坏哪些寄存器 | `rax rcx rdx rsi rdi r8 r9 r10 r11` + 全部 `xmm`（调用者保存） |
| 我改了必须还原哪些寄存器 | `rbx rbp r12 r13 r14 r15`（被调用者保存） |
| `call` 时栈有什么要求 | 执行 `call` 的那一刻 `rsp` 必须是 16 的倍数 |

本文件里所有函数**只用调用者保存寄存器**（`rax/rcx/rdx/xmm0/xmm1`），所以一条 `push`/`pop` 都不用写——这也是“写库函数”的常规做法：能不碰被调用者保存寄存器就不碰。

### 3.2 完整代码（库函数部分）

```asm
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

; long asm_add(long a, long b)
asm_add:
    lea rax, [rdi + rsi]    ; 一条指令算完：rax = rdi + rsi，不碰内存、不碰标志位
    ret

; long asm_sum_array(const long *arr, long n)
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

; double asm_hypot(double x, double y)
asm_hypot:
    mulsd xmm0, xmm0        ; xmm0 = x*x
    mulsd xmm1, xmm1        ; xmm1 = y*y
    addsd xmm0, xmm1        ; xmm0 = x*x + y*y
    sqrtsd xmm0, xmm0       ; xmm0 = sqrt(xmm0)；sqrtsd 是“目标 = 源开方”
    ret

; long asm_strlen(const char *s)
asm_strlen:
    xor eax, eax
.loop:
    cmp byte [rdi + rax], 0 ; 一次比较一个字节
    je .done
    inc rax
    jmp .loop
.done:
    ret

; double asm_dot(const double *a, const double *b, long n)
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
```

文件结尾还有一段 `%ifndef NO_MAIN … %endif` 包着的自测 `main`（3.4 节解释它为什么存在）。

### 3.3 逐段解释

**`extern printf`**：NASM 不会去猜一个没见过的符号，你得显式告诉它“这个符号在别的目标文件里”。不写就报
`error: symbol 'printf' not defined`。

**`global asm_add:function`**：`global` 让符号对链接器可见（相当于 C 的“非 static”）；`:function` 只是把它标成 STT_FUNC 类型，方便调试器和 `nm` 认出来。

**`lea rax, [rdi + rsi]`**：`lea` 的名字叫“加载有效地址”，但地址计算本质就是加法，所以常被拿来当**不改变标志位**的加法用。注意 `lea` 不会写标志位，`add` 会——这是它们最实用的区别。

**`add rax, [rdi + rcx*8]`**：`rdi` 是数组首地址，`rcx` 是下标，×8 是因为每个元素 8 字节。这条指令一次读 8 字节到 `rax`。

**`jb` 而不是 `jle`**：`n <= 0` 已经在前面用 `jle .done` 排除了，循环里是 `i < n`，所以用无符号的 `jb`（below）。

**浮点参数走 `xmm`**：`asm_hypot(3.0, 4.0)` 编译后 C 侧会把 3.0 放 `xmm0`、4.0 放 `xmm1`，我们直接算 `sqrt(x*x+y*y)`，结果留在 `xmm0` 返回即可。注意 `sqrtsd xmm0, xmm0` 的语义是“目标 = 源开方”，源和目标可以是同一个寄存器。

**`mulsd xmm1, [rsi + rcx*8]`**：SSE 指令允许第二个操作数来自内存，一条指令完成“取数 + 乘”，比先 `movsd` 到寄存器再乘少一条指令。

### 3.4 单独链接 vs 混合链接：`global main:weak`

`make all` 会用规则 `lc_%: lc_%.asm` 把 `lc_asm_lib.asm` 单独链接成可执行文件：

```bash
nasm -f elf64 -g -F dwarf -I ../include -o lc_asm_lib.o lc_asm_lib.asm
gcc -no-pie -o lc_asm_lib lc_asm_lib.o
./lc_asm_lib
```

输出：

```text
=== lc_asm_lib 自测（弱符号 main）===
asm_add(2,3)        = 5
asm_sum_array(nums) = 36
asm_hypot(3,4)      = 5.000000
asm_strlen(hello)  = 5
asm_dot(a,b)        = 32.000000
```

问题来了：`gcc -no-pie` 会链入 `crt1.o`，它**要求存在 `main`**。所以这个文件必须自己带一个 `main`；
可一旦和 `c_driver.c` 一起链接，两个 `main` 又会 `duplicate symbol`。

解法就是**弱符号**：`global main:weak` 声明的是“弱定义”，链接器优先用强定义。验证一下（符号地址随工具链版本可能略有不同，`W` 和 `T` 是关键）：

```bash
nasm -f elf64 -g -F dwarf -o lib.o lc_asm_lib.asm
nm lib.o | grep -i ' main'
# 000000000000005c W main        ← W = weak

gcc -no-pie -o mix c_driver.c lib.o
nm mix | grep -w main
# 0000000000401126 T main        ← T = 强符号，来自 c_driver.c
```

* 单独链接：没有别的 `main`，弱符号 `main` 就顶上，`crt1.o` 能找到入口，`./lc_asm_lib` 正常跑；
* 和 `c_driver.c` 链接：C 的 `main` 是强符号，弱符号让位，**不会报重复定义**。

如果你更希望“汇编文件里干脆没有 main”，可以用条件汇编把它关掉：

```bash
nasm -f elf64 -g -F dwarf -DNO_MAIN -o lc_asm_lib.o lc_asm_lib.asm
gcc -no-pie -o mix c_driver.c lc_asm_lib.o
```

`test.sh` 两条路都会测（`mix` 和 `mix_nomain`）。

## 四、示例二：`c_driver.c`

```c
#include <stdio.h>

/* 汇编里用 global 导出的符号，在 C 里用 extern 声明。 */
extern long   asm_add(long a, long b);
extern long   asm_sum_array(const long *arr, long n);
extern double asm_hypot(double x, double y);
extern long   asm_strlen(const char *s);
extern double asm_dot(const double *a, const double *b, long n);

int main(void)
{
    long   nums[8] = {1, 2, 3, 4, 5, 6, 7, 8};
    double a[3] = {1.0, 2.0, 3.0};
    double b[3] = {4.0, 5.0, 6.0};
    const char *s = "hello";

    printf("asm_add(2,3)        = %ld\n", asm_add(2, 3));
    printf("asm_sum_array(nums) = %ld\n", asm_sum_array(nums, 8));
    printf("asm_hypot(3,4)      = %f\n", asm_hypot(3.0, 4.0));
    printf("asm_strlen(%s)  = %ld\n", s, asm_strlen(s));
    printf("asm_dot(a,b)        = %f\n", asm_dot(a, b, 3));

    return 0;
}
```

C 侧只要 `extern` 声明正确，完全不用关心它是 C 写的还是汇编写的——链接器只看符号名。
**类型必须和汇编里的实现一致**：`asm_hypot` 声明成 `double(double,double)`，汇编里就必须从 `xmm0/xmm1` 读、往 `xmm0` 写；如果 C 原型写成 `long asm_hypot(long,long)`，参数就会跑进 `rdi/rsi`，结果一定是错的。

## 五、混合编译与运行

```bash
# 1) 汇编 → 目标文件（-g -F dwarf 让 gdb 能对上源码行号）
nasm -f elf64 -g -F dwarf -o lc_asm_lib.o lc_asm_lib.asm
# 2) C + 汇编一起链接（必须 -no-pie）
gcc -no-pie -o mix c_driver.c lc_asm_lib.o
# 3) 运行
./mix
```

写成一行的等价形式：

```bash
nasm -f elf64 -g -F dwarf -o lc_asm_lib.o lc_asm_lib.asm && gcc -no-pie -o mix c_driver.c lc_asm_lib.o
```

输出：

```text
asm_add(2,3)        = 5
asm_sum_array(nums) = 36
asm_hypot(3,4)      = 5.000000
asm_strlen(hello)  = 5
asm_dot(a,b)        = 32.000000
```

对拍一下：`./lc_asm_lib` 的自测 `main` 打印的是同样 5 个数字（多一行标题）。
两个不同的 `main`、同一份汇编库，输出一致，说明符号和调用约定都对上了。

**为什么必须 `-no-pie`？** 本教程统一用 `-no-pie`：这样程序加载地址固定，`nasm` 手写的绝对/相对寻址都好推理，和 `nasm + ld` 的写法保持一致。默认的 PIE 会把程序放到随机地址，手写汇编里如果出现绝对地址假设就会失效。

## 六、看看编译器生成的汇编：`-S` 与 `objdump -d`

**1) 让 GCC 输出它自己生成的汇编**（`-masm=intel` 输出 Intel 语法，和我们平时写的一致）：

```bash
cat > /tmp/o2.c <<'EOF'
long c_sum_array(const long *a, long n) {
    long s = 0;
    for (long i = 0; i < n; i++) s += a[i];
    return s;
}
EOF

gcc -O2 -S -masm=intel -o - /tmp/o2.c
```

GCC 14 在 `-O2` 下生成的循环（节选，省掉了 `.p2align` 对齐伪指令）：

```asm
c_sum_array:
	test	rsi, rsi
	jle	.L4
	lea	rdx, [rdi+rsi*8]
	xor	eax, eax
.L3:
	add	rax, QWORD PTR [rdi]
	add	rdi, 8
	cmp	rdi, rdx
	jne	.L3
	ret
```

和我们的手写版本几乎一样（连“用指针走到末尾而不是用下标比较”的优化都做了）。再试一次：

```bash
gcc -O3 -march=native -S -masm=intel -o - /tmp/o2.c
```

这次 GCC 会**自动向量化**，出现 `vpaddq ymm0, ymm0, YMMWORD PTR [rax]` 这样的 AVX2 指令——这正是第 11 课讲 SIMD 的动机：让编译器替你向量化，或者像本课第七节那样自己动手。

**2) 反汇编目标文件 / 可执行文件**：

```bash
objdump -d -M intel lc_asm_lib.o
```

节选（真实输出）：

```text
0000000000000000 <asm_add>:
   0:	48 8d 04 37          	lea    rax,[rdi+rsi*1]
   4:	c3                   	ret

000000000000001b <asm_hypot>:
  1b:	f2 0f 59 c0          	mulsd  xmm0,xmm0
  1f:	f2 0f 59 c9          	mulsd  xmm1,xmm1
  23:	f2 0f 58 c1          	addsd  xmm0,xmm1
  27:	f2 0f 51 c0          	sqrtsd xmm0,xmm0
  2b:	c3                   	ret
```

几个观察点：

* `lea rax,[rdi+rsi*1]` —— objdump 会把比例写成显式的 `*1`，别以为是另一条指令；
* 前面的 `48` 是 REX.W 前缀，表示 64 位操作；`f2` 是 SSE2 双精度前缀；
* 想看“汇编和源码行怎么对应”的完整流程，用 `objdump -d -M intel -l mix`（`-l` 会带行号），或者直接用 gdb（第 14 课）。

## 七、示例三：`lc_opt.asm` —— 朴素 vs 优化，为什么快

两个任务，各写两版：

| 任务 | 朴素版 | 优化版 | 为什么快 |
|---|---|---|---|
| 求 1024 个 `int64` 的和 | 每轮 1 个元素 | 每轮 2 个元素（`movdqu` + `paddq`） | 循环次数减半 → 循环控制（`inc/cmp/jb`）和分支预测压力减半；一次读 16 字节 |
| 统计 4096 字节里 `'a'` 的个数 | 每字节比较 + 条件跳转 | 16 字节一次 `pcmpeqb` | 每字节一次不可预测的分支变成每 16 字节 5 条顺序指令 |

### 7.1 朴素的求和 / 统计

```asm
; long sum_naive(const long *arr, long n)
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

; long count_a_naive(const char *s, long n)
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
```

### 7.2 SIMD 求和：一次两个 `int64`

```asm
; long sum_simd(const long *arr, long n)
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
```

* `paddq` 是“按 64 位整数逐元素相加”，两个 64 位通道互不干扰，所以不会因为进位串扰出错；
* 最后要把 xmm 里的**两个** 64 位计数器水平合并成一个标量：`movhlps` 搬高 64 位，再 `paddq`；
* 元素个数是奇数时尾巴单独处理——SIMD 代码永远要处理“不满一整块”的尾部。

### 7.3 SIMD 统计字符

```asm
; long count_a_simd(const char *s, long n)
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
```

这段的核心是三条指令：

1. `pcmpeqb`：一条指令同时比较 16 个字节，相等的位置变成 `0xFF`；
2. `pand xmm4`（xmm4 = 16 个 `0x01`）：把 `0xFF` 变成 `0x01`，这样后面求和才是“个数”而不是“255 × 个数”；
3. `psadbw`：把 128 位分成两个 8 字节半区，各自求“差的绝对值之和”——和 0 相减再取绝对值，正好就是这一块的字节和。**注意它把两个半区的结果分别放在低 64 位和高 64 位**，所以要 `psrldq xmm0, 8` 把高半区挪下来再加一次，否则答案会正好少一半。

`xmm_a` 用 `movdqa`（要求 16 字节对齐），所以数据段里写了 `align 16`；从字符串加载用 `movdqu`（不要求对齐），因为字符串的地址我们控制不了。

### 7.4 运行与实测

```bash
make            # 生成 lc_opt
./lc_opt
```

输出是**确定的**（可以让脚本比对）：

```text
naive  sum        = 50800
simd   sum        = 50800
naive  count 'a'  = 158
simd   count 'a'  = 158
check  : results match (1)
```

两个数字手算就能验证：

* 数组 `arr[i] = i % 100 + 1`，1024 个元素 = 10 轮完整的 `1+2+…+100 = 5050`，加上 `1+…+24 = 300`，合计 `10*5050 + 300 = 50800`；
* 字符串每 26 字节一个 `'a'`，`26*157 = 4082` 字节，再补 1 个 `'a'` 和 13 个 `'b'` 凑满 4096 → `157 + 1 = 158`。

想看真实耗时（数值每次都不同，所以默认不编译这段）：

```bash
nasm -f elf64 -g -F dwarf -DMEASURE -o lc_opt_m.o lc_opt.asm
gcc -no-pie -o lc_opt_m lc_opt_m.o
./lc_opt_m
```

`-DMEASURE` 会打开条件汇编里的计时块（用 `clock_gettime` 系统调用读 `CLOCK_MONOTONIC`），某次运行结果：

```text
measure: naive sum   = 59000916 ns      ← 2 万次朴素求和
measure: simd  sum   = 23656848 ns      ← 2 万次 SIMD 求和
measure: naive count = 101700526 ns     ← 5 千次朴素统计
measure: simd  count = 3342032 ns       ← 5 千次 SIMD 统计
```

即求和快约 2.5 倍、字符统计快约 30 倍。字符统计的差距特别大，是因为朴素版**每读一个字节就有一次条件跳转**，而随机数据里的分支预测器几乎猜不中；SIMD 版把 16 个字节压成 5 条顺序指令，几乎没有分支。

> 记住一句话：SIMD 的收益不只是“一次算更多”，更是“**少分支、少循环控制**”。

## 八、动手练习

1. 给 `lc_asm_lib.asm` 加一个 `asm_add3(long,long,long)`（第三个参数在 `rdx`），在 `c_driver.c` 里调用并打印。
2. 把 `asm_hypot` 改成 `float asm_hypotf(float,float)`（`float` 参数同样走 `xmm`，但用 `mulss/addss/sqrtss`，返回 `xmm0` 的低 32 位）。C 侧原型要改成 `extern float asm_hypotf(float, float);`。
3. 把 `asm_sum_array` 改成“一次加 4 个元素”的版本（提示：`paddq` 处理两个，想一次四个可以用两个 xmm 累加器，或者嵌套展开）。
4. 让 `lc_opt.asm` 的 `sum_simd` 支持“每轮 4 个元素”（`n/4` 个块，`n%4` 的尾巴用标量补），再用 `-DMEASURE` 比较三种版本的耗时。
5. 用 `gcc -O3 -march=native -S -masm=intel` 看看 GCC 给你的 C 求和函数生成了什么，和 `sum_simd` 比一比谁的指令更少。
6. 把 `lc_asm_lib.asm` 里的 `global main:weak` 改成 `global main`，重新 `make`：先看 `make all`（单独链接）能不能过，再手工试混合链接命令，观察 `duplicate symbol 'main'` 报错。（练完记得改回来。）

其中第 3、4 题的思路：先用 `n >> 2` 算出整块个数，块内累加到一个或多个 xmm，最后水平求和；尾部用 `n & 3` 求个数，循环用标量补。第 6 题想说明的是：`weak` 的作用就是“**有强的就让位**”，去掉它两个 `main` 必然冲突。

## 九、常见坑

1. **忘了 `extern printf`**：NASM 立刻报 `symbol 'printf' not defined`。凡是调用 libc 函数，都要在文件开头 `extern`。
2. **`al` 忘了清零/置位**：`printf` 是变参函数，调用前 `al` 必须等于“用到的向量寄存器个数”。不用浮点就 `xor eax, eax`；把 `double` 放在 `xmm0` 里当参数传就 `mov eax, 1`。写错的表现是打印出 `0.000000` 或者直接崩。
3. **`call` 时 `rsp` 不是 16 的倍数**：函数入口要 `push rbp; mov rbp, rsp`（这样 rsp 就是 16 的倍数），返回 `leave; ret`。中间临时 `push` 了奇数个 8 字节要补回来，否则 `printf` 里的 `movaps` 会因未对齐而崩（第 14 课会看到这种崩溃）。
4. **`sqrtsd` 的方向**：`sqrtsd xmm0, xmm1` 是 `xmm0 = sqrt(xmm1)`，目标在左。同理 `movhlps`、`psrldq` 的目标都在左。
5. **`psadbw` 只水平合并了一半**：它把两个 8 字节半区的结果放在低/高 64 位，忘了 `psrldq xmm0, 8` 再相加，答案正好少一半——这个 bug 很难从结果上直接看出来（如果你知道正确值就能一眼发现）。
6. **`movdqa` 用在没对齐的地址上**：会触发通用保护错（段错误）。数据段里配上 `align 16`，或者干脆用 `movdqu`（稍慢但安全）。
7. **`mov [rax], rbx` 这类指令缺大小**：只要两边都能推出大小就没问题，但 `mov [rax], 1` 必须写 `mov byte [rax], 1`（或 `dword`/`qword`），否则 NASM 报 `operation size not specified`。
8. **`extern` 的 C 原型写错**：`double` 写成 `long`，参数就会进 `rdi/rsi` 而不是 `xmm0/xmm1`。汇编这边不会报错，只是结果离谱——这类 bug 只能靠“声明和实现对照检查”发现。

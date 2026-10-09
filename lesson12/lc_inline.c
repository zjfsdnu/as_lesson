/* ===========================================================================
 * 第 12 课示例 2 的 C 部分：lc_inline.c
 *   GCC 内联汇编（inline assembly）入门
 *
 *   注意：内联汇编是 **C 语言**的特性，NASM 里没有 __asm__ 这种东西。
 *   本文件的角色是「C 驱动」：里面用 __asm__ volatile 写几个小函数，
 *   再调用同目录 lc_inline.asm（NASM）提供的 asm_flag / scale_shift，
 *   演示 C 与汇编互相调用，并用 printf 验证结果。
 *
 * 编译运行（要把同目录的 lc_inline.o 一起链进来）：
 *   nasm -f elf64 -g -F dwarf -I ../include -o lc_inline.o lc_inline.asm
 *   gcc -no-pie -Wall -O0 -o lc_inline_c lc_inline.c lc_inline.o
 *   ./lc_inline_c
 *
 * ---------------------------------------------------------------------------
 * 五条最基本的 AT&T / Intel 语法差异（gcc 内联汇编默认 AT&T）：
 *
 *   1. 操作数顺序反过来：AT&T 是「源在前、目的在后」
 *        AT&T : movl %eax, %ebx      （ebx = eax）
 *        Intel: mov  ebx, eax       （ebx = eax）
 *   2. 寄存器要加 %，内联汇编里自己的寄存器要写两个 %
 *        GCC 里的 %0/%1 是操作数占位符，所以裸寄存器必须写 %%rax
 *   3. 立即数要加 $：AT&T 的 $2 等于 Intel 的 2
 *   4. 助记符后缀表示数据宽度：b=8 位, w=16 位, l=32 位, q=64 位
 *        addl %eax, %ebx   /  addq %rax, %rbx
 *   5. 内存操作数带括号和段前缀：AT&T 的 (%rdi) 等于 Intel 的 [rdi]
 * ========================================================================= */

#include <stdio.h>

/* ---------------------------------------------------------------------------
 * 1) add_two(x) -> x + 2
 *    "r"  = 让 gcc 任选一个通用寄存器；"=r" 是只写输出
 *    %0 是第 1 个操作数（输出），%1 是第 2 个（输入）
 *    AT&T 的 addl %1, %0 等于 Intel 的 add %0, %1，即 %0 = %0 + %1
 * ------------------------------------------------------------------------- */
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
static long double_it(long x)
{
    long out;
    __asm__ volatile (
        "movq  %1, %0\n\t"
        "addq  %1, %0\n\t"      /* out = x + x */
        : "=r" (out)
        : "r"  (x)
        : "cc"
    );
    return out;
}

/* ---------------------------------------------------------------------------
 * 3) fma_like(v) -> 3 * v * v
 *    约束 "t" 表示「任选一个 xmm 寄存器」，用于 double/float 运算
 *    addsd/mulsd 是**标量**双精度指令（只算低 64 位那个 double）
 * ------------------------------------------------------------------------- */
static double fma_like(double v)
{
    double out;
    __asm__ (
        "movsd %1, %0\n\t"      /* out = v */
        "addsd %1, %0\n\t"      /* out = 2v */
        "addsd %1, %0\n\t"      /* out = 3v */
        "mulsd %1, %0\n\t"      /* out = 3v * v = 3v^2 */
        /* 输出用 "=&x"（early-clobber）：第一条 movsd 在读完输入之前就写了
           输出寄存器。不加 & 的话 gcc 可能让输出和输入共用同一个 xmm，
           第一条 movsd 会先把 v 覆盖掉，结果全错。
           这里用 "=x"（SSE 寄存器类）而不是 "=t"（栈顶寄存器 st0，属于 x87），
           再用 & 让 gcc 另找一个空闲的 xmm。 */
        : "=&x" (out)
        : "x"  (v)
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
    __asm__ volatile ("" : "+x" (a0), "+x" (a1));   /* 只是把值钉在 xmm0/xmm1
                                                       （约束 x = SSE 寄存器；t 是 x87 的 st0，不要混用） */
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

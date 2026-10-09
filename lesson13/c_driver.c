/* ===========================================================================
 * c_driver.c —— C 主程序，调用 lc_asm_lib.asm 里用汇编实现的函数
 *
 * 编译（和汇编目标文件一起，必须 -no-pie）：
 *   nasm -f elf64 -g -F dwarf -o lc_asm_lib.o lc_asm_lib.asm
 *   gcc -no-pie -o mix c_driver.c lc_asm_lib.o
 *   ./mix
 *
 * 为什么必须 -no-pie：
 *   -no-pie 生成“非位置无关”的可执行文件，汇编里直接写 lea rax,[rdi+rsi]
 *   这类绝对/相对寻址都按传统的固定基址链接；而默认的 PIE 会把程序放到
 *   随机地址，汇编里手写的绝对地址（本课虽然没有）就会失效。
 *   教程统一用 -no-pie，和 nasm + ld 的写法保持一致。
 * ===========================================================================
 */

#include <stdio.h>

/* 汇编里用 global 导出的符号，在 C 里用 extern 声明。
 * 类型必须和汇编里的实际实现一致：
 *   asm_add       整数参数 rdi,rsi      → rax
 *   asm_sum_array 指针 rdi + 长度 rsi   → rax
 *   asm_hypot     浮点参数 xmm0,xmm1    → xmm0
 *   asm_strlen    指针 rdi              → rax
 *   asm_dot       两个指针 + 长度       → xmm0
 */
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

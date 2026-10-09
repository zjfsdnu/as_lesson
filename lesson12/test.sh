#!/usr/bin/env bash
# 第 12 课自测：
#   1) 运行宏演示程序，检查输出
#   2) 额外编译「C 内联汇编 + NASM 汇编」的混合程序并运行
#      （make all 只编译 *.asm；带 C 文件的例子按 INSTRUCTOR.md 的约定
#        在本脚本里用显式命令自己编译，不修改 Makefile）
set -u
cd "$(dirname "$0")"
fail=0

check() {
    local name="$1" expected="$2" got
    got=$(./"$name" 2>&1)
    if [ "$got" = "$expected" ]; then
        echo "  [OK] $name"
    else
        echo "  [FAIL] $name"
        printf '    期望:\n%s\n' "$expected" | sed 's/^/      /'
        printf '    实际:\n%s\n' "$got" | sed 's/^/      /'
        fail=1
    fi
}

exp_macro='=== NASM 宏 / 条件汇编演示 ===
本文件由第 12 课的宏生成
--- 1. %define：汇编期常量，不占空间 ---
12.0
--- 2. %macro：带参数的宏 ---
本文件由第 PRINT_LINE 宏：字符串内嵌在代码段，靠 jmp 跳过
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
宏演示结束'

check macro_demo "$exp_macro"

# 单独验证 %define：VERSION_MAJOR 必须展开成 12
got=$(./macro_demo | sed -n '2p')
if [ "$got" = "本文件由第 12 课的宏生成" ]; then
    echo "  [OK] %define VERSION_MAJOR 展开正确"
else
    echo "  [FAIL] %define 展开不对: $got"
    fail=1
fi

# 单独验证条件汇编：BUF_SIZE >= 32 分支被选中
if ./macro_demo | grep -q "BUF_SIZE >= 32"; then
    echo "  [OK] %if BUF_SIZE < 32 选择了正确的分支"
else
    echo "  [FAIL] %if 条件汇编分支不对"
    fail=1
fi

# ---------------------------------------------------------------------------
# 混合编译：lc_inline.c（GCC 内联汇编）+ lc_inline.asm（NASM，提供 asm_flag
# 和 scale_shift）。这一步刻意不用 Makefile 的规则，因为 Makefile 只处理 *.asm。
# ---------------------------------------------------------------------------
echo "  -- 编译 C 内联汇编 + NASM 混合程序 --"
if nasm -f elf64 -g -F dwarf -DNO_MAIN -I ../include -o lc_inline_mix_asm.o lc_inline.asm \
   && gcc -no-pie -Wall -O0 -o lc_inline_c lc_inline.c lc_inline_mix_asm.o; then
    exp_inline='1. add_two(40)          = 42
2. double_it(21)        = 42
3. fma_like(2.0)        = 12.000000
4. 汇编 scale_shift(5.0, 1.5) = 11.500000
5. 汇编 asm_double_int(21)    = 42
汇编函数 asm_flag(7) 通过 printf 打印:
  [asm] n = 7
7. 内联汇编演示结束'
    check lc_inline_c "$exp_inline"
else
    echo "  [FAIL] 混合编译失败（lc_inline.c + lc_inline.asm）"
    fail=1
fi

# ---------------------------------------------------------------------------
# 单独运行纯 NASM 版的 lc_inline（它自己也有 main）
# ---------------------------------------------------------------------------
exp_inline_asm='=== 汇编版对照程序（真正的内联汇编在 lc_inline.c）===
汇编函数 scale_shift(2.0, 0.5) = 4.500000   (期望 4.5)
cvtsi2sd: 42 -> 42.0
汇编函数 asm_flag(99) 通过 printf 打印:
  [asm] n = 99'
check lc_inline "$exp_inline_asm"

# 清理混合编译产生的临时文件（可执行文件 lc_inline_c 保留，方便手动运行）
rm -f lc_inline_mix_asm.o

if [ $fail -eq 0 ]; then
    echo "第 12 课全部通过"
else
    echo "第 12 课存在失败"
fi
exit $fail

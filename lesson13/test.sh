#!/usr/bin/env bash
# ===========================================================================
# 第 13 课自测：与 C 互调、混合编译、性能优化
#
#   * 本课有 C 文件参与链接，所以这里显式调用 nasm / gcc（不调用 make；
#     `make test` 已经先执行过 `make all`，./lc_asm_lib 和 ./lc_opt 已经在了）
#   * 混合编译命令就是 README 里给出的那两条
# ===========================================================================
set -u
cd "$(dirname "$0")"
fail=0

expect_ok() {   # $1=名字 $2=实际输出 $3=期望输出
    if [ "$2" = "$3" ]; then
        echo "  [OK] $1"
    else
        echo "  [FAIL] $1"
        printf '%s\n' "$3" | sed 's/^/    期望: /'
        printf '%s\n' "$2" | sed 's/^/    实际: /'
        fail=1
    fi
}

# C 驱动的期望输出（自测 main 和 c_driver.c 打印的东西一样，只是少了标题行）
expect_driver='asm_add(2,3)        = 5
asm_sum_array(nums) = 36
asm_hypot(3,4)      = 5.000000
asm_strlen(hello)  = 5
asm_dot(a,b)        = 32.000000'

# ---- 1. 汇编库单独链接（弱符号 main 自测）--------------------------------
out=$(./lc_asm_lib 2>&1)
expect='=== lc_asm_lib 自测（弱符号 main）===
asm_add(2,3)        = 5
asm_sum_array(nums) = 36
asm_hypot(3,4)      = 5.000000
asm_strlen(hello)  = 5
asm_dot(a,b)        = 32.000000'
expect_ok "lc_asm_lib（nasm + gcc -no-pie，单独链接）" "$out" "$expect"

# ---- 2. C + 汇编混合编译（README 里给出的命令）----------------------------
echo "  -- nasm -f elf64 -g -F dwarf -o lc_asm_lib.o lc_asm_lib.asm"
echo "  -- gcc -no-pie -o mix c_driver.c lc_asm_lib.o"
if nasm -f elf64 -g -F dwarf -o lc_asm_lib.o lc_asm_lib.asm \
   && gcc -no-pie -o mix c_driver.c lc_asm_lib.o; then
    out=$(./mix)
    expect_ok "mix（C 的 main 调汇编函数）" "$out" "$expect_driver"
else
    echo "  [FAIL] 混合链接失败"
    fail=1
fi

# ---- 3. 用 -DNO_MAIN 去掉弱符号 main，纯函数库照样能和 C 链接 -------------
if nasm -f elf64 -g -F dwarf -DNO_MAIN -o lc_asm_lib_nomain.o lc_asm_lib.asm \
   && gcc -no-pie -o mix_nomain c_driver.c lc_asm_lib_nomain.o; then
    out=$(./mix_nomain)
    expect_ok "mix_nomain（汇编侧没有 main）" "$out" "$expect_driver"
else
    echo "  [FAIL] -DNO_MAIN 版混合链接失败"
    fail=1
fi

# ---- 4. 朴素 vs SIMD 的对比程序（输出是确定的）---------------------------
out=$(./lc_opt)
expect="naive  sum        = 50800
simd   sum        = 50800
naive  count 'a'  = 158
simd   count 'a'  = 158
check  : results match (1)"
expect_ok "lc_opt（两种实现结果一致）" "$out" "$expect"

# ---- 5. 清理测试过程中产生的文件（不动 make all 生成的可执行文件）--------
rm -f lc_asm_lib.o lc_asm_lib_nomain.o mix mix_nomain

[ $fail -eq 0 ] && echo "第 13 课全部通过" || echo "第 13 课存在失败"
exit $fail

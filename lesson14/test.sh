#!/usr/bin/env bash
# ===========================================================================
# 第 14 课自测：调试靶子（故意写错的版本）+ hexdump
#
#   make test 已经先 `make all`，所以 ./debug_target 和 ./hexdump 必定存在；
#   这里只额外编译一次“有 bug 的版本”（README 里的 -DBUGGY_VERSION 命令）。
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

# ---- 1. 默认构建：修好的版本 ---------------------------------------------
out=$(./debug_target)
expect='count = 8
sum   = 4294967296
avg   = 536870912'
expect_ok "debug_target（修好的版本）" "$out" "$expect"

# ---- 2. 打开两个 bug 的版本：能跑完，但结果是错的 -------------------------
echo "  -- nasm -DBUGGY_VERSION ... && ld -o debug_target_buggy debug_target.o"
if nasm -f elf64 -g -F dwarf -DBUGGY_VERSION -I ../include -o debug_target.o debug_target.asm \
   && ld -o debug_target_buggy debug_target.o; then
    out=$(./debug_target_buggy)
    expect='count = 9
sum   = 1073741824
avg   = 119304647'
    expect_ok "debug_target_buggy（jbe 越界 + 32 位累加）" "$out" "$expect"
else
    echo "  [FAIL] -DBUGGY_VERSION 版本编译失败"
    fail=1
fi

# ---- 3. hexdump：喂固定输入，比对每一行 ----------------------------------
# 十六进制区固定 49 个字符 = 16 字节 × 3 + 第 8 字节后多 1 个空格；
# 不满 16 字节的行用空格补足，所以用 %*s 现场补 (49 - 3*已有字节数) 个空格。
HEXLEN=49

out=$(printf 'hello\n' | ./hexdump)
expect=$(printf '00000000  68 65 6c 6c 6f 0a %*s |hello.|\n00000006' $((HEXLEN - 3 * 6)) '')
expect_ok "hexdump（6 字节：短行补空格 + 末尾总偏移）" "$out" "$expect"

out=$(printf '0123456789abcdef' | ./hexdump)
expect='00000000  30 31 32 33 34 35 36 37  38 39 61 62 63 64 65 66  |0123456789abcdef|
00000010'
expect_ok "hexdump（正好 16 字节：第 8 字节后多一个空格）" "$out" "$expect"

out=$(printf 'a\001\377\176\040b' | ./hexdump)
expect=$(printf '00000000  61 01 ff 7e 20 62 %*s |a..~ b|\n00000006' $((HEXLEN - 3 * 6)) '')
expect_ok "hexdump（不可打印字节显示成 .）" "$out" "$expect"

out=$(./hexdump < /dev/null)
expect_ok "hexdump（空输入：什么都不打印，正常退出）" "$out" ""

# ---- 4. 系统里如果有 hexdump，就和它逐字节比一次 -------------------------
if command -v hexdump >/dev/null 2>&1; then
    same=1
    for gen in "printf hello" \
               "printf 0123456789abcdef" \
               "printf 01234567890123456789" \
               "printf a\\001\\377\\176\\040b" \
               "printf \\377\\376\\375" \
               "head -c 999 /dev/urandom"; do
        eval "$gen" > .hx_in
        ./hexdump < .hx_in > .hx_mine
        hexdump -C < .hx_in > .hx_ref
        if ! cmp -s .hx_mine .hx_ref; then
            echo "  [FAIL] 和 hexdump -C 不一致：$gen"
            diff <(cat -A .hx_ref) <(cat -A .hx_mine) | head -6
            same=0
            fail=1
        fi
    done
    [ $same -eq 1 ] && echo "  [OK] 与系统 hexdump -C 逐字节一致（6 组输入）"
    rm -f .hx_in .hx_mine .hx_ref
else
    echo "  [SKIP] 系统没有 hexdump，跳过与 hexdump -C 的交叉验证"
fi

# ---- 5. 清理测试产物 ------------------------------------------------------
rm -f debug_target.o debug_target_buggy

[ $fail -eq 0 ] && echo "第 14 课全部通过" || echo "第 14 课存在失败"
exit $fail

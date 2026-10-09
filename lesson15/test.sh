#!/usr/bin/env bash
# ===========================================================================
# 第 15 课自测：hexdump2（支持文件名参数）+ wordcount（三列统计、多文件）
#
#   make test 已经先 `make all`，./hexdump2 和 ./wordcount 必定存在。
#   这里现场造三个小测试文件，比对输出后删掉。
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

printf 'hello world\nfoo bar baz\n' > t1.txt    # 2 行 5 词 24 字节
printf 'one\ttwo three\n'          > t2.txt    # 1 行 3 词 14 字节
printf 'x y z\n'                   > t3.txt    # 1 行 3 词 6 字节
trap 'rm -f t1.txt t2.txt t3.txt' EXIT

# ===========================================================================
# 一、wordcount
# ===========================================================================
out=$(./wordcount t1.txt)
expect_ok "wordcount 单文件" "$out" " 2  5 24 t1.txt"

out=$(./wordcount t1.txt t2.txt t3.txt)
expect=$(printf '%s\n%s\n%s\n%s' \
    ' 2  5 24 t1.txt' \
    ' 1  3 14 t2.txt' \
    ' 1  3  6 t3.txt' \
    ' 4 11 44 total')
expect_ok "wordcount 多文件 + total 行（列宽右对齐）" "$out" "$expect"

# 管道输入：列宽最小 7（GNU wc 的怪癖，我们用 fstat 判断文件类型来对齐）
out=$(printf 'a b\nc\n' | ./wordcount)
expect=$(printf '%7d %7d %7d' 2 3 6)
expect_ok "wordcount 标准输入（管道 → 列宽最小 7）" "$out" "$expect"

# 重定向普通文件：按文件大小的位数定列宽（这里 24 → 2）
out=$(./wordcount < t1.txt)
expect_ok "wordcount 重定向普通文件（列宽 = 2）" "$out" " 2  5 24"

# 打不开的文件：退出码 1
./wordcount nonexistent.txt > .wc_out 2> .wc_err
rc=$?
out=$(cat .wc_out)
if [ $rc -eq 1 ] && [ "$out" = "" ]; then
    echo "  [OK] wordcount 打不开的文件：退出码 1，stdout 为空"
else
    echo "  [FAIL] wordcount 错误处理：rc=$rc stdout=[$out]"
    fail=1
fi
rm -f .wc_out .wc_err

# 如果系统有 wc，再用 LC_ALL=C wc -l -w -c 交叉验证一次（纯 ASCII 文本两者应一致）
if command -v wc >/dev/null 2>&1; then
    ./wordcount t1.txt t2.txt t3.txt > .wc_mine
    LC_ALL=C wc -l -w -c t1.txt t2.txt t3.txt > .wc_ref
    if cmp -s .wc_mine .wc_ref; then
        echo "  [OK] 与 LC_ALL=C wc -l -w -c 输出一致"
    else
        echo "  [FAIL] 与 wc 输出不一致"
        diff .wc_ref .wc_mine
        fail=1
    fi
    rm -f .wc_mine .wc_ref
fi

# ===========================================================================
# 二、hexdump2
# ===========================================================================
HEXLEN=49   # 十六进制区固定 49 字符 = 16 字节 × 3 + 第 8 字节后多 1 个空格

# 文件参数：t1.txt 共 24 字节 = 一行满 16 字节 + 一行 8 字节
out=$(./hexdump2 t1.txt)
expect=$(printf '00000000  68 65 6c 6c 6f 20 77 6f  72 6c 64 0a 66 6f 6f 20  |hello world.foo |\n00000010  62 61 72 20 62 61 7a 0a %*s |bar baz.|\n00000018' $((HEXLEN - 3 * 8)) '')
expect_ok "hexdump2 单文件（24 字节，含短行）" "$out" "$expect"

# 无参数 → 读标准输入
out=$(printf 'hello\n' | ./hexdump2)
expect=$(printf '00000000  68 65 6c 6c 6f 0a %*s |hello.|\n00000006' $((HEXLEN - 3 * 6)) '')
expect_ok "hexdump2 无参数读标准输入" "$out" "$expect"

# 多个文件 = 一条连续字节流，偏移不重置（和 hexdump -C a b 行为一致）
out=$(./hexdump2 t1.txt t2.txt t3.txt)
expect=$(cat t1.txt t2.txt t3.txt | hexdump -C 2>/dev/null)
if [ -n "$expect" ]; then
    expect_ok "hexdump2 多文件连续流（对照 hexdump -C）" "$out" "$expect"
else
    # 没有 hexdump 就只检查总偏移行：24 + 14 + 6 = 44 = 0x2c
    last=$(printf '%s\n' "$out" | tail -1)
    expect_ok "hexdump2 多文件总偏移" "$last" "0000002c"
fi

# 打不开的文件：报错到 stderr、退出码 1、不影响其他文件
./hexdump2 t1.txt nope.bin > .hx_out 2> .hx_err
rc=$?
if [ $rc -eq 1 ] && grep -q 'nope.bin: cannot open' .hx_err; then
    echo "  [OK] hexdump2 打不开的文件：stderr 有提示、退出码 1"
else
    echo "  [FAIL] hexdump2 错误处理：rc=$rc stderr=[$(cat .hx_err)]"
    fail=1
fi
rm -f .hx_out .hx_err

# 空输入不输出
out=$(./hexdump2 < /dev/null)
expect_ok "hexdump2 空输入" "$out" ""

[ $fail -eq 0 ] && echo "第 15 课全部通过" || echo "第 15 课存在失败"
exit $fail

#!/usr/bin/env bash
# ===========================================================================
# 第 09 课自测：编译 + 运行 + 比对期望输出
#   make test 会先 make all，所以这里不调用 make，直接跑程序
#
# 本课两个程序都要命令行参数，所以先用 printf 造几个测试文件再跑。
# ===========================================================================
set -u
cd "$(dirname "$0")"
fail=0
TMP=$(mktemp -d 2>/dev/null || echo /tmp/lesson09-test.$$)
mkdir -p "$TMP"



report() { # $1=成功/失败 $2=名字 $3=详情
    if [ "$1" = 1 ]; then
        echo "  [OK]   $2"
    else
        echo "  [FAIL] $2"
        printf '         %s\n' "$3"
        fail=1
    fi
}

expect_eq() { # $1=名字 $2=实际 $3=期望
    if [ "$2" = "$3" ]; then report 1 "$1"; else
        report 0 "$1" "实际=[$2] 期望=[$3]"
    fi
}

expect_contains() { # $1=名字 $2=实际 $3=子串
    case "$2" in
        *"$3"*) report 1 "$1" ;;
        *) report 0 "$1" "输出里找不到 [$3]；实际=[$2]" ;;
    esac
}

# ---------------------------------------------------------------------------
# 造测试文件
printf 'hello world\nfoo bar\n' > "$TMP/small.txt"
printf 'one two three\n' > "$TMP/three.txt"
: > "$TMP/empty.txt"
printf 'no-trailing-newline' > "$TMP/nonl.txt"
printf 'a  b\tc\nd\n' > "$TMP/space.txt"
# 一个比 64 KiB 缓冲区大的文件（验证「短读」和边界处理）
i=0
while [ $i -lt 30000 ]; do printf 'word %s and more words here\n' "$i"; i=$((i+1)); done > "$TMP/big.txt"

echo "== copy =="

# 1) 基本拷贝：内容和字节数都要对上
rm -f "$TMP/out.txt"
out=$(./copy "$TMP/small.txt" "$TMP/out.txt" 2>&1)
rc=$?
expect_eq "退出码为 0" "$rc" "0"
expect_contains "打印了完成信息" "$out" "复制完成"
if cmp -s "$TMP/small.txt" "$TMP/out.txt"; then
    report 1 "small.txt 逐字节一致"
else
    report 0 "small.txt 逐字节一致" "$(cmp "$TMP/small.txt" "$TMP/out.txt" 2>&1)"
fi

# 2) 大文件（跨多个 64 KiB 缓冲区）
rm -f "$TMP/out_big.txt"
./copy "$TMP/big.txt" "$TMP/out_big.txt" >/dev/null 2>&1
if cmp -s "$TMP/big.txt" "$TMP/out_big.txt"; then
    report 1 "big.txt（约 780 KiB）逐字节一致"
else
    report 0 "big.txt 逐字节一致" "$(cmp "$TMP/big.txt" "$TMP/out_big.txt" 2>&1)"
fi

# 3) 空文件
rm -f "$TMP/out_empty.txt"
out=$(./copy "$TMP/empty.txt" "$TMP/out_empty.txt" 2>&1)
if [ -f "$TMP/out_empty.txt" ] && [ ! -s "$TMP/out_empty.txt" ]; then
    report 1 "空文件也能拷（目标文件是 0 字节）"
else
    report 0 "空文件也能拷" "目标文件不存在或非空"
fi
expect_contains "空文件也报告 0 字节" "$out" "0 字节"

# 4) 没有结尾换行的文件
rm -f "$TMP/out_nonl.txt"
./copy "$TMP/nonl.txt" "$TMP/out_nonl.txt" >/dev/null 2>&1
if cmp -s "$TMP/nonl.txt" "$TMP/out_nonl.txt"; then
    report 1 "没有结尾换行也原样拷贝"
else
    report 0 "没有结尾换行也原样拷贝" "内容不一致"
fi

# 5) 参数错误 / 源文件不存在，要优雅退出
out=$(./copy 2>&1); rc=$?
expect_eq "参数不足时退出码 1" "$rc" "1"
expect_contains "参数不足时给出用法" "$out" "用法"

out=$(./copy "$TMP/没有这个文件" "$TMP/x.txt" 2>&1); rc=$?
expect_eq "源文件不存在时退出码 2" "$rc" "2"
expect_contains "源文件不存在时给出提示" "$out" "打不开源文件"

# ---------------------------------------------------------------------------
echo "== wc =="

# 用「期望值」直接比对，不依赖系统 wc（不同平台的 wc 对多字节字符的
# 单词切分规则不完全一样，拿它当参照反而会引入平台差异）。
#
# 输出的三列是：行数 单词数 字节数，每列右对齐 7 位，最后跟文件名。
check_wc() { # $1=文件 $2=显示名 $3=行 $4=词 $5=字节
    out=$(./wc "$1")
    got=$(printf '%s\n' "$out" | sed 's/^[[:space:]]*//; s/[[:space:]]\{1,\}/ /g' | cut -d' ' -f1-3)
    expect_eq "wc $2 = $3 行 $4 词 $5 字节" "$got" "$3 $4 $5"
    expect_contains "wc $2 输出里带文件名" "$out" "$2"
}

# small.txt: "hello world\nfoo bar\n"
check_wc "$TMP/small.txt"  "$TMP/small.txt"  2 4 20
# three.txt: "one two three\n"
check_wc "$TMP/three.txt"  "$TMP/three.txt"  1 3 14
# empty.txt: 0 字节
check_wc "$TMP/empty.txt"  "$TMP/empty.txt"  0 0 0
# nonl.txt: "no-trailing-newline"，没有换行符 -> 行数是 0
check_wc "$TMP/nonl.txt"   "$TMP/nonl.txt"   0 1 19
# space.txt: "a  b\tc\nd\n"：连续空格和 TAB 都只是分隔符
check_wc "$TMP/space.txt"  "$TMP/space.txt"  2 4 9
# 大文件（约 780 KiB，跨多个 64 KiB 缓冲区）：
#   每行 "word N and more words here" + '\n'，共 30000 行、6 个词
check_wc "$TMP/big.txt"    "$TMP/big.txt"    30000 180000 918890

# 不带参数：从标准输入读（文件名显示 '-'）
out=$(printf 'a b\n' | ./wc)
expect_eq "stdin：1 行 2 词 4 字节" \
    "$(printf '%s\n' "$out" | sed 's/^[[:space:]]*//; s/[[:space:]]\{1,\}/ /g')" "1 2 4 -"

# 空的标准输入（等价于 EOF）也要能正常收工
out=$(printf '' | ./wc)
expect_eq "空 stdin：0 0 0" \
    "$(printf '%s\n' "$out" | sed 's/^[[:space:]]*//; s/[[:space:]]\{1,\}/ /g')" "0 0 0 -"

# 文件不存在：退出码 2
out=$(./wc "$TMP/没有这个文件" 2>&1); rc=$?
expect_eq "文件不存在时退出码 2" "$rc" "2"
expect_contains "文件不存在时给出提示" "$out" "打不开文件"

# ---------------------------------------------------------------------------
rm -rf "$TMP"
[ $fail -eq 0 ] && echo "第 09 课全部通过" || echo "第 09 课存在失败"
exit $fail

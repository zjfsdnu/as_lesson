#!/usr/bin/env bash
# ===========================================================================
# 第 08 课自测：编译 + 运行 + 比对期望输出
#   make test 会先 make all，所以这里不调用 make，直接跑程序
# ===========================================================================
set -u
cd "$(dirname "$0")"
fail=0

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

# line_with <输出> <行首前缀> <第几个匹配>：取第 n 行匹配的行（从 1 开始）
line_with() {
    printf '%s\n' "$1" | grep -F -- "$2" | sed -n "${3}p"
}

# ---------------------------------------------------------------------------
echo "== num2str =="
out=$(./num2str)

expect_eq "print_uint_v1(0) = 0" \
    "$(line_with "$out" 'print_uint_v1(0)' 1 | sed 's/.* = //')" "0"
expect_eq "print_uint_v1(7) = 7" \
    "$(line_with "$out" 'print_uint_v1(7)' 1 | sed 's/.* = //')" "7"
expect_eq "print_uint_v1(12345) = 12345" \
    "$(line_with "$out" 'print_uint_v1(12345)' 1 | sed 's/.* = //')" "12345"
expect_eq "print_uint_v1(u64 最大值)" \
    "$(line_with "$out" 'print_uint_v1(18446744073709551615)' 1 | sed 's/.* = //')" \
    "18446744073709551615"
# 反面教材：顺序反了，输出应该是 54321
expect_contains "print_uint_reversed(12345) = 54321（反面教材）" \
    "$(line_with "$out" 'print_uint_reversed' 1)" "= 54321 "
# 除法过程的 5 轮余数：5 4 3 2 1
# 五轮除法的余数应当依次是 5 4 3 2 1（顺序是「低位先出」）
for pair in "1:5" "2:4" "3:3" "4:2" "5:1"; do
    k=${pair%%:*}; want=${pair##*:}
    expect_contains "第 $k 轮余数是 $want" "$(line_with "$out" '余数' "$k")" "= $want "
done

expect_eq "u64_to_dec(0) -> 0" \
    "$(line_with "$out" 'u64_to_dec(0)' 1 | sed 's/.*【//; s/】.*//')" "0"
expect_eq "u64_to_dec(12345) -> 12345" \
    "$(line_with "$out" 'u64_to_dec(12345)' 1 | sed 's/.*【//; s/】.*//')" "12345"
expect_eq "u64_to_dec(1000000) -> 1000000" \
    "$(line_with "$out" 'u64_to_dec(1000000)' 1 | sed 's/.*【//; s/】.*//')" "1000000"
expect_eq "u64_to_dec(u64 最大值)" \
    "$(line_with "$out" 'u64_to_dec(18446744073709551615)' 1 | sed 's/.*【//; s/】.*//')" \
    "18446744073709551615"
# 小数字只占用缓冲区最后 1 个字节，前面 11 个 '#' 原封不动
buf12=$(line_with "$out" '缓冲区的末尾 12 字节' 1 | sed 's/.*\[//; s/\].*//')
expect_eq "只有最后一个字节被改写：###########1" "$buf12" "###########1"

# ---------------------------------------------------------------------------
echo "== str2num =="
# 喂一行输入给「从标准输入读」的演示
out=$(printf '  -12345\n' | ./str2num)

# 用 awk 按「空白分隔的字段」取值：输出里有中文，用字段比较比数字节位置稳。
# 字段含义：$1=输入 $2=值 $3=十六进制 $4=位数 $5=状态
# 注意第二行是表头、第 11 行是空串用例（那一行只有一个字段），要跳过。
field() { # $1=输入串 $2=要第几个字段
    printf '%s\n' "$out" | /usr/bin/awk -v key="$1" -v f="$2"         'index($0,key)==1 && $1!="输入" && NF>1 { print $f; exit }'
}

check_row() { # $1=输入串 $2=期望值 $3=期望位数 $4=期望状态
    expect_eq "'$1' -> 值 $2"   "$(field "$1" 2)" "$2"
    expect_eq "'$1' -> 位数 $3" "$(field "$1" 4)" "$3"
    expect_eq "'$1' -> 状态 $4" "$(field "$1" 5)" "$4"
}

check_row "12345"                "12345"               "5"  "OK"
check_row "-987"                 "-987"                "3"  "OK"
check_row "+42"                  "42"                  "2"  "OK"
check_row "0000"                 "0"                   "4"  "OK"
check_row "9223372036854775807"  "9223372036854775807" "19" "OK"
check_row "-9223372036854775808" "-9223372036854775808" "19" "OK"
check_row "9223372036854775808"  "0"                   "0"  "溢出"
check_row "99999999999999999999" "0"                   "0"  "溢出"
# 「-」这一行第一列是 "-" 加 20 个空格，去掉行尾空格后前缀匹配会更简单
expect_contains "'-' -> 空串/只有符号" "$(line_with "$out" '- ' 1)" "空串/只有符号"
check_row "12a3"                 "0"                   "0"  "非法字符"
expect_contains "空串用例被识别成空串" "$out" "(空串)"

# 标准输入那一行：前导空格被跳过，能正确解析 -12345
expect_contains "stdin 里读到并去掉了换行" "$out" "读出（已去掉换行）=   -12345"
expect_contains "stdin 的 -12345 解析成功" "$out" "0xffffffffffffcfc7"

# ---------------------------------------------------------------------------
[ $fail -eq 0 ] && echo "第 08 课全部通过" || echo "第 08 课存在失败"
exit $fail

#!/usr/bin/env bash
# ===========================================================================
# 第 07 课自测：编译 + 运行 + 比对期望输出
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

# ---------------------------------------------------------------------------
echo "== add_func =="
out=$(./add_func)
expect_eq "add_two(a_value, b_value) = 42" \
    "$(printf '%s\n' "$out" | grep '^add_two(a_value' | sed 's/.*= //')" "42"
expect_eq "add_two(1000, 2345) = 3345" \
    "$(printf '%s\n' "$out" | grep '^add_two(1000,' | sed 's/.*= //')" "3345"
expect_eq "add_two(7, -20) = -13" \
    "$(printf '%s\n' "$out" | grep '^add_two(7,' | sed 's/.*= //')" "-13"
expect_eq "add_two(1, -1) = 0" \
    "$(printf '%s\n' "$out" | grep '^add_two(1,' | sed 's/.*= //')" "0"
expect_eq "add_four(...) = 137" \
    "$(printf '%s\n' "$out" | grep '^add_four' | sed 's/.*= //')" "137"
expect_eq "被调用者保存的 rbx 没被破坏" \
    "$(printf '%s\n' "$out" | grep '^函数返回后' | sed 's/.*= //')" "22"

# ---------------------------------------------------------------------------
echo "== stack_demo =="
out=$(./stack_demo)
# 地址每次运行都不同（ASLR），所以只比对固定的文字和「下了几字节」
expect_contains "起始 rsp 已对齐" "$(printf '%s\n' "$out" | grep '^起始 rsp')" "= 0x"
expect_contains "第 1 次 push 下了 8 字节" \
    "$(printf '%s\n' "$out" | grep '第 1 次 push')" "下了 8 字节"
expect_contains "第 2 次 push 下了 16 字节" \
    "$(printf '%s\n' "$out" | grep '第 2 次 push')" "下了 16 字节"
expect_contains "局部空间 16 字节" "$(printf '%s\n' "$out" | grep 'rbp - rsp')" "16 字节"

# 起始 / 第 1 次 / 第 2 次 / 弹干净 四个 rsp 的数值关系：
#   rsp0 == rsp_after_all, rsp1 == rsp0 - 8, rsp2 == rsp0 - 16
rsp0=$(printf '%s\n' "$out" | sed -n 's/^起始 rsp.*= \(0x[0-9a-f]*\) *$/\1/p')
rsp1=$(printf '%s\n' "$out" | sed -n 's/^第 1 次 push.*= \(0x[0-9a-f]*\) *$/\1/p')
rsp2=$(printf '%s\n' "$out" | sed -n 's/^第 2 次 push.*= \(0x[0-9a-f]*\) *$/\1/p')
rspend=$(printf '%s\n' "$out" | sed -n 's/^全部弹干净.*= \(0x[0-9a-f]*\) *$/\1/p')
if [ -n "$rsp0" ] && [ -n "$rsp1" ] && [ -n "$rsp2" ] && [ -n "$rspend" ]; then
    # bash 的算术展开认识 0x 前缀
    diff1=$(( rsp0 - rsp1 ))
    diff2=$(( rsp0 - rsp2 ))
    diffend=$(( rsp0 - rspend ))
    expect_eq "push 1 次后 rsp 减 8" "$diff1" "8"
    expect_eq "push 2 次后 rsp 减 16" "$diff2" "16"
    expect_eq "弹干净后 rsp 回到起点" "$diffend" "0"
else
    report 0 "能解析出四个 rsp 地址" "rsp0=[$rsp0] rsp1=[$rsp1] rsp2=[$rsp2] end=[$rspend]"
fi

# ---------------------------------------------------------------------------
echo "== multi_args =="
out=$(./multi_args)
expect_eq "sum6(1,2,3,4,5,6) = 21" \
    "$(printf '%s\n' "$out" | grep '^sum6(1,' | sed 's/.*= //')" "21"
expect_eq "sum6(10,20,30,40,50,60) = 210" \
    "$(printf '%s\n' "$out" | grep '^sum6(10,' | sed 's/.*= //')" "210"
expect_eq "sum6(-1..-6) = -21" \
    "$(printf '%s\n' "$out" | grep '^sum6(-1' | sed 's/.*= //')" "-21"
expect_eq "sum6(100..600) = 2100" \
    "$(printf '%s\n' "$out" | grep '^sum6(100,' | sed 's/.*= //')" "2100"
expect_eq "sum7 的第 7 个参数在栈上 = 28" \
    "$(printf '%s\n' "$out" | grep '^sum7' | sed 's/.*= //')" "28"

# ---------------------------------------------------------------------------
[ $fail -eq 0 ] && echo "第 07 课全部通过" || echo "第 07 课存在失败"
exit $fail

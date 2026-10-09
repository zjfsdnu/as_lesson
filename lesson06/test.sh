#!/usr/bin/env bash
# 第 06 课自测：运行 count / sum_array 并逐字节比对期望输出
#
#   make test   —— Makefile 会先 make all，再执行本脚本；本脚本不再调用 make。
#   全部通过 exit 0，任何一项不符 exit 1；程序不存在会被判为失败。
set -u
cd "$(dirname "$0")"
fail=0

# check <程序名> <期望输出>（期望输出末尾不要换行，command substitution 会吃掉）
check() {
    local prog want got rc
    prog="$1"; want="$2"
    got=$(./"$prog"); rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "  [FAIL] $prog：退出码 $rc（应为 0）"
        fail=1
        return
    fi
    if [ "$got" = "$want" ]; then
        echo "  [OK] $prog"
    else
        echo "  [FAIL] $prog：输出与期望不符（- 期望 / + 实际）"
        diff <(printf '%s\n' "$want") <(printf '%s\n' "$got")
        fail=1
    fi
}

check count "$(cat <<'EOF'
A) rcx counter, 1..10   : 1 2 3 4 5 6 7 8 9 10
B) rcx counter, 10..1   : 10 9 8 7 6 5 4 3 2 1
C) loop: 1+2+...+100    = 5050
EOF
)"

check sum_array "$(cat <<'EOF'
array    : [10, -3, 25, -8, -1, 100, -50, 7]
sum      = 80
count    = 8
negative = 4
average  = 10
EOF
)"

[ $fail -eq 0 ] && echo "第 06 课全部通过" || echo "第 06 课存在失败"
exit $fail

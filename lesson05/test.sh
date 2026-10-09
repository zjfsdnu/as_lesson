#!/usr/bin/env bash
# 第 05 课自测：运行 cmpjmp / minmax 并逐字节比对期望输出
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

check cmpjmp "$(cat <<'EOF'
cmp   1, 2     : jl    -> taken
cmp  -1, 1     : jl    -> taken
cmp  -1, 1     : jg    -> not taken
cmp  -1, 1     : ja    -> taken
cmp  -1, 1     : jb    -> not taken
cmp   5, 5     : je    -> taken
cmp   3, 5     : jge   -> not taken
test  0, 0     : jz    -> taken
EOF
)"

check minmax "$(cat <<'EOF'
max_signed(-7, 3)   = 3
max_unsigned(-7, 3) = 0xfffffffffffffff9  (unsigned: 18446744073709551609)
array               = [17, -5, 42, -100, 0, 33, -7]
max                 = 42
min                 = -100
EOF
)"

[ $fail -eq 0 ] && echo "第 05 课全部通过" || echo "第 05 课存在失败"
exit $fail

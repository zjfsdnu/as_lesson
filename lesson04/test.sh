#!/usr/bin/env bash
# 第 04 课自测：运行 arith / flags / bitops 并逐字节比对期望输出
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

check arith "$(cat <<'EOF'
add:     15 + 27               = 42
sub:     15 - 27               = -12
imul:    15 * 27               = 405
imul:    1000000 * 1000000     = 1000000000000
imul:    (2^32)*(2^32) rdx:rax = 1:0
div:     100 / 7               = 14  rem 2
idiv:    -100 / 7              = -14  rem -2
inc:     41 + 1                = 42
dec:     42 - 1                = 41
neg:     -(5)                  = -5
div:     2^64 / 10             = 1844674407370955161  rem 6
div:     100 / 7 (rdx=1)       = 2635249153387078816  rem 4
EOF
)"

check flags "$(cat <<'EOF'
sub 5 - 5            -> ZF=1  CF=0  SF=0  OF=0
sub 1 - 2            -> ZF=0  CF=1  SF=1  OF=0
add 0x7fff..ff + 1   -> ZF=0  CF=0  SF=1  OF=1
add -1 + 1           -> rflags & 0x8c1 = 0b1000001   [bit0=CF bit6=ZF bit7=SF bit11=OF]
test 0x0f & 0xf0     -> rflags & 0x8c1 = 0b1000000   [bit0=CF bit6=ZF bit7=SF bit11=OF]
shl 0x8000..00 by 1  -> rflags & 0x8c1 = 0b100001000001   [bit0=CF bit6=ZF bit7=SF bit11=OF]
EOF
)"

check bitops "$(cat <<'EOF'
and:  0x1234abcd & 0x0000ffff = 0xabcd
or:   0x1000 | 0x0001         = 0x1001
xor:  0b1100 ^ 0b1010         = 0b110
not:  ~0x0f                   = 0xfffffffffffffff0
shl:  1 << 4                  = 16
shl:  1 << 63                 = 0x8000000000000000
shr:  0x8000000000000000 >> 3 = 0x1000000000000000
sar:  -16 >> 2 (arith)        = -4
shr:  -16 >> 2 (logical)      = 4611686018427387900
shl:  1 << cl (cl = 8)        = 256
shl:  1 << cl (cl = 65)       = 2
xor:  eax ^= eax (zero idiom) = 0
EOF
)"

[ $fail -eq 0 ] && echo "第 04 课全部通过" || echo "第 04 课存在失败"
exit $fail

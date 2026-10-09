#!/usr/bin/env bash
# 第 10 课自测：编译好的示例直接运行，检查输出
#   （make test 会先 make all，所以这里不调用 make；程序不存在就直接失败）
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

exp_float='a = 2.500000   (位模式 0x4004000000000000)
b = 7.000000   (位模式 0x401c000000000000)
a + b = 9.500000
a - b = -4.500000
a * b = 17.500000
a / b = 0.357143
pi    = 3.1415926536
e     = 2.7182818285
sqrt(2) = 1.4142135624
42 转成 double 后是 42.0
浮点运算演示结束'

exp_div='=== 整数除法 vs 浮点除法 ===
整数: 7 / 2 = 3 余 1
浮点: 7.0 / 2.0 = 3.500000
7.0 / 3.0 = 2.333333
17.5 / 25.0 = 70.0%   (printf 里 % 打印一个百分号)
7.0 / (-2.0) = -3.500000
%+.2f 会强制显示正负号 : +1234.57
1234.5678 的 IEEE-754 位模式: 0x40934a456d5cfaad
结论: 需要小数就必须用浮点指令'

check lc_float "$exp_float"
check lc_float_div "$exp_div"

# 单独验证「除不尽」的精度：%.6f 必须把 7/3 四舍五入到 2.333333
got=$(./lc_float_div | sed -n '4p')
if [ "$got" = "7.0 / 3.0 = 2.333333" ]; then
    echo "  [OK] 浮点除法的四舍五入"
else
    echo "  [FAIL] 浮点除法的四舍五入: $got"
    fail=1
fi

if [ $fail -eq 0 ]; then
    echo "第 10 课全部通过"
else
    echo "第 10 课存在失败"
fi
exit $fail

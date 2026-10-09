#!/usr/bin/env bash
# ===========================================================================
# 第 02 课自测：检查 regs / mem 的输出
#
#   ./test.sh        单独跑本脚本
#   make test        Makefile 会先 make all，再调用本脚本
#
# 本脚本不调用 make：二进制不存在就直接失败。
# ===========================================================================
set -u
cd "$(dirname "$0")"
fail=0

# ---------------------------------------------------------------------------
# check_block <名字> <程序输出> <期望行数>
#   期望的每一行从标准输入（here-document）读入：
#   1) 先比行数；2) 再要求每一行都在输出里原样出现（-x 整行、-F 不当正则）。
#   行数对 + 每行都命中，就等价于逐字节一致。
# ---------------------------------------------------------------------------
check_block() {
    local name="${1}" out="${2}" want_n="${3}"
    local n miss=0
    n=$(printf '%s\n' "${out}" | wc -l | tr -d ' ')
    if [ "${n}" -eq "${want_n}" ]; then
        echo "  [OK] ${name}：输出 ${n} 行"
    else
        echo "  [FAIL] ${name}：输出 ${n} 行，期望 ${want_n} 行"
        fail=1
    fi
    while IFS= read -r want; do
        if ! printf '%s\n' "${out}" | grep -qxF -- "${want}"; then
            echo "  [FAIL] ${name}：缺少这一行：${want}"
            miss=1
            fail=1
        fi
    done
    [ "${miss}" -eq 0 ] && echo "  [OK] ${name}：每一行都和期望一致"
    return 0
}

# ---------------------------------------------------------------------------
# regs：输出全是确定值，10 行都要对
# ---------------------------------------------------------------------------
out=$(./regs)
check_block regs "$out" 10 <<'EOF'
=== 第 02 课：寄存器宽度演示 ===
1) mov rax, 0x1122334455667788          -> rax = 0x1122334455667788
2) 再 mov ax, 0xaabb（只动低 16 位）    -> rax = 0x112233445566aabb
3) 重来再 mov al, 0xcc（只动低 8 位）   -> rax = 0x11223344556677cc
4) 重来 mov eax, 0xdeadbeef（清高 32）  -> rax = 0xdeadbeef
5) 接上一步 mov ah, 0x77（第 2 字节）   -> rax = 0xdead77ef
6) rax = -1，当有符号数看               -> -1
   rax = -1，当无符号数看               -> 18446744073709551615
7) mov al,0xFF 后 movzx rax,al          -> 255
   mov al,0xFF 后 movsx rax,al          -> -1
EOF

# ---------------------------------------------------------------------------
# mem：有一行打印的是地址（每次运行都可能不同），所以先单独检查它，
#      再用"滤掉地址行"的输出做整段比对。
# ---------------------------------------------------------------------------
raw=$(./mem)

if printf '%s\n' "$raw" | grep -qF -- '[地址 ] d_val(.data) = 0x' \
   && printf '%s\n' "$raw" | grep -qF -- 'b_num(.bss) = 0x' \
   && printf '%s\n' "$raw" | grep -qF -- 'rsp(栈顶) = 0x'; then
    echo "  [OK] mem：打印出了 .data / .bss / 栈 三个地址"
else
    echo "  [FAIL] mem：地址行不符合预期（应该打印出 0x 开头的三个地址）"
    fail=1
fi

out=$(printf '%s\n' "$raw" | grep -vF -- '[地址 ]')
check_block mem "$out" 11 <<'EOF'
=== 第 02 课：三种数据位置 .data / .bss / 栈 ===
[.data] d_val 的初值               = 0x1122334455667788
[.data] d_msg 的内容               : d_msg：我在 .data，初值已经写进可执行文件
[.bss ] b_num 没赋过值，读出来是   = 0x0
[.bss ] 往 b_num 写 0x2a 再读      = 0x2a
[.bss ] b_buf[0] 当数字看          = 0x41
[.bss ] b_buf 当字符串看           = AB
[栈   ] sub rsp,16 之后 [rsp]      = 0x1111
[栈   ] 同一块空间的 [rsp+8]       = 0x2222
[栈   ] add rsp,16 后 (备份rsp-rsp)= 0x0   ← 0 表示栈指针已经复原
（地址每次运行都可能不同，这是正常的）
EOF

[ ${fail} -eq 0 ] && echo "第 02 课全部通过" || echo "第 02 课存在失败"
exit ${fail}

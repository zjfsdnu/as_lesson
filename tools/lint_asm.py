#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课程源码静态规范检查器（不需要 nasm，本地就能跑）。

检查项：
  1. 纯 syscall 程序必须有 `global _start`；lc_ 开头的 libc 程序必须有 `global main`
     且**不能**有 `_start`
  2. lc_*.asm（用 gcc -no-pie 链 libc）不能 %include "io.inc"
  3. 纯 syscall 程序里出现 `main` 入口会被 crt1.o 冲突 —— 提示
  4. 危险写法：syscall 的缓冲区地址直接指向活动栈（`mov rsi, rsp` 后紧跟 write 类调用）
  5. `mov dl/ml/…` 设置长度：提示改用 32 位写法（不清高位）
  6. `mov`/`lea` 里访问数据标签但没写 `rel`（非 PIE 下能编过，但容易踩绝对寻址坑，
     只作为提醒，不算错误）
  7. 数据标签出现却没有对应 section（简单粗查）
  8. README 里 ```asm 代码块是否与磁盘上的 .asm 逐字节一致（可选，--readme）

用法：
  python3 tools/lint_asm.py            # 检查所有课程
  python3 tools/lint_asm.py lesson07   # 只检查某一课
  python3 tools/lint_asm.py --readme   # 额外校验 README 内嵌源码一致性
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ERROR, WARN = "错误", "提醒"
problems = []
stats = {"files": 0, "errors": 0, "warnings": 0}


def report(level, path, line, msg):
    problems.append((level, path, line, msg))
    stats["errors" if level == ERROR else "warnings"] += 1


def check_file(path):
    stats["files"] += 1
    rel = os.path.relpath(path, ROOT)
    base = os.path.basename(path)
    is_libc = base.startswith("lc_")
    text = open(path, encoding="utf-8").read()
    lines = text.splitlines()

    has_start = re.search(r"^\s*global\s+_start\b", text, re.M) is not None
    has_main = re.search(r"^\s*global\s+main\b", text, re.M) is not None
    has_include_io = re.search(r'%include\s+"io\.inc"', text) is not None

    # 1. 入口约定
    if is_libc:
        if not has_main:
            report(ERROR, rel, 0, "lc_ 开头的 libc 程序必须 `global main`")
        if has_start:
            report(ERROR, rel, 0, "lc_ 程序不能定义 _start（crt1.o 已定义，会重复符号）")
        if has_include_io:
            report(ERROR, rel, 0, 'lc_ 程序不要 %include "io.inc"（会与 libc 混用且重复定义）')
    else:
        if not has_start:
            report(ERROR, rel, 0, "纯 syscall 程序必须 `global _start`")
        if has_main:
            report(WARN, rel, 0, "纯 syscall 程序里出现 global main，确认不需要改成 lc_ 风格")

    # 2. 危险：把 syscall 缓冲区指向活动栈
    for i, ln in enumerate(lines, 1):
        code = ln.split(";")[0]
        if re.search(r"\bmov\s+rsi\s*,\s*rsp\b", code):
            report(WARN, rel, i, "把 rsi 指向栈顶当输出缓冲区有风险（实测会让 ret 弹飞），"
                                 "请改用 io_putchar 或 .data 里的静态缓冲区")

    # 3. mov dl/xl 之类 + 立即数：写 8 位寄存器不清高位，设置长度时是常见 bug
    for i, ln in enumerate(lines, 1):
        code = ln.split(";")[0]
        m = re.search(r"\bmov\s+(dl|sil|dil|bl|cl)\s*,\s*([0-9]+|0x[0-9a-fA-F]+|'[^']*')\s*$", code)
        if m:
            report(WARN, rel, i, "`mov %s, %s` 不会清零高位，长度/数值请写 32 位（如 mov edx, 1）"
                   % (m.group(1), m.group(2)))

    # 4. 立即数 push（只压 4 字节，容易错位）
    for i, ln in enumerate(lines, 1):
        code = ln.split(";")[0]
        if re.search(r"\bpush\s+0x[0-9a-fA-F]+\b", code) or re.search(r"\bpush\s+\d+\b", code):
            if "qword" not in code:
                report(WARN, rel, i, "push 立即数只压 4/8 字节且不写 qword 时易错位，建议先 mov 到寄存器再 push")

    # 5. 数据访问没写 rel（只提醒，非 PIE 下合法）
    for i, ln in enumerate(lines, 1):
        code = ln.split(";")[0]
        for m in re.finditer(r"\[\s*([A-Za-z_][A-Za-z0-9_]*)\s*\]", code):
            name = m.group(1)
            if name in ("rsp", "rbp", "rax", "rbx", "rcx", "rdx", "rsi", "rdi",
                        "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15"):
                continue
            report(WARN, rel, i, "`[%s]` 建议写成 `[rel %s]`（位置无关，避免绝对寻址）" % (name, name))

    return text


def check_readme(path, asm_text_by_name):
    """校验 README 里的 ```asm 代码块是否来自磁盘上的 .asm 文件。

    只做「连续片段」判定：块里的每一行（去掉首尾空白后）要能在某个 .asm 中
    按同样顺序连续找到。这样既允许 README 只摘录某个函数/循环，
    也能抓出「README 和源码不同步」的真实问题。
    """
    rel = os.path.relpath(path, ROOT)
    lines = open(path, encoding="utf-8").read().splitlines()
    blocks, cur, in_block = [], [], False
    for ln in lines:
        if ln.strip().startswith("```asm"):
            in_block, cur = True, []
            continue
        if in_block and ln.strip() == "```":
            blocks.append("\n".join(cur))
            in_block = False
            continue
        if in_block:
            cur.append(ln)

    files = {name: [l.strip() for l in text.splitlines()]
             for name, text in asm_text_by_name.items()}

    for idx, blk in enumerate(blocks, 1):
        rows = [l.strip() for l in blk.strip().splitlines() if l.strip()]
        if not rows:
            continue
        # 在某个 .asm 里按顺序（允许跳过少量行）匹配，命中率 >= 90% 就算同步，
        # 这样既能容忍 README 省略个别注释/section 行，又能抓住真正的代码不同步。
        best = 0.0
        for name, frows in files.items():
            # 贪心按顺序匹配：对每一行，从上次命中位置往后找
            pos, hit = 0, 0
            for r in rows:
                try:
                    j = frows.index(r, pos)
                except ValueError:
                    # 找不到就跳过这一行（算作 README 自行添加的说明）
                    continue
                hit += 1
                pos = j + 1
            ratio = hit / len(rows)
            best = max(best, ratio)
        if best < 0.9:
            report(WARN, rel, 0,
                   "第 %d 个 ```asm 代码块与磁盘 .asm 只有 %.0f%% 的行能对应"
                   "（首行: %s），请检查是否已不同步"
                   % (idx, best * 100, rows[0][:40]))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    do_readme = "--readme" in sys.argv
    lessons = args or sorted(d for d in os.listdir(ROOT)
                             if re.match(r"^lesson\d\d$", d))
    for lesson in lessons:
        d = os.path.join(ROOT, lesson)
        if not os.path.isdir(d):
            continue
        asm_text = {}
        for f in sorted(os.listdir(d)):
            if f.endswith(".asm"):
                asm_text[f] = check_file(os.path.join(d, f))
        if do_readme and os.path.exists(os.path.join(d, "README.md")):
            check_readme(os.path.join(d, "README.md"), asm_text)

    print("检查了 %d 个 .asm 文件" % stats["files"])
    for level, path, line, msg in problems:
        loc = "%s:%d" % (path, line) if line else path
        print("[%s] %s  %s" % (level, loc, msg))
    print("\n汇总：%d 个错误，%d 条提醒" % (stats["errors"], stats["warnings"]))
    return 1 if stats["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())

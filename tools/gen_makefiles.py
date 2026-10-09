#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成每课统一 Makefile + 顶层总控 Makefile。

两种示例风格（默认模板同时支持，互不冲突）：

  A. 纯系统调用程序          源文件名：任意（例如 hello.asm）
     直接用 ld 链接，不要 libc，入口 _start。
         nasm -f elf64 -g -F dwarf -o hello.o hello.asm
         ld -o hello hello.o

  B. 调用 libc 的程序        源文件名必须以 lc_ 开头（例如 lc_printf.asm）
     入口必须写 main（不能写 _start；crt1.o 里已经有 _start 了）。
         nasm -f elf64 -g -F dwarf -o lc_printf.o lc_printf.asm
         gcc -no-pie -o lc_printf lc_printf.o
     原因见 README「约定」一节。

用法：python3 tools/gen_makefiles.py [tutorial_root]
"""
import os
import sys

LESSON_MAKEFILE = r"""# ===========================================================================
# Lesson {num} 统一 Makefile
#
#   make        编译本课全部示例
#   make run    依次运行本课全部示例（输出重定向到终端）
#   make test   运行本课自测脚本 test.sh（若存在）
#   make clean  清理编译产物
#
# 两种示例风格：
#   * 纯 syscall 程序：任意文件名，入口 _start，用 ld 直链
#   * libc 程序      ：文件名以 lc_ 开头，入口 main，用 gcc -no-pie 链接
# ===========================================================================

NASM      := nasm
NASMFLAGS := -f elf64 -g -F dwarf -I ../include
CC        := gcc
CFLAGS    := -no-pie -Wall -O0

SYS_ASMS  := $(filter-out lc_%, $(wildcard *.asm))
LC_ASMS   := $(wildcard lc_*.asm)
SYS_PROGS := $(SYS_ASMS:.asm=)
LC_PROGS  := $(LC_ASMS:.asm=)
PROGS     := $(SYS_PROGS) $(LC_PROGS)

.PHONY: all run test clean
all: $(PROGS)

# ---- A. 纯系统调用：nasm + ld -------------------------------------------
%: %.asm
	$(NASM) $(NASMFLAGS) -o $@.o $<
	ld -o $@ $@.o
	@rm -f $@.o

# ---- B. 调用 libc：nasm + gcc -no-pie（入口 main）-----------------------
lc_%: lc_%.asm
	$(NASM) $(NASMFLAGS) -o $@.o $<
	$(CC) $(CFLAGS) -o $@ $@.o
	@rm -f $@.o

run: all
	@for p in $(PROGS); do \
		echo "===== 运行 ./$$p ====="; \
		./$$p < /dev/null; echo "[退出码 $$?]"; echo; \
	done

test: all
	@if [ -x ./test.sh ]; then ./test.sh; else \
		echo "本课没有 test.sh：请手动 make run 观察输出"; fi

clean:
	rm -f $(PROGS) *.o
"""

TOP_MAKEFILE = r"""# ===========================================================================
# x86-64 汇编语言教程（NASM）总控 Makefile
#
#   make        编译全部课程
#   make test   运行全部课程测试
#   make run    顺序运行全部课程示例（输出很长）
#   make clean  清理全部产物
#   make list   列出全部课程目录
# ===========================================================================

LESSONS := $(wildcard lesson[0-9][0-9])

.PHONY: all test run clean list
all:
	@for d in $(LESSONS); do \
		echo "======== 编译 $$d ========"; \
		$(MAKE) -C $$d all || exit 1; \
	done
	@echo "全部课程编译完成。"

test:
	@fail=0; \
	for d in $(LESSONS); do \
		echo "======== 测试 $$d ========"; \
		$(MAKE) -C $$d test || fail=1; \
	done; \
	if [ $$fail -eq 0 ]; then echo "**** 全部测试通过 ****"; \
	else echo "**** 存在失败项 ****"; exit 1; fi

run:
	@for d in $(LESSONS); do $(MAKE) -C $$d run; done

clean:
	@for d in $(LESSONS); do $(MAKE) -C $$d clean; done

list:
	@ls -d $(LESSONS)
"""


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    count = 0
    for name in sorted(os.listdir(root)):
        if not (name.startswith("lesson") and name[6:].isdigit()):
            continue
        num = name[6:]
        with open(os.path.join(root, name, "Makefile"), "w", encoding="utf-8") as f:
            f.write(LESSON_MAKEFILE.format(num=num))
        count += 1
    with open(os.path.join(root, "Makefile"), "w", encoding="utf-8") as f:
        f.write(TOP_MAKEFILE)
    os.makedirs(os.path.join(root, "include"), exist_ok=True)
    print("已生成 %d 个课程 Makefile，以及顶层 Makefile" % count)


if __name__ == "__main__":
    main()

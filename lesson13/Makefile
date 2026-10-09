# ===========================================================================
# Lesson 13 统一 Makefile
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

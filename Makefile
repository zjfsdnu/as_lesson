# ===========================================================================
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

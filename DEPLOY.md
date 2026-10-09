# 部署与验证说明（给维护者看，不属于学员教程正文）

本目录是一套完整的 x86-64 汇编语言教程（15 课），最终部署位置：**`root@104.129.2.168:/root/study/as`**。

## 一、目录结构

```
as/
├── README.md             教程总览：路线图、编译方式、FAQ（学员从这里开始）
├── INSTRUCTOR.md         课程编写规范（技术约定、每题交付物要求）
├── Makefile              顶层总控：make / make test / make clean / make list
├── include/
│   ├── syscalls.inc      x86-64 系统调用号与常量（SYS_read / SYS_write / O_CREAT…）
│   └── io.inc            纯 syscall 输入输出例程（io_print / io_print_int / io_print_hex…）
├── lesson01 … lesson15/  每课：README.md（正文）+ *.asm（示例）+ test.sh（自测）
├── SOURCE_LISTING.txt    全书 32 个 .asm 的合订本（方便通读/打印）
├── FILE_TREE.txt         文件树
└── tools/
    ├── gen_makefiles.py  重新生成 15 个课程 Makefile 与顶层 Makefile
    ├── verify_remote.sh  打包 → 上传 → 编译 → 测试 一条龙
    ├── remote_check.sh   逐文件编译诊断 + 逐程序运行抽查（体检报告）
    ├── lint_asm.py       静态规范检查（入口风格、栈陷阱、README 与源码同步）
    └── source_listing.sh 生成 SOURCE_LISTING.txt 与 FILE_TREE.txt
```

## 一之二、验证状态（2026-10-07 实测）

在 `root@104.129.2.168`（Debian 13 / NASM 2.16.03 / gcc 14.2.0）上：

* `make -k all`：32 个 `.asm` 全部编译链接成功，退出码 0
* `make test`：**15 课全部通过**（`**** 全部测试通过 ****`）
* 本地另用 NASM 2.16.03 `-f elf64` 对全部 32 个文件做过汇编级校验，32/32 通过
* `tools/lint_asm.py`：0 个错误

### 两个真实的环境坑（已写进教程正文）

1. **这台虚拟机的 SSE 实现有缺陷**：`paddd` / `pmulld` 这类「多 lane 32 位」
   指令只算低 64 位（第 5~8 个 lane 恒为 0），而 `paddq` / `paddb` / `movdqu`
   都正常。第 11 课的 `lc_simd_intro.asm` 因此内置了自检：正常 CPU 打印
   「8 个 lane 全部正确」，坏环境打印「只有低 4 个 lane 正确（宿主机问题）」。
   换物理机/别的云主机即正常。
2. **macOS 打包会带 AppleDouble 文件**：`tar` 若不加 `COPYFILE_DISABLE=1`，
   远端会出现 `._xxx.asm`，被每课 Makefile 的 `$(wildcard *.asm)` 当成源文件
   而链接失败。`tools/remote_check.sh` 与 `verify_remote.sh` 都已处理。

## 二、两种示例风格（重要）

| | 纯系统调用程序 | libc 程序 |
|---|---|---|
| 文件名 | 任意（`hello.asm`、`hexdump.asm`） | **必须以 `lc_` 开头**（`lc_float.asm`） |
| 入口 | `global _start` | `global main` |
| 链接 | `nasm -f elf64 -g -F dwarf` + `ld` | nasm + `gcc -no-pie` |
| 原因 | 直接和内核打交道，看清 syscall 全貌 | `gcc -no-pie` 会链入 crt1.o（已含 `_start`）并由它完成 libc 初始化；自己写 `_start` 直接 `call printf` 会段错误 |

这套约定已实测：`ld` 直链的 `_start` 程序与 `gcc -no-pie` 链的 `main` 程序都能正常跑，且 `make test` 全绿。

## 三、在远端编译验证

```bash
# 一条龙：打包上传 → make all → make test → 运行抽查
tools/verify_remote.sh                      # 默认 root@104.129.2.168:/root/study/as
tools/remote_check.sh                       # 更详细的逐文件诊断报告
tools/remote_check.sh root@其他主机 /path    # 换主机/目录

# 只想自己上去看
ssh root@104.129.2.168
cd /root/study/as
make            # 编译全部 15 课
make test       # 跑全部自测
make clean
cd lesson01 && make run     # 单课
```

## 四、手动编译单个示例

```bash
# 纯 syscall
nasm -f elf64 -g -F dwarf -I ../include -o hello.o hello.asm && ld -o hello hello.o && ./hello

# libc 版（注意入口是 main，文件名 lc_ 前缀）
nasm -f elf64 -g -F dwarf -I ../include -o lc_float.o lc_float.asm && gcc -no-pie -o lc_float lc_float.o && ./lc_float
```

调试：

```bash
gdb -tui ./hello            # b _start / run / si / ni / info registers / x/8xb $rsp
objdump -d -M intel ./hello # 用 Intel 语法反汇编，和源码对照
readelf -h ./hello          # 看 ELF 头与入口地址
```

## 五、环境要求

Debian/Ubuntu x86-64（本教程在 Debian 13 + NASM 2.16.03 + GCC 14.2 上验证通过）：

```bash
apt-get update
apt-get install -y nasm binutils gcc gdb make
```

## 六、重新生成 Makefile

改动课程目录名或需要新增课程时：

```bash
python3 tools/gen_makefiles.py .     # 为每个 lessonNN 生成统一 Makefile
```

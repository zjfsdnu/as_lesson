#!/usr/bin/env bash
# ===========================================================================
# 远端完整体检：编译 → 测试 → 运行抽查，输出结构化报告。
#
#   tools/remote_check.sh [user@host] [远端目录]
#   默认： root@104.129.2.168  /root/study/as
#
# 说明：macOS 上 tar 默认会把扩展属性打包成 AppleDouble 文件（`._xxx.asm`），
# 而每课 Makefile 用 $(wildcard *.asm) 收集源文件，会把 `._hello.asm`
# 也当成源文件丢给 ld，导致 make all 报一堆莫名其妙的链接错误。
# 所以这里强制 COPYFILE_DISABLE=1 并排除 `._*`。
# ===========================================================================
set -u
HOST="${1:-root@104.129.2.168}"
REMOTE="${2:-/root/study/as}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARBALL="$(mktemp -t asm-tutorial).tar.gz"
trap 'rm -f "$TARBALL"' EXIT

export COPYFILE_DISABLE=1

SSH="ssh -o ConnectTimeout=20 $HOST"

echo "==> 打包本地教程（COPYFILE_DISABLE=1，排除 ._*）"
tar --exclude='._*' --exclude='.DS_Store' --exclude='*.o' \
    -czf "$TARBALL" -C "$ROOT" \
    Makefile README.md INSTRUCTOR.md DEPLOY.md include lesson[0-9][0-9] tools

echo "==> 上传到 $HOST:$REMOTE"
$SSH "mkdir -p $REMOTE && rm -rf $REMOTE/*"
scp -o ConnectTimeout=20 -q "$TARBALL" "$HOST:/tmp/asm-tutorial.tar.gz"
$SSH "tar -xzf /tmp/asm-tutorial.tar.gz -C $REMOTE && echo 解包完成"

echo
echo "==> 远端文件概览"
$SSH "cd $REMOTE && echo \"课程目录: \$(ls -d lesson* | tr '\n' ' ')\" && \
      echo \"asm 文件 \$(find lesson* -name '*.asm' | wc -l) 个, test.sh \$(find lesson* -name 'test.sh' | wc -l) 个, README \$(find . -name 'README.md' | wc -l) 个\" && \
      echo \"AppleDouble 垃圾文件: \$(find . -name '._*' | wc -l) 个\""

echo
echo "==> 逐个 .asm 编译诊断"
$SSH "cd $REMOTE
  fail=0; ok=0
  for f in \$(find lesson* -name '*.asm' | sort); do
    d=\$(dirname \$f); b=\$(basename \$f .asm)
    case \$b in lc_*) cc='gcc -no-pie -Wall -O0';; *) cc='ld';; esac
    if ! err=\$(cd \$d && nasm -f elf64 -g -F dwarf -I ../include -o /tmp/\$b.o \$b.asm 2>&1); then
      echo \"[NASM错误] \$f\"; echo \"\$err\" | head -5 | sed 's/^/    /'; fail=\$((fail+1)); continue
    fi
    if ! err=\$(cd \$d && \$cc -o /tmp/\$b.bin /tmp/\$b.o 2>&1); then
      echo \"[链接错误] \$f\"; echo \"\$err\" | head -5 | sed 's/^/    /'; fail=\$((fail+1)); continue
    fi
    ok=\$((ok+1))
  done
  echo \"编译通过 \$ok 个，失败 \$fail 个\""

echo
echo "==> make -k all"
$SSH "cd $REMOTE && make -k all > /tmp/all.log 2>&1; echo \"make all 退出码=\$?\"; grep -Ei 'error|错误|undefined|No such file' /tmp/all.log | head -30; echo '(以上为错误摘要，空则无错)'"

echo
echo "==> make test"
$SSH "cd $REMOTE && make test 2>&1 | tail -70"

echo
echo "==> 运行抽查（stdin=/dev/null，2 秒超时）"
$SSH "cd $REMOTE
  for p in \$(find lesson* -maxdepth 1 -type f -perm -u+x ! -name '*.sh' ! -name '*.c' | sort); do
    out=\$(timeout 2 \"\$p\" < /dev/null 2>/tmp/e.\$\$); rc=\$?
    printf '%-34s rc=%-4s 输出%6s字节' \"\$p\" \"\$rc\" \"\$(printf '%s' \"\$out\" | wc -c)\"
    case \$rc in 124) printf ' [超时/死循环]';; 139) printf ' [段错误]';; 136) printf ' [除零]';; 134) printf ' [abort]';; esac
    [ -s /tmp/e.\$\$ ] && printf ' stderr=%s' \"\$(head -c 80 /tmp/e.\$\$ | tr '\n' ' ')\"
    printf '  首行=%s\n' \"\$(printf '%s' \"\$out\" | head -1 | cut -c1-58)\"
  done
  rm -f /tmp/e.*"
echo
echo "==> 体检结束"

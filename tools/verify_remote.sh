#!/usr/bin/env bash
# ===========================================================================
# 把教程同步到远端主机并完整验证：编译全部课程 + 运行全部测试 + 抽查输出
#
#   tools/verify_remote.sh [user@host] [远端目录]
# 默认： root@104.129.2.168  /root/study/as
#
# 用法示例： tools/verify_remote.sh
# ===========================================================================
set -u
HOST="${1:-root@104.129.2.168}"
REMOTE="${2:-/root/study/as}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARBALL="$(mktemp -t asm-tutorial).tar.gz"

# macOS 上必须关掉 AppleDouble 打包：否则远端会出现 ._xxx.asm 垃圾文件，
# 被每课 Makefile 的 $(wildcard *.asm) 当成源文件而链接失败。
export COPYFILE_DISABLE=1

cleanup() { rm -f "$TARBALL"; }
trap cleanup EXIT

echo "==> 打包 $ROOT"
tar --exclude='._*' --exclude='.DS_Store' --exclude='*.o' \
    -czf "$TARBALL" -C "$ROOT" \
    Makefile INSTRUCTOR.md README.md DEPLOY.md include lesson[0-9][0-9] tools 2>/dev/null

echo "==> 上传到 $HOST:$REMOTE"
ssh "$HOST" "mkdir -p $REMOTE"
scp -q "$TARBALL" "$HOST:/tmp/asm-tutorial.tar.gz"

echo "==> 远端解包并检查"
ssh "$HOST" "set -e
  rm -rf $REMOTE/*
  tar -xzf /tmp/asm-tutorial.tar.gz -C $REMOTE
  cd $REMOTE
  echo '--- 文件清单 ---'
  find . -name '*.asm' | sort | sed 's|^\./||'
  echo '--- 目录 ---'
  ls -d lesson* | tr '\n' ' '; echo
"

echo "==> 远端编译（make -k all）"
ssh "$HOST" "cd $REMOTE && make -k all 2>&1 | tail -40"

echo "==> 远端测试（make test）"
ssh "$HOST" "cd $REMOTE && make test 2>&1 | tail -60"

echo "==> 远端抽查：每个可执行文件运行一遍（stdin=/dev/null，3 秒超时）"
ssh "$HOST" "cd $REMOTE
  for d in lesson*; do
    for p in \$(find \$d -maxdepth 1 -type f -perm -u+x ! -name '*.sh' ! -name '*.asm' 2>/dev/null); do
      printf '%-28s : ' \"\$p\"
      timeout 3 \"\$p\" < /dev/null > /tmp/out.\$\$ 2>/tmp/err.\$\$; rc=\$?
      printf 'rc=%-3s out=%s bytes' \"\$rc\" \"\$(wc -c < /tmp/out.\$\$)\"
      [ -s /tmp/err.\$\$ ] && printf ' stderr=%s' \"\$(head -c 120 /tmp/err.\$\$ | tr '\n' ' ')\"
      [ \$rc -eq 124 ] && printf '  <== 超时(死循环?)'
      [ \$rc -ge 128 ] && printf '  <== 非正常退出'
      echo
    done
  done
  rm -f /tmp/out.* /tmp/err.*
"

#!/usr/bin/env bash
# ===========================================================================
# 生成全书源代码清单SOURCE_LISTING.txt：把 15 课所有 .asm/.c 按课号顺序拼接，
# 方便一次性通读或打印。同时生成每课文件树 FILE_TREE.txt。
#   tools/source_listing.sh [教程根目录]
# ===========================================================================
set -eu
ROOT="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
cd "$ROOT"

OUT="SOURCE_LISTING.txt"
TREE="FILE_TREE.txt"

{
  echo "=========================================================================="
  echo " x86-64 汇编语言教程（NASM）—— 全书源代码清单"
  echo " 生成时间：$(date '+%Y-%m-%d %H:%M:%S')"
  echo " 共 $(find lesson[0-9][0-9] -name '*.asm' | wc -l | tr -d ' ') 个汇编源文件，"
  echo "    $(find lesson[0-9][0-9] -name '*.c' | wc -l | tr -d ' ') 个 C 源文件，"
  echo "    $(find lesson[0-9][0-9] -name 'Makefile' | wc -l | tr -d ' ') 个课程 Makefile。"
  echo "=========================================================================="
  echo
} > "$OUT"

for d in $(ls -d lesson[0-9][0-9] | sort); do
  title=$(head -1 "$d/README.md" 2>/dev/null | sed 's/^#[[:space:]]*//')
  {
    echo
    echo "##########################################################################"
    echo "# $d  ${title:-（无 README）}"
    echo "##########################################################################"
    echo
    for f in $(find "$d" -maxdepth 1 -type f \( -name '*.asm' -o -name '*.c' -o -name '*.inc' -o -name '*.h' \) | sort); do
      echo "-------------------------------- 文件：$f --------------------------------"
      echo
      cat "$f"
      echo
    done
  } >> "$OUT"
  echo "已收录 $d"
done

{
  echo "x86-64 汇编语言教程 文件树（$(date '+%Y-%m-%d')）"
  echo
  if command -v tree >/dev/null 2>&1; then
    tree -a -I '*.o|*.bin' --charset=ascii
  else
    find . -type f ! -name '*.o' | sed 's|^\./||' | sort
  fi
} > "$TREE"

echo "已生成：${ROOT}/${OUT}（$(wc -l < "${OUT}" | tr -d ' ') 行）"
echo "已生成：${ROOT}/${TREE}"

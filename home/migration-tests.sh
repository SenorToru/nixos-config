#!/usr/bin/env bash
#
# state-sync 的回归测试。
#
# 接缝（seam）是 **CLI 边界**：给定一个临时 HOME 和一个临时状态仓库，
# 跑 `state-sync push` / `restore`，断言文件的**最终位置和内容**。
# 不测任何内部函数。
#
# 为什么只测 state-sync 不测 migration-check：
# restore 是这两个命令里唯一会**覆盖 $HOME 现有文件**的操作，
# 写错了不可逆；migration-check 是只读的，误报顶多浪费几分钟。
# 测试力度按后果分配。
#
# 由 home/migration.nix 的 migrationTests 派生在**构建期**执行 ——
# 测试不过就 build 不出来，nrb 直接停在这一步。
# 手动跑：
#   STATE_SYNC_BIN=$(command -v state-sync) bash home/migration-tests.sh

set -uo pipefail

SS="${STATE_SYNC_BIN:?需要 STATE_SYNC_BIN 指向 state-sync 可执行文件}"

fails=0
pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1" >&2
  fails=$((fails + 1))
}

newenv() {
  local root
  root=$(mktemp -d)
  mkdir -p "$root/home" "$root/repo"
  git -C "$root/repo" init -q 2>/dev/null
  printf '%s' "$root"
}

# ---------------------------------------------------------------------
# 1. push 只收清单里的东西
#
# 为什么值得测：清单是 migration.nix 里的一个 Nix 列表，改动很随意。
# 如果 push 变成「把 ~/.config 整个收进去」，秘密（~/.config/gh 的 token）
# 会被推进一个 GitHub 仓库。这是最坏的失败模式，必须有测试盯着。
# ---------------------------------------------------------------------
root=$(newenv)
mkdir -p "$root/home/.config/fcitx5" "$root/home/.config/gh"
echo "profile-content" > "$root/home/.config/fcitx5/profile"
echo "SECRET-TOKEN"    > "$root/home/.config/gh/hosts.yml"

HOME="$root/home" STATE_REPO="$root/repo" "$SS" push >/dev/null 2>&1

if [ -f "$root/repo/.config/fcitx5/profile" ]; then
  pass "push 收了清单里的 .config/fcitx5/profile"
else
  fail "push 没收清单里的 .config/fcitx5/profile"
fi

if [ -e "$root/repo/.config/gh" ]; then
  fail "push 把清单外的 .config/gh 收进去了（那里面是 token！）"
else
  pass "push 没碰清单外的 .config/gh"
fi
rm -rf "$root"

# ---------------------------------------------------------------------
# 2. restore 不动清单外的文件
#
# 为什么值得测：restore 会 rm -rf 目标再 cp。如果路径计算写错
# （比如少了一层 dirname），可能删掉 $HOME 下不该删的东西。
# ---------------------------------------------------------------------
root=$(newenv)
mkdir -p "$root/repo/.config/fcitx5" "$root/home/.config/fcitx5" "$root/home/Documents"
echo "from-repo"  > "$root/repo/.config/fcitx5/profile"
echo "old"        > "$root/home/.config/fcitx5/profile"
echo "my-notes"   > "$root/home/Documents/notes.txt"
echo "untouched"  > "$root/home/.config/fcitx5/unrelated"

HOME="$root/home" STATE_REPO="$root/repo" "$SS" restore >/dev/null 2>&1

if [ "$(cat "$root/home/.config/fcitx5/profile" 2>/dev/null)" = "from-repo" ]; then
  pass "restore 用仓库内容覆盖了目标文件"
else
  fail "restore 没能覆盖目标文件"
fi

if [ "$(cat "$root/home/Documents/notes.txt" 2>/dev/null)" = "my-notes" ]; then
  pass "restore 没动清单外的 ~/Documents"
else
  fail "restore 动了清单外的 ~/Documents"
fi

if [ "$(cat "$root/home/.config/fcitx5/unrelated" 2>/dev/null)" = "untouched" ]; then
  pass "restore 没误删同目录下清单外的文件"
else
  fail "restore 误删了同目录下清单外的文件"
fi
rm -rf "$root"

# ---------------------------------------------------------------------
# 3. 目录类条目整个搬（mozc 的 .encrypt_key.db 必须跟着走）
#
# 为什么值得测：清单里 .config/mozc 是**目录**，而
# .local/state/theme/current 是**文件**。两种都要成立。
# mozc 少搬一个 .encrypt_key.db，学习记录就全丢且看不出来。
# ---------------------------------------------------------------------
root=$(newenv)
mkdir -p "$root/home/.config/mozc"
echo "history" > "$root/home/.config/mozc/.history.db"
echo "key"     > "$root/home/.config/mozc/.encrypt_key.db"

HOME="$root/home" STATE_REPO="$root/repo" "$SS" push >/dev/null 2>&1

if [ -f "$root/repo/.config/mozc/.encrypt_key.db" ] \
   && [ -f "$root/repo/.config/mozc/.history.db" ]; then
  pass "push 把 mozc 整个目录搬了（含 .encrypt_key.db）"
else
  fail "push 漏了 mozc 目录里的文件"
fi
rm -rf "$root"

# ---------------------------------------------------------------------
# ---------------------------------------------------------------------
# 4. push 剔掉日志 / 锁文件 / IPC 套接字路径
#
# 为什么值得测：清单里有几项是**整个目录**，目录里混着运行时垃圾。
# .session.ipc 记的是本机的套接字路径，拷到新机器上是错的；
# *.log 每次用输入法都在变，会把 git 历史刷满噪音。
# 这些都不会报错，只会安静地污染仓库 —— 正是需要测试盯着的那种。
# ---------------------------------------------------------------------
root=$(newenv)
mkdir -p "$root/home/.config/mozc"
echo real   > "$root/home/.config/mozc/.history.db"
echo log    > "$root/home/.config/mozc/mozc_server.log"
echo lock   > "$root/home/.config/mozc/.server.lock"
echo ipc    > "$root/home/.config/mozc/.session.ipc"

HOME="$root/home" STATE_REPO="$root/repo" "$SS" push >/dev/null 2>&1

if [ -f "$root/repo/.config/mozc/.history.db" ]; then
  pass "push 保留了真正的数据文件"
else
  fail "push 把真正的数据文件也剔掉了"
fi

junk_left=0
for j in mozc_server.log .server.lock .session.ipc; do
  [ -e "$root/repo/.config/mozc/$j" ] && junk_left=$((junk_left+1))
done
if [ "$junk_left" -eq 0 ]; then
  pass "push 剔掉了日志 / 锁 / IPC 文件"
else
  fail "push 把 $junk_left 个运行时垃圾收进了仓库"
fi
rm -rf "$root"

# 5. 没有状态仓库时要报错退出，不能静默什么都不做
# ---------------------------------------------------------------------
root=$(mktemp -d)
mkdir -p "$root/home"
if HOME="$root/home" STATE_REPO="$root/nonexistent" "$SS" push >/dev/null 2>&1; then
  fail "仓库不存在时 push 应该失败退出"
else
  pass "仓库不存在时 push 报错退出"
fi
rm -rf "$root"

echo
if [ "$fails" -gt 0 ]; then
  echo "$fails 个用例失败" >&2
  exit 1
fi
echo "全部通过"

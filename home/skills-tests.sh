#!/usr/bin/env bash
#
# `skills` 命令的回归测试。
#
# 接缝（seam）是 **CLI 边界**：给定一个临时 HOME、一个 pool 夹具、一份
# disabled 状态文件，跑 `skills sync` / `on` / `off`，断言三个目标目录里
# 符号链接的**最终状态**。不测任何内部函数（fm、catalog_chars 那些），
# 因为它们是实现细节，改内部结构不该让测试变红。
#
# 这个文件由 home/agent-skills.nix 里的 skillsTests 派生在**构建期**执行 ——
# 测试不过就 build 不出来，nixos-rebuild 直接停在这一步。
# 手动跑：
#   SKILLS_BIN=$(command -v skills) bash home/skills-tests.sh

set -uo pipefail

SKILLS="${SKILLS_BIN:?需要 SKILLS_BIN 指向 skills 可执行文件}"

fails=0
pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1" >&2
  fails=$((fails + 1))
}

# 造一个最小的 skill 夹具：pool/<名字>/SKILL.md，frontmatter 齐全。
# 缺 name 或 description 的 SKILL.md 会被各家工具静默跳过，夹具必须是合法的。
mkfixture() {
  local pool="$1" name="$2"
  mkdir -p "$pool/$name"
  cat > "$pool/$name/SKILL.md" <<EOF
---
name: $name
description: fixture skill for tests
---

body
EOF
}

# ---------------------------------------------------------------------
# 规则：sync 只剪「原始链接目标落在 pool 里」的符号链接。
#
# 为什么这条值得单独测：~/.claude/skills/ 是用户自己也会往里放东西的目录，
# 误删不可逆，而剪枝逻辑又必须存在（换了 store 路径之后得能清断链）。
# 这两个要求拉扯的地方就是最容易写错的地方。
# ---------------------------------------------------------------------
t_sync_keeps_foreign_symlinks() {
  local home pool outside
  home="$(mktemp -d)"
  pool="$(mktemp -d)"
  outside="$(mktemp -d)"

  mkfixture "$pool" alpha
  mkdir -p "$home/.local/share"
  ln -s "$pool" "$home/.local/share/agent-skills"

  # 用户自己装的 skill：一个指向 pool 之外的符号链接
  mkdir -p "$outside/my-own" "$home/.claude/skills"
  ln -s "$outside/my-own" "$home/.claude/skills/my-own"

  HOME="$home" "$SKILLS" sync > /dev/null

  if [ -L "$home/.claude/skills/my-own" ] && [ -e "$home/.claude/skills/my-own" ]; then
    pass "pool 之外的符号链接在 sync 之后还在"
  else
    fail "pool 之外的符号链接被 sync 删掉了"
  fi

  # 守住测试本身：如果 sync 其实什么都没干，上面那条会「假阳性」地通过。
  if [ -L "$home/.claude/skills/alpha" ]; then
    pass "pool 里的 skill 确实被装上了（证明 sync 真的跑了）"
  else
    fail "pool 里的 skill 没装上 —— 上一条断言不可信"
  fi
}

printf 'skills-tests\n'
t_sync_keeps_foreign_symlinks

if [ "$fails" -gt 0 ]; then
  printf '\n%s 条断言失败\n' "$fails" >&2
  exit 1
fi
printf '\n全部通过\n'

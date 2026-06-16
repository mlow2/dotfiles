#!/usr/bin/env bash
# Claude Code status line. Reads the session JSON from stdin, prints one line.
# Requires: jq (parses the session JSON); git is optional (branch segment).
#
# Format:  <dir> | <git-branch> | <model> (<effort>) | <bar> <ctx>% of <max>k
#
# .effort.level is the live session effort (low|medium|high|xhigh|max). It is
# only present when the active model supports reasoning effort, so the "(...)"
# is dropped otherwise. /effort at runtime is reflected on the next render.
#
# The context segment is a 20-wide bar (green <50%, yellow <80%, red >=80%)
# followed by "<used>% of <window-size>k".

input=$(cat)

# jq emits one field per line; read them individually so empty fields survive
# (read/IFS splitting would collapse them) and spaces in values are preserved.
# One read per line keeps this working on macOS's bash 3.2 (no mapfile).
fields=$(printf '%s' "$input" | jq -r '
  .workspace.current_dir // .cwd // "",
  .model.display_name // .model.id // "?",
  .effort.level // "",
  ((.context_window.used_percentage // -1) | round | if . < 0 then "" else tostring end),
  (.context_window.context_window_size // 0 | tostring)
')
{ IFS= read -r dir; IFS= read -r model; IFS= read -r effort
  IFS= read -r ctx;  IFS= read -r ctxsize; } <<< "$fields"

base=${dir##*/}
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

dim=$'\033[2m'; cyan=$'\033[36m'; grn=$'\033[32m'; ylw=$'\033[33m'
red=$'\033[31m'; mag=$'\033[35m'; rst=$'\033[0m'
sep=" ${dim}|${rst} "

# 20-wide bar colored by usage; filled with '|', remainder dimmed '.'.
build_bar() {
  local pct=$1 width=20 filled empty color fill rest
  filled=$(( width * pct / 100 ))
  (( filled > width )) && filled=$width
  (( filled < 0 )) && filled=0
  empty=$(( width - filled ))
  if   (( pct < 50 )); then color=$grn
  elif (( pct < 80 )); then color=$ylw
  else                      color=$red
  fi
  fill=$(printf '%*s' "$filled" '' | tr ' ' '|')
  rest=$(printf '%*s' "$empty" '' | tr ' ' '.')
  printf '%s%s%s%s%s' "$color" "$fill" "$dim" "$rest" "$rst"
}

line="${cyan}${base}${rst}"
[ -n "$branch" ] && line+="${sep}${grn}${branch}${rst}"
line+="${sep}${mag}${model}${rst}"
[ -n "$effort" ] && line+=" ${dim}(${effort})${rst}"
if [ -n "$ctx" ]; then
  (( ctxsize == 0 )) && ctxsize=200000
  line+="${sep}$(build_bar "$ctx") ${ctx}% of $(( ctxsize / 1000 ))k"
fi

printf '%s' "$line"

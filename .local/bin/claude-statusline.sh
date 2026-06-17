#!/usr/bin/env bash
# Claude Code status line. Reads the session JSON from stdin, prints one line.
# Requires: jq (parses the session JSON); git is optional (branch segment).
#
# Format:  <dir> | <git-branch> | <model> (<effort>) | <bar> <ctx>% of <max>k       5h <p>% (<reset>) · wk <p>%
#
# The usage segment (5h/weekly rate limits) is right-aligned to the terminal
# edge using $COLUMNS, which Claude Code exports to this command.
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
  (.context_window.context_window_size // 0 | tostring),
  ((.rate_limits.five_hour.used_percentage // -1) | round | if . < 0 then "" else tostring end),
  (.rate_limits.five_hour.resets_at // 0 | tostring),
  ((.rate_limits.seven_day.used_percentage // -1) | round | if . < 0 then "" else tostring end)
')
{ IFS= read -r dir; IFS= read -r model; IFS= read -r effort
  IFS= read -r ctx;  IFS= read -r ctxsize
  IFS= read -r u5;   IFS= read -r u5reset; IFS= read -r u7; } <<< "$fields"

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

usage_color() {
  if   (( $1 < 50 )); then printf '%s' "$grn"
  elif (( $1 < 80 )); then printf '%s' "$ylw"
  else                     printf '%s' "$red"
  fi
}

# Visible width of a string in terminal columns: strip ANSI escapes, count
# UTF-8 characters (-CS) so multibyte glyphs like '·' count as one.
vlen() { printf '%s' "$1" | perl -CS -ne 's/\e\[[0-9;]*m//g; print length'; }

line="${cyan}${base}${rst}"
[ -n "$branch" ] && line+="${sep}${grn}${branch}${rst}"
line+="${sep}${mag}${model}${rst}"
[ -n "$effort" ] && line+=" ${dim}(${effort})${rst}"
if [ -n "$ctx" ]; then
  (( ctxsize == 0 )) && ctxsize=200000
  line+="${sep}$(build_bar "$ctx") ${ctx}% of $(( ctxsize / 1000 ))k"
fi

if [ -n "$u5" ]; then
  usage="${dim}5h${rst} $(usage_color "$u5")${u5}%${rst}"
  if (( u5reset > 0 )); then
    rtime=$(date -r "$u5reset" +"%-l:%M%p" 2>/dev/null || date -d "@$u5reset" +"%-l:%M%p" 2>/dev/null)
    rtime=$(printf '%s' "$rtime" | tr 'A-Z' 'a-z')
    [ -n "$rtime" ] && usage+=" ${dim}(${rtime})${rst}"
  fi
  [ -n "$u7" ] && usage+="${sep}${dim}wk${rst} $(usage_color "$u7")${u7}%${rst}"

  # Right-align the usage block. Claude Code renders the statusline a few
  # columns narrower than the $COLUMNS it exports (it truncates/corrupts rows
  # that reach the real edge), so keep the line inside that budget.
  reserve=4
  cols=${COLUMNS:-$(tput cols 2>/dev/null)}; cols=${cols:-80}
  pad=$(( cols - reserve - $(vlen "$line") - $(vlen "$usage") ))
  (( pad < 1 )) && pad=1
  line+=$(printf '%*s' "$pad" '')"$usage"
fi

printf '%s' "$line"

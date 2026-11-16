#!/usr/bin/env bash
# Claude Code status line. Reads the session JSON from stdin, prints one line.
# Requires: jq (parses the session JSON); git is optional (branch segment).
#
# Format:  <dir> | <session-name> | <git-branch> | <model> (<effort>) | <bar> <ctx>% of <max>k       5h <p>% (<reset>) | wk <p>%
#
# Plans without a 5-hour limit show the weekly limit with its reset day:
#   wk <p>% (<day> <reset>)
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
  .session_name // "",
  .model.display_name // .model.id // "?",
  .effort.level // "",
  ((.context_window.used_percentage // -1) | round | if . < 0 then "" else tostring end),
  (.context_window.context_window_size // 0 | tostring),
  ((.rate_limits.five_hour.used_percentage // -1) | round | if . < 0 then "" else tostring end),
  (.rate_limits.five_hour.resets_at // 0 | tostring),
  ((.rate_limits.seven_day.used_percentage // -1) | round | if . < 0 then "" else tostring end),
  (.rate_limits.seven_day.resets_at // 0 | tostring)
')
{ IFS= read -r dir; IFS= read -r name; IFS= read -r model; IFS= read -r effort
  IFS= read -r ctx;  IFS= read -r ctxsize
  IFS= read -r u5;   IFS= read -r u5reset; IFS= read -r u7; IFS= read -r u7reset; } <<< "$fields"

base=${dir##*/}
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

# Long fork and branch names keep the root and the leaf.
if (( ${#name} > 48 )); then
  name="${name:0:16}...${name: -29}"
fi

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
[ -n "$name" ] && line+="${sep}${ylw}${name}${rst}"
[ -n "$branch" ] && line+="${sep}${grn}${branch}${rst}"
line+="${sep}${mag}${model}${rst}"
[ -n "$effort" ] && line+=" ${dim}(${effort})${rst}"
if [ -n "$ctx" ]; then
  (( ctxsize == 0 )) && ctxsize=200000
  line+="${sep}$(build_bar "$ctx") ${ctx}% of $(( ctxsize / 1000 ))k"
fi

# Prints an epoch time in the given date format, with am/pm in lower case.
fmt_reset() {
  local t
  (( $1 > 0 )) || return
  t=$(date -r "$1" +"$2" 2>/dev/null || date -d "@$1" +"$2" 2>/dev/null)
  printf '%s' "$t" | sed 's/AM$/am/; s/PM$/pm/'
}

usage=""
if [ -n "$u5" ]; then
  usage="${dim}5h${rst} $(usage_color "$u5")${u5}%${rst}"
  rtime=$(fmt_reset "$u5reset" "%-l:%M%p")
  [ -n "$rtime" ] && usage+=" ${dim}(${rtime})${rst}"
  [ -n "$u7" ] && usage+="${sep}${dim}wk${rst} $(usage_color "$u7")${u7}%${rst}"
elif [ -n "$u7" ]; then
  usage="${dim}wk${rst} $(usage_color "$u7")${u7}%${rst}"
  rtime=$(fmt_reset "$u7reset" "%a %-l:%M%p")
  [ -n "$rtime" ] && usage+=" ${dim}(${rtime})${rst}"
fi

if [ -n "$usage" ]; then

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

# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# git alias
# Instantly adds modified files to the very last commit, keeping the same message
alias gcaa='git commit -a --amend --no-edit'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# CUDA 13.1
export PATH=/usr/local/cuda-13.1/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda-13.1/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/opt/miniconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/opt/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/opt/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/opt/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# FUNCTIONS GO HERE
pbcopy() {
  if [ -t 0 ]; then
    echo "pbcopy expects stdin" >&2
    return 1
  fi
  base64 | tr -d '\n' | awk '{printf "\033]52;c;%s\a", $0}'
}

clipfile() {
  [ $# -eq 1 ] || { echo "usage: clipfile <file>" >&2; return 1; }
  pbcopy < "$1"
}

# Git Add, Commit in one command
gac() {
    if [ -z "$1" ]; then
        echo "Error: Please provide a commit message."
        echo "Usage: gacp \"your commit message\""
        return 1
    fi
    git commit -am "$1" #  && git pp # if pull and push is desired
}
# Instantly adds modified files to the very last commit, keeping the same message
alias gaca='git commit -a --amend --no-edit'

# 1. Source the git-prompt script (Path varies by OS/distro. This is common for Ubuntu/Debian)
if [ -f /usr/lib/git-core/git-sh-prompt ]; then
    source /usr/lib/git-core/git-sh-prompt
elif [ -f /etc/bash_completion.d/git-prompt ]; then
    source /etc/bash_completion.d/git-prompt
fi

# 2. Enable extra Git status indicators (optional but recommended)
export GIT_PS1_SHOWDIRTYSTATE=1      # Shows * for unstaged, + for staged
export GIT_PS1_SHOWUNTRACKEDFILES=1  # Shows % for untracked files
export GIT_PS1_SHOWUPSTREAM="auto"   # Shows <, >, =, or <> for sync status

# 3. Set your PS1 prompt to include the Git info AND preserve colors.
# This creates: Green user@host, Blue path, and Cyan git info.
# export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[01;36m\]$(__git_ps1 " (%s)")\[\033[00m\]\$ '
# Compressed Prompt: green current_dir, cyan git_info.
# Example output: my_project|main*+ $
export PS1='\[\033[01;32m\]\W\[\033[01;36m\]$(__git_ps1 "|%s")\[\033[00m\]\$ '


# Enable Vim keybindings in Bash (before ble.sh)
# set -o vi

# 4. Source ble.sh at the VERY END of your .bashrc
source ~/ble.sh/out/ble.sh

# 
# # 5. ble.sh custom keybindings (Must come AFTER sourcing ble.sh)
# # Maps Ctrl-l to specifically accept the auto-suggestion
# # ble-bind -f 'C-l' auto_complete/insert # this replaces default C-l to clear screen
# 
# # Tell ble.sh to use a beam cursor in Insert mode and a block in Normal mode
# bleopt term_cursor_vi_nmode=2  # Block cursor for Normal mode
# bleopt term_cursor_vi_imode=5  # Blinking bar for Insert mode
# 
# # Optional: Add the text [I] or [N] to the right-hand side of your terminal
# bleopt prompt_rps1='\q{mode}'
# 
# # Mirror custom Vim mappings in ble.sh Normal mode
# ble-bind -m vi_nmap 'H' '^'
# ble-bind -m vi_nmap 'L' '$'
# ble-bind -m vi_nmap 'Y' 'y$'
# 
# 

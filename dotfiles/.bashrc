# SuperLite OS — Bash Config
[[ $- != *i* ]] && return

# Prompt
PS1='\[\033[1;31m\]SuperLite\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '

# Aliases
alias ls='ls --color=auto --group-directories-first'
alias ll='ls -la'
alias la='ls -a'
alias grep='grep --color=auto'
alias df='df -h'
alias free='free -m'
alias cls='clear'
alias vi='nvim'
alias vim='nvim'

# History
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth
shopt -s histappend
shopt -s checkwinsize

# Completion
[ -f /etc/profile.d/bash-completion.sh ] && . /etc/profile.d/bash-completion.sh

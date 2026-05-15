# SuperLite OS — Bash Config

source /etc/bash/bash_completion.sh 2>/dev/null

alias ls='ls --color=auto'
alias ll='ls -lav --ignore=..'
alias l='ls -lav --ignore=.?*'
alias reboot='sudo reboot'
alias conf='micro ~/.config/labwc/rc.xml'
alias conf-bar='micro ~/.config/waybar/config'
alias conf-term='micro ~/.config/foot/foot.ini'
alias waykill='killall waybar && waybar &'

PS1='[\u@\W]\$ '

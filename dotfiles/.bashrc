#
# ~/.bashrc
#
# Riccardo Palombo - https://riccardo.im
# Preparato per la community Patreon: patreon.com/riccardopalombo
# Qualche alias utile (bisogna installare exa!)
#

 alias ls='ls --color=auto'
 alias ll='ls -lav --ignore=..'   # show long listing of all except ".."
 alias l='ls -lav --ignore=.?*'   # show long listing but no hidden dotfiles except "."
 alias reboot='sudo reboot'
 alias conf='micro ~/.config/labwc/rc.xml'
 alias conf-bar='micro ~/.config/waybar/config'
 alias conf-term='micro ~/.config/foot/foot.ini'
 alias waykill='killall waybar && waybar &'

#alias dots='cd ~/code/dotfiles && lazygit'
#alias labwc='dbus-launch --exit-with-session labwc'



#PS1='[\u@\h \W]\$ '
#PS1='[\u@\W]\$ '
PS1='\[\e[1;37m\][\u@\W]\$\[\e[0m\] '

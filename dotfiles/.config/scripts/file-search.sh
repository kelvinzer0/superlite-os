#!/bin/sh
# File search using tofi + find
# Searches common file types in $HOME

SEARCH_DIRS="$HOME"
EXTENSIONS="txt|md|pdf|doc|docx|odt|xls|xlsx|ods|csv|ppt|pptx|png|jpg|jpeg|gif|svg|mp4|mkv|mp3|flac|zip|tar|gz|json|xml|yaml|yml|html|css|sh|py|lua|go|rs|c|h|cpp|java"

SELECTED=$(find $SEARCH_DIRS -maxdepth 5 -type f \
    | grep -iE "\.($EXTENSIONS)$" \
    | sed "s|$HOME/||" \
    | tofi --prompt-text "File > " --num-results 10)

if [ -n "$SELECTED" ]; then
    "$HOME/.config/scripts/open-with-web.sh" "$HOME/$SELECTED"
fi

#!/bin/bash
if [ -z "$1" ]; then
    TARGET="/Volumes/hb"
else
    TARGET="$1"
fi
if [ ! -e "$TARGET" ]; then
    echo "$TARGET does not exist"
    exit 1
fi

rsync --progress --recursive --update --exclude .svn --exclude .git "`dirname $0`" "$TARGET"

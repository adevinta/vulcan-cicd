#!/bin/bash
# Copyright 2021 Adevinta


function patch_folder() {
    if [ ! -d $1 ]; then
        echo "Usage $0 path"
        exit 1
    fi
    BASE=$1

    if [[ ! -x "$(which rg)" ]]; then
        echo "We need to install rg (ripgrep)"
        exit 1
    fi

    if [[ "$(uname)" == "Darwin" ]]; then
        echo "Not compatible with Macos"
        exit 1
    fi

    COMMON_MSG="Copyright $(date +"%Y") Adevinta"
    COMMON_PATTERN="Copyright\s+20[0-9]{2}\s+Adevinta"

    # Update existing year
    rg -l -e ''$COMMON_PATTERN'' $BASE | \
        xargs -r -n1 sed -i 's|Copyright[ \t]\+20[0-9]\{2\}[ \t]\+Adevinta|'"$COMMON_MSG"'|g'

    # Files with hash-bang notation (shell, python, ruby)
    COMMENT="# $COMMON_MSG\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' -t py -t sh -t ruby $BASE | \
        xargs -r -n1 sed -i '1s|^\(#!/.\+\)|\1\n'"$COMMENT"'|'

    COMMENT="# $COMMON_MSG\n\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' \
        -t ruby -t py -t docker -t sh -t yaml -t toml -g '!.travis.y*ml' $BASE | \
        xargs -r -n1 sed -i '1s|^|'"$COMMENT"'|'

    COMMENT="/*\n$COMMON_MSG\n*/\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' -t go $BASE | \
        xargs -r -n1 sed -i '1s|^|'"$COMMENT"'|'
}

function add_copyright() {
    if [ ! -d $1 ]; then
        echo "Usage $0 path"
        exit 1
    fi
    BASE=$1

    cp CONTRIBUTING.md $BASE/
    cp DISCLAIMER.md $BASE/
    cp LICENSE $BASE/
}

patch_folder $1
add_copyright $1

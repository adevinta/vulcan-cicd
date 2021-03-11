#!/bin/bash

set -e

set -o errexit
set -o nounset

function patch_files() {
    BASE=${1:-.}

    COMMON_MSG="Copyright $(date +"%Y") Adevinta"
    COMMON_PATTERN="Copyright\s+20[0-9]{2}\s+Adevinta"

    # Update existing year
    rg -l -e ''$COMMON_PATTERN'' $BASE | \
        xargs -r sed -i 's/Copyright[ \t]\+20[0-9]\{2\}[ \t]\+Adevinta/'"$COMMON_MSG"'/g'

    # Files with hash-bang notation (shell, python, ruby)
    COMMENT="# $COMMON_MSG\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' -t py -t sh -t ruby $BASE | \
        xargs -r -n1 sed -i '1s|^\(#!/.\+\)|\1\n'"$COMMENT"'|'

    COMMENT="# $COMMON_MSG\n\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' \
        -t ruby -t py -t docker -t sh -t yaml -t toml -g '!.travis.yml' $BASE | \
        xargs -r -n1 sed -i '1s!^!'"$COMMENT"'!'

    COMMENT="/*\n$COMMON_MSG\n*/\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' -t go $BASE | \
        xargs -r -n1 sed -i '1s!^!'"$COMMENT"'!'
}

function add_copyright() {
    BASE=${1:-.}

    cp CONTRIBUTING.md $BASE/
    cp DISCLAIMER.md $BASE/
    cp LICENSE $BASE/
}

patch_files $1
# add_copyright $1

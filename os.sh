#!/bin/bash

set -e

set -o errexit
set -o nounset

function patch_files() {
    BASE=${1:-.}

    COMMON_MSG="Copyright $(date +"%Y") Adevinta"
    COMMON_PATTERN="Copyright\s+20[0-9]{2}\s+Adevinta"

    # Update existing years
    rg -l -e ''$COMMON_PATTERN'' $BASE | \
        xargs -r sed -i 's/Copyright[ \t]\+20[0-9]\{2\}[ \t]\+Adevinta/'"$COMMON_MSG"'/g'

    COMMENT="/*\n$COMMON_MSG\n*/\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' -t go $BASE | \
        xargs -r -n1 sed -i '1s!^!'"$COMMENT"'!'

    COMMENT="# $COMMON_MSG\n\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' -t ruby $BASE | \
        xargs -r -n1 sed -i '1s!^!'"$COMMENT"'!'

    COMMENT="# $COMMON_MSG\n\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' -t py $BASE | \
        xargs -r -n1 sed -i '1s!^!'"$COMMENT"'!'

    COMMENT="# $COMMON_MSG\n\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' -t docker $BASE | \
        xargs -r -n1 sed -i '1s!^!'"$COMMENT"'!'

    COMMENT="# $COMMON_MSG\n\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' -t yaml -t toml -g '!.travis.yml' $BASE | \
        xargs -r -n1 sed -i '1s!^!'"$COMMENT"'!'

    COMMENT="# $COMMON_MSG\n\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' -t sh $BASE | \
        xargs -r -n1 sed -i '/^#!\/.\+sh/a '"$COMMENT"''
}

function add_copyright() {
    BASE=${1:-.}

    cp CONTRIBUTING.md $BASE/
    cp DISCLAIMER.md $BASE/
    cp LICENSE $BASE/
}

patch_files $1
# add_copyright $1

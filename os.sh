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

    SED=sed
    if [[ "$(uname)" == "Darwin" ]]; then
        if [[ ! -x "$(which gsed)" ]]; then
            echo "We need to use gnu-sed in mac (brew install gsed)"
            exit 1
        fi
        SED=gsed
    fi

    COMMON_MSG="Copyright $(date +"%Y") Adevinta"
    COMMON_PATTERN="Copyright\s+20[0-9]{2}\s+Adevinta"

    # Update existing year
    rg -l -e ''$COMMON_PATTERN'' $BASE | \
        xargs -r -n1 $SED -i 's|Copyright[ \t]\+20[0-9]\{2\}[ \t]\+Adevinta|'"$COMMON_MSG"'|g'

    # Files with hash-bang notation (shell, python, ruby)
    COMMENT="# $COMMON_MSG"
    rg --files-without-match ''"$COMMON_PATTERN"'' -t py -t sh -t ruby $BASE | \
        xargs -r -n1 $SED -i '1s|^\(#!/.\+\)|\1\n\n'"$COMMENT"'|'

    COMMENT="# $COMMON_MSG\n\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' \
        -t ruby -t py -t docker -t sh $BASE | \
        xargs -r -n1 $SED -i '1s|^|'"$COMMENT"'|'

    COMMENT="/*\n$COMMON_MSG\n*/\n\n"
    rg --files-without-match ''"$COMMON_PATTERN"'' -t go -g '!vendor/*' $BASE | \
        xargs -r -n1 $SED -i '1s|^|'"$COMMENT"'|'
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

function patch_repo() {
    if [[ ! -x "$(which gh)" ]]; then
        echo "We need github-cli"
        exit 1
    fi

    REPO_FOLDER=$(mktemp -d)
    echo "Working in $REPO_FOLDER"

    gh repo clone $1 $REPO_FOLDER
    patch_folder $REPO_FOLDER
    add_copyright $REPO_FOLDER
    pushd $REPO_FOLDER
    FIX_SLUG=$(date +"%Y%m%d_%s")
    git checkout -b os_update_$FIX_SLUG
    git add .
    if ! git diff-index --quiet --cached HEAD; then
        git commit -m "Update Open Source"
        gh pr create --fill
    else
        echo "No updates need to be commited"
    fi
    popd
    rm -rf $REPO_FOLDER
}

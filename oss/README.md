# NOTICE updater

We have some scripts to automate the generation of copyright notices.

```sh
source ./oss.sh

# Notice all unnoticed files with 2019 year
patch_folder ./tests/src 2019

```

To update the file's notice year based on year the file was added to the repo:

```sh
YEAR=2021

# Get the last commit of the year
FIRST_COMMIT=$(git rev-list --reverse --after="$YEAR-01-01" master | head -n1)

git diff --name-only --diff-filter=A $FIRST_COMMIT HEAD | \
    xargs -r sed -i 's/Copyright 20[12][0-9][0-9] Adevinta/Copyright '$YEAR' Adevinta/g'
```

To help creating a PR for a github repo:

```sh
source ./oss.sh

patch_github_repo adevinta/vulcan-cicd -i
```

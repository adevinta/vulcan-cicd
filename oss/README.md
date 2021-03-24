# NOTICE updater

We have some scripts to automate the generation of copyright notices.

```sh
source ./oss.sh

# Notice all unnoticed files with 2019 year on this folder
patch_folder ./tests/source 2020

# Compare with the expected results
diff -r ./tests/source ./tests/expected
```

To help creating a PR for a github repo:

```sh
source ./oss.sh

# Create a PR for a given repo
patch_github_repo adevinta/vulcan-cicd -i

# Or to create PRs for a given list of repositories
for repo in $(gh repo list adevinta -L 100 | cut -f1 - | egrep '(vulcan|vulnerability)' | sort)
do
    patch_github_repo $repo -i
done
```

To update the file's notice year based on year the file was added to the repo:

```sh
YEAR=2021

# Get the last commit of the year
FIRST_COMMIT=$(git rev-list --reverse --after="$YEAR-01-01" master | head -n1)

git diff --name-only --diff-filter=A $FIRST_COMMIT HEAD | \
    xargs -r sed -i 's/Copyright 20[12][0-9][0-9] Adevinta/Copyright '$YEAR' Adevinta/g'
```

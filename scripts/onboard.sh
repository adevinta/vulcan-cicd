#!/bin/bash

set -e

generate_dependabot() {
echo 'version: 2
updates:'

for f in $(find "$PWD" -type f -name go.mod | sed -r 's|/[^/]+$|/|' | sort | uniq); do
local ignore
echo '- package-ecosystem: "gomod"
  directory: "'"${f/#$PWD}"'"
  schedule:
    interval: "daily"'
ignore=
if grep "github.com/aws/aws-sdk-go" "$f/go.mod" &> /dev/null; then
ignore+='  - dependency-name: "github.com/aws/aws-sdk-go"
    update-types: ["version-update:semver-patch"]
'
fi
if grep "github.com/goadesign/goa" "$f/go.mod" &> /dev/null; then
ignore+='  - dependency-name: "github.com/goadesign/goa"
    update-types: ["version-update:semver-minor", "version-update:semver-major"]
'
fi
if [ "$ignore" != "" ]; then
echo '  ignore:'
echo -n "$ignore"
fi
echo '  labels:
    - "dependencies"'
done

for f in $(find "$PWD" -type f -name "Gemfile" | sed -r 's|/[^/]+$|/|' | sort | uniq); do
echo '- package-ecosystem: "bundler"
  directory: "'"${f/#$PWD}"'"
  schedule:
    interval: "daily"
  labels:
    - "dependencies"'
done

for f in $(find "$PWD" -type f -name "*requirements*.txt" | sed -r 's|/[^/]+$|/|' | sort | uniq); do
echo '- package-ecosystem: "pip"
  directory: "'"${f/#$PWD}"'"
  schedule:
    interval: "daily"
  labels:
    - "dependencies"'
done

for f in $(find "$PWD" -type f -name "package.json" | sed -r 's|/[^/]+$|/|' | sort | uniq); do
echo '- package-ecosystem: "npm"
  directory: "'"${f/#$PWD}"'"
  schedule:
    interval: "daily"
  labels:
    - "dependencies"'
done

for f in $(find "$PWD" -type f -name Dockerfile | sed -r 's|/[^/]+$|/|' | sort | uniq); do
echo '- package-ecosystem: "docker"
  directory: "'"${f/#$PWD}"'"
  schedule:
    interval: "weekly"
  labels:
    - "dependencies"'
done

echo '- package-ecosystem: "github-actions"
  directory: "/"
  schedule:
    interval: "weekly"
  labels:
    - "dependencies"'
}

GITHUB_STEP_SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/stderr}

gh repo set-default "$REPOSITORY"

DEFAULT_BRANCH=$(gh api "repos/$REPOSITORY" --jq '.default_branch')

git config --global user.name "purple-team-service-user"
git config --global user.email "vulcan@example.org"

PR=$(gh pr list --author purple-team-service-user -s open --json number --jq '.[] | .number')
if [[ "$PR" =~ [0-9]+ ]]; then
    echo "Updating existing pr $PR"
    gh pr checkout "$PR"
else
    echo "Creating branch"
    git checkout -b cicd-onboard
    PR=
fi

# Add the selected workflows
mkdir -p .github/workflows
cp -r "$GITHUB_WORKSPACE/template/." .github
generate_dependabot > .github/dependabot.yml
git add .
if ! git diff-index --quiet --cached HEAD; then
    git commit -a -m "Onboard dependabot workflows" -m "Generated by ${RUN_URL}"
    git push origin cicd-onboard

    if [ "$PR" == "" ]; then
        gh pr create -f --body "Generated by ${RUN_URL}"
        echo "* :white_check_mark: Created PR waiting for review $(gh pr view --json url -q .url)" >> "$GITHUB_STEP_SUMMARY"
    else
        gh pr comment -b "Updated by ${RUN_URL}"
        echo "* :white_check_mark: Updated PR waiting for review $(gh pr view --json url -q .url)" >> "$GITHUB_STEP_SUMMARY"
    fi

else

    echo "* :white_check_mark: No changes needs to be pushed" >> "$GITHUB_STEP_SUMMARY"

fi

if [ "$DEPENDABOT_AUTOMERGE_TOKEN" != "" ]; then
  echo "$DEPENDABOT_AUTOMERGE_TOKEN" | gh secret set DEPENDABOT_AUTOMERGE_TOKEN --app dependabot
  echo "* :white_check_mark: Created dependabot secret \`DEPENDABOT_AUTOMERGE_TOKEN\`" >> "$GITHUB_STEP_SUMMARY"
else
  echo "* :warning: Empty PAT. Skipping \`DEPENDABOT_AUTOMERGE_TOKEN\` dependabot secret creation." >> "$GITHUB_STEP_SUMMARY"
fi

# Create the dependencies label
gh label create dependencies -d "Bump dependencies" -c f29513 || true
echo "* :white_check_mark: Created \`dependencies\` label" >> "$GITHUB_STEP_SUMMARY"

# Allow auto-merge pull requests
gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
    --method PATCH "/repos/$REPOSITORY" \
    -F allow_auto_merge=true > /dev/null
echo "* :white_check_mark: Allowed automerge" >> "$GITHUB_STEP_SUMMARY"

# Activate security scanning
echo '{
    "security_and_analysis": {
        "dependabot_security_updates": {
            "status": "enabled"
        }
    }
}' | gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
    --method PATCH "/repos/$REPOSITORY" \
    --input - > /dev/null
echo "* :white_check_mark: Enabled dependabot security updates" >> "$GITHUB_STEP_SUMMARY"

# # Add protection rules for default branch
# CHECK=
# if [ -f .travis.yml ]; then
#     CHECK="Travis CI - Branch"
# fi

# echo '
# {
#     "enabled": true
#     "required_status_checks": {
#         "strict": true,
#         "contexts": [
#             "'$CHECK'"
#         ]
#     },
#     "required_pull_request_reviews": {
#         "required_approving_review_count": 1
#     },
#     "enforce_admins": false,
#     "restrictions": null
# }' | gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
#     --method PUT "/repos/$REPOSITORY/branches/$DEFAULT_BRANCH/protection" \
#     --input -  > /dev/null
{
echo "* :bangbang: Enable branch protection for $DEFAULT_BRANCH here <https://github.com/$REPOSITORY/settings/branches>"
echo "* :bangbang: Enable 'Dependabot version updates' here <https://github.com/$REPOSITORY/settings/security_analysis>"
echo "* :bangbang: After merge create a release https://github.com/$REPOSITORY/releases/new" 
} >> "$GITHUB_STEP_SUMMARY"

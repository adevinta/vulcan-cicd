#!/bin/bash

set -e

GITHUB_STEP_SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/stderr}

gh repo set-default "$REPOSITORY"

DEFAULT_BRANCH=$(gh api "repos/$REPOSITORY" --jq '.default_branch')

git config --global user.name "purple-team-service-user"
git config --global user.email "vulcan@example.org"

# Add the selected workflows
mkdir -p .github/workflows
cp -r "$GITHUB_WORKSPACE/template/." .github
git checkout -b cicd-onboard
git add .
git commit -a -m "Onboard dependabot workflows"
git push origin cicd-onboard
gh pr create -f --body "After merge create a tag/release."
echo "* :white_check_mark: Created PR waiting for review $(gh pr view --json url -q .url)" >> "$GITHUB_STEP_SUMMARY"

echo "$DEPENDABOT_AUTOMERGE_TOKEN" | gh secret set DEPENDABOT_AUTOMERGE_TOKEN --app dependabot
echo "* :white_check_mark: Created dependabot secret \`DEPENDABOT_AUTOMERGE_TOKEN\`" >> "$GITHUB_STEP_SUMMARY"

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
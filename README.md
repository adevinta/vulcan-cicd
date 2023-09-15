# vulcan-cicd

This repository contains scripts and workflows to automate CI/CD tasks.

## Reusable workflows

### [Approve dependabot PR](.github/workflows/approve-dependabot-pr.yml)

Add this workflow to approve the dependabot pull requests.

The target branch should be protected to require checks to be passed in order to prevent
merging faulty updates.

```yaml
name: Approve dependabot PR

on: pull_request

jobs:
  approve:
    uses: adevinta/vulcan-cicd/.github/workflows/reusable-approve-dependabot-pr.yml@v1
    secrets:
      PAT: ${{ secrets.DEPENDABOT_AUTOMERGE_TOKEN }}
```

### [Release dependabot updates](.github/workflows/release-dependabot-updates.yml)

Add this workflow to automate the release of dependabot updates.

It looks for the commits after the last tag.
In case of all these commits where from dependabot it would bump a new patch tag and generate a release.

```yaml
name: Release dependabot updates

on:

  # To generate a release on every update
  # push:
  #  branches: master

  # To group dependabot updates in the same release
  schedule:
    - cron: '30 5 * * *'

  # To allow manual execution
  workflow_dispatch:

jobs:
  release:
    uses: adevinta/vulcan-cicd/.github/workflows/reusable-release-dependabot-updates.yml@v1
```

### Automatic onboard repositories

The onboarding of a new repository can be done by executing a workflow.

```sh
# Will use existing DEPENDABOT_AUTOMERGE_TOKEN and DEPENDABOT_ONBOARD_AUTOMERGE_TOKEN action secrets.
gh workflow run .github/workflows/onboard.yml -f repository=adevinta/my-repo
```

To use other PATs.

```sh
# Create the secrets (if they doesn't exist).
# Mind not to overwrite valid tokens.
echo MYTOKEN1 | gh secret set MY_DEPENDABOT_ONBOARD_TOKEN --app actions
echo MYTOKEN2 | gh secret set MY_DEPENDABOT_AUTOMERGE_TOKEN --app actions

gh workflow run .github/workflows/onboard.yml -f repository=adevinta/my-repo \
  -f PAT_onboard_secret=MY_DEPENDABOT_ONBOARD_TOKEN \
  -f PAT_automerge_secret=MY_DEPENDABOT_AUTOMERGE_TOKEN
```

See [onboard.yml](.github/workflows/onboard.yml) for details

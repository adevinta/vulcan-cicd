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
    uses: adevinta/vulcan-cicd/.github/workflows/approve-dependabot-pr.yml@master
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
    uses: adevinta/vulcan-cicd/.github/workflows/release-dependabot-updates.yml@master
```

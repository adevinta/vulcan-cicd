# vulcan-cicd

This repository contains scripts and workflows to automate CI/CD tasks.

## Reusable workflows

### [Approve dependabot PR](.github/workflows/approve-dependabot-pr.yml)

Add this workflow to approve the dependabot pull requests.

* Activates auto-merge for **all** dependabot pull requests.
* Approves the dependabot pull requests for `minor` or `patch` updates.
  * `major` updates must be approved.
  * The target branch should be protected to require checks to be passed in order to prevent
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
gh workflow run .github/workflows/onboard.yml -f repository=myorg/my-repo -f environment=myenv
```

Where `myenv` is the environment name that defines the following variables:

* Env `ONBOARD_GH_HOST`: Env with the github host (i.e. `github.com`, `github.example.com`, ...)
* Secret `AUTOMERGE_TOKEN`: PAT for the previous host with `repo`, `org:read` permissions.
  This token will be copied to the `myorg/my-repo` dependabot secret `DEPENDABOT_AUTOMERGE_TOKEN`.
* Secret `ONBOARD_TOKEN`: PAT for the previous host with `repo`, `org:read` and `actions` permissions.
  This token will be used for onboarding the repository (i.e. `myorg/my-repo`)
  * Creating a PR with the workflows and dependabot configs if needed.
  * Creating the `DEPENDABOT_AUTOMERGE_TOKEN` used by the workflows.
  * Creating the label `dependencies`.
  * Enabling `auto-merge` PRs.
  * Enabling Security scanning.

See [onboard.yml](.github/workflows/onboard.yml) for details

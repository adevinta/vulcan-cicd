#!/bin/bash

# Copyright 2020 Adevinta
set -e

########################
# Initalices the environment
#   Logins in the registry
#   Calculates the tags for the docker images based on the git commit, branch, tag:
#   1.- If tag exists the tag
#   2.- If branch 3 tags:  branch branch-shortsha fullsha  (if branch=master rename to latest)
# Envs:
#   ARTIFACTORY_DOCKER_REGISTRY: Optinal registry to use, defaults to dockerhub
#   DOCKER_USERNAME / ARTIFCATORY_USER: Required, the registry user
#   DOCKER_PASSWORD / ARTIFACTORY_PASSWORD: Required, password/token for the registry
#   GITHUB_REPOSITORY / TRAVIS_REPO_SLUG: Provided by Travis / GitHub Actions, repository name.
#   GITHUB_SHA / TRAVIS_COMMIT: Provided by Travis / GitHub Actions, git commit.
#   GITHUB_REF / TRAVIS_TAG: Provided by Travis / GitHub Actins.
#   GITHUB_HEAD_REF / TRAVIS_PULL_REQUEST_BRANCH: Provided by Travis / GitHub Actins.
#   GITHUB_REF / TRAVIS_BRANCH: Provided by Travis / GitHub Actins.
# Sets those env vars:
#   DKR_REGISTRY DKR_USERNAME DKR_PASSWORD DKR_REPO
#   DKR_GIT_TAG DKR_GIT_BRANCH DKR_GIT_SHA DKR_GIT_SHORT_SHA
#   DKR_TAGS
function dkr_init() {
  # Aapt to be compatible with artifactory registry
  DKR_REGISTRY=$ARTIFACTORY_DOCKER_REGISTRY
  DKR_USERNAME=${DOCKER_USERNAME:-$ARTIFACTORY_USER}
  DKR_PASSWORD=${DOCKER_PASSWORD:-$ARTIFACTORY_PWD}
  DKR_REPO=${GITHUB_REPOSITORY:-$TRAVIS_REPO_SLUG}

  DKR_GIT_SHA=${GITHUB_SHA:-$TRAVIS_COMMIT}
  if [[ "$GITHUB_REF" =~ 'refs/DKR_TAGS/' ]]; then
    DKR_GIT_TAG=${GITHUB_REF//refs\/DKR_TAGS\//}
  else
    DKR_GIT_TAG=${DKR_GIT_TAG:-$TRAVIS_TAG}
  fi

  # If it's a pr the head/originator branch.
  DKR_GIT_BRANCH=${GITHUB_HEAD_REF:-$TRAVIS_PULL_REQUEST_BRANCH}

  if [[ "$GITHUB_REF" =~ 'refs/heads/' ]]; then
    DKR_GIT_BRANCH=${GITHUB_REF//refs\/heads\//}
  else
    DKR_GIT_BRANCH=$TRAVIS_BRANCH
  fi

  DKR_GIT_SHORT_SHA=$(echo "${DKR_GIT_SHA}" | cut -c1-7)

  dkr_sanitize "${DKR_REPO}" "name"
  dkr_sanitize "${DKR_USERNAME}" "username"
  dkr_sanitize "${DKR_PASSWORD}" "password"

  local REGISTRY_NO_PROTOCOL
  REGISTRY_NO_PROTOCOL=${DKR_REGISTRY/https:\/\//}
  if [ -n "$DKR_REGISTRY" ] && [[ ${DKR_REPO} == *${REGISTRY_NO_PROTOCOL}* ]]; then
    DKR_REPO="${REGISTRY_NO_PROTOCOL}/${DKR_REPO}"
  fi

  echo "DKR_REPO=${DKR_REPO}"
  echo "DKR_GIT_SHA=${DKR_GIT_SHA}"
  echo "DKR_GIT_BRANCH=${DKR_GIT_BRANCH}"
  echo "DKR_GIT_TAG=${DKR_GIT_TAG}"

  echo "docker login -u ${DKR_USERNAME} ${DKR_REGISTRY}"
  echo "${DKR_PASSWORD}" | docker login -u "${DKR_USERNAME}" --password-stdin "${DKR_REGISTRY}"

  local BRANCH

  if [ -n "$DKR_GIT_TAG" ]; then
    DKR_TAGS=$DKR_GIT_TAG
  elif [ -n "$DKR_GIT_BRANCH" ]; then
    BRANCH=${DKR_GIT_BRANCH//\//-}
    if [ "$BRANCH" = "master" ]; then
      BRANCH=latest
    fi
    DKR_TAGS="${BRANCH} ${BRANCH}-${DKR_GIT_SHORT_SHA} ${DKR_GIT_SHA}"
  else
    DKR_TAGS="${DKR_GIT_SHA}"
  fi;

  echo "DKR_TAGS=$DKR_TAGS"
}

function dkr_sanitize() {
  if [ -z "${1}" ]; then
    >&2 echo "Unable to find the ${2}. Did you set with.${2}?"
    exit 1
  fi
}

########################
# Builds the image
# Envs:
#   DKR_CONTEXT: Optional Build context defaults to .
#   DKR_DOCKERFILE: Optional path to a custom Dockerfile
#   DKR_BUILDOPTIONS: Optional Additional list of parameters to add to the build command.
#   DKR_BUILDARGS: Optional list of build-args to add (i.e. FOO=3 BAR=5)
# Uses those envs:
#   DKR_GIT_SHA: Commit id
#   DKR_TAGS: List of tags to add to the image 
function dkr_build() {
  local CONTEXT BUILDPARAMS BUILDTAGS
  CONTEXT=${DKR_CONTEXT:-.}
  BUILDPARAMS="--build-arg BUILD_RFC3339=$(date -u +"%Y-%m-%dT%H:%M:%SZ") --build-arg COMMIT=$DKR_GIT_SHA"
  BUILDTAGS=""

  if [ -n "${DKR_BUILDOPTIONS}" ]; then
    BUILDPARAMS="${BUILDPARAMS} ${DKR_BUILDOPTIONS}"
  fi

  if [ -n "${DKR_DOCKERFILE}" ]; then
    BUILDPARAMS="${BUILDPARAMS} -f ${DKR_DOCKERFILE}"
  fi
  if [ -n "${DKR_BUILDARGS}" ]; then
    for ARG in $(echo "${DKR_BUILDARGS}" | tr ',' '\n'); do
      BUILDPARAMS="${BUILDPARAMS} --build-arg ${ARG}"
    done
  fi
  for TAG in ${DKR_TAGS}
  do
    BUILDTAGS="${BUILDTAGS}-t ${DKR_REPO}:${TAG} "
  done
  echo "docker build ${BUILDPARAMS} ${BUILDTAGS} ${CONTEXT}"
  eval "docker build ${BUILDPARAMS} ${BUILDTAGS} ${CONTEXT}"
}

########################
# Pushes all the image tags
# Envs:
#   DKR_TAGS: space separated list of image
function dkr_push() {
  for TAG in ${DKR_TAGS}
  do
    echo "docker push ${DKR_REPO}:${TAG}"
    eval "docker push ${DKR_REPO}:${TAG}"
  done
}

########################
# One single process.
# Envs:
#   DKR_TAGS: space separated list of image
function dkr_all() {
    dkr_init

    dkr_build

    dkr_push

    docker logout
}

########################
# Shows information about the rate limit of the current user in dockerhub
# Envs:
#   DOCKER_USERNAME
#   DOCKER_PASSWORD 
function dkr_dockerhub_ratelimit() {
  if [ -n "${DOCKER_USERNAME}" ]; then
    local DKRTOKEN
    echo "Getting token from dockerhub"
    DKRTOKEN=$(curl -s --user "$DOCKER_USERNAME:$DOCKER_PASSWORD" "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token)
    echo "Getting ratelimit"
    curl -s --head -H "Authorization: Bearer $DKRTOKEN" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest
  fi
}

dkr_init

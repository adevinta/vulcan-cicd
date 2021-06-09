#!/bin/bash

# Copyright 2020 Adevinta
set -e

function dkr_init() {
  echo "" # see https://github.com/actions/toolkit/issues/168

  # Aapt to be compatible with artifactory registry
  _DKR_REGISTRY=$ARTIFACTORY_DOCKER_REGISTRY
  _DKR_USERNAME=${DOCKER_USERNAME:-$ARTIFACTORY_USER}
  _DKR_PASSWORD=${DOCKER_PASSWORD:-$ARTIFACTORY_PWD}
  _DKR_REPO=${GITHUB_REPOSITORY:-$TRAVIS_REPO_SLUG}

  _GIT_SHA=${GITHUB_SHA:-$TRAVIS_COMMIT}
  if [[ "$GITHUB_REF" =~ 'refs/_DKR_TAGS/' ]]; then
    _GIT_TAG=${GITHUB_REF//refs\/_DKR_TAGS\//}
  else
    _GIT_TAG=${_GIT_TAG:-$TRAVIS_TAG}
  fi

  # If it's a pr the head/originator branch.
  _GIT_BRANCH=${GITHUB_HEAD_REF:-$TRAVIS_PULL_REQUEST_BRANCH}

  if [[ "$GITHUB_REF" =~ 'refs/heads/' ]]; then
    _GIT_BRANCH=${GITHUB_REF//refs\/heads\//}
  else
    _GIT_BRANCH=$TRAVIS_BRANCH
  fi

  _GIT_SHORT_SHA=$(echo "${_GIT_SHA}" | cut -c1-7)

  echo "_DKR_REPO=${_DKR_REPO}"
  echo "_GIT_SHA=${_GIT_SHA}"
  echo "_GIT_BRANCH=${_GIT_BRANCH}"

  dkr_sanitize "${_DKR_REPO}" "name"
  dkr_sanitize "${_DKR_USERNAME}" "username"
  dkr_sanitize "${_DKR_PASSWORD}" "password"

  local REGISTRY_NO_PROTOCOL
  REGISTRY_NO_PROTOCOL=${_DKR_REGISTRY/https:\/\//}
  if [ -n "$_DKR_REGISTRY" ] && [[ ${_DKR_REPO} == *${REGISTRY_NO_PROTOCOL}* ]]; then
    _DKR_REPO="${REGISTRY_NO_PROTOCOL}/${_DKR_REPO}"
  fi

  echo "docker login -u ${_DKR_USERNAME} ${_DKR_REGISTRY}"
  echo "${_DKR_PASSWORD}" | docker login -u "${_DKR_USERNAME}" --password-stdin "${_DKR_REGISTRY}"

  local BRANCH

  if [ -n "$_GIT_TAG" ]; then
    _DKR_TAGS=$_GIT_TAG
  elif [ -n "$_GIT_BRANCH" ]; then
    BRANCH=${_GIT_BRANCH//\//-}
    if [ "$BRANCH" = "master" ]; then
      BRANCH=latest
    fi
    _DKR_TAGS="${BRANCH} ${BRANCH}-${_GIT_SHORT_SHA} ${_GIT_SHA}"
  else
    _DKR_TAGS="${_GIT_SHA}"
  fi;

  if [ "${INPUT_SNAPSHOT}" = "true" ]; then
    _DKR_TAGS="${_DKR_TAGS} $(date +%Y%m%d%H%M%S)${_GIT_SHORT_SHA}"
  fi

  echo "_DKR_TAGS=$_DKR_TAGS"
}

function dkr_sanitize() {
  if [ -z "${1}" ]; then
    >&2 echo "Unable to find the ${2}. Did you set with.${2}?"
    exit 1
  fi
}

function dkr_build() {
  if [ -e "${INPUT_WORKDIR}" ]; then
    cd "${INPUT_WORKDIR}"
  fi

  BUILDPARAMS="--build-arg BUILD_RFC3339=$(date -u +"%Y-%m-%dT%H:%M:%SZ") --build-arg COMMIT=$_GIT_SHA"
  CONTEXT="."

  if [ -n "${INPUT_BUILDOPTIONS}" ]; then
    BUILDPARAMS="${BUILDPARAMS} ${INPUT_BUILDOPTIONS}"
  fi

  if [ -n "${INPUT_DOCKERFILE}" ]; then
    BUILDPARAMS="${BUILDPARAMS} -f ${INPUT_DOCKERFILE}"
  fi
  if [ -n "${INPUT_BUILDARGS}" ]; then
    for ARG in $(echo "${INPUT_BUILDARGS}" | tr ',' '\n'); do
      BUILDPARAMS="${BUILDPARAMS} --build-arg ${ARG}"
    done
  fi
  if [ -n "${INPUT_CONTEXT}" ]; then
    CONTEXT="${INPUT_CONTEXT}"
  fi

  local BUILDTAGS=""
  for TAG in ${_DKR_TAGS}
  do
    BUILDTAGS="${BUILDTAGS}-t ${_DKR_REPO}:${TAG} "
  done
  echo "docker build ${BUILDPARAMS} ${BUILDTAGS} ${CONTEXT}"
  eval "docker build ${BUILDPARAMS} ${BUILDTAGS} ${CONTEXT}"
}

function dkr_push() {
  for TAG in ${_DKR_TAGS}
  do
    echo "docker push ${_DKR_REPO}:${TAG}"
    eval "docker push ${_DKR_REPO}:${TAG}"
  done
}

function dkr_all() {
    dkr_init

    dkr_build

    dkr_push

    docker logout
}

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

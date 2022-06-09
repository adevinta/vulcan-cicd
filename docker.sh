#!/bin/bash

# Copyright 2020 Adevinta
set -e


function main() {
  echo "" # see https://github.com/actions/toolkit/issues/168

  # Aapt to be compatible with artifactory registry
  INPUT_REGISTRY=${INPUT_REGISTRY:-$ARTIFACTORY_DOCKER_REGISTRY}
  INPUT_USERNAME=${INPUT_USERNAME:-$ARTIFACTORY_USER}
  INPUT_PASSWORD=${INPUT_PASSWORD:-$ARTIFACTORY_PWD}

  # Adapt to be compatible with travis-ci
  INPUT_USERNAME=${INPUT_USERNAME:-$DOCKER_USERNAME}
  INPUT_PASSWORD=${INPUT_PASSWORD:-$DOCKER_PASSWORD}
  INPUT_NAME=${INPUT_NAME:-$GITHUB_REPOSITORY}
  INPUT_NAME=${INPUT_NAME:-$TRAVIS_REPO_SLUG}
  GITHUB_SHA=${GITHUB_SHA:-$TRAVIS_COMMIT}
  SHORT_SHA=${GITHUB_SHA::7}
  GITHUB_REF=${GITHUB_REF:-$TRAVIS_PULL_REQUEST_BRANCH}   # In case of pull request we want the originating branch, not the target.
  GITHUB_REF=${GITHUB_REF:-$TRAVIS_BRANCH}

  if [ "$GITHUB_REF_TYPE" == "tag" ]; then
    INPUT_TAG=${GITHUB_REF_NAME}
  else
    INPUT_TAG=${TRAVIS_TAG}
  fi

  echo "INPUT_NAME=${INPUT_NAME}"
  echo "GITHUB_SHA=${GITHUB_SHA}"
  echo "GITHUB_REF=${GITHUB_REF}"
  echo "INPUT_TAG=${INPUT_TAG}"

  sanitize "${INPUT_NAME}" "name"
  sanitize "${INPUT_USERNAME}" "username"
  sanitize "${INPUT_PASSWORD}" "password"

  REGISTRY_NO_PROTOCOL=${INPUT_REGISTRY#"https://"}
  if uses "${INPUT_REGISTRY}" && ! isPartOfTheName "${REGISTRY_NO_PROTOCOL}"; then
    INPUT_NAME="${REGISTRY_NO_PROTOCOL}/${INPUT_NAME}"
  fi

  translateDockerTag
  echo "TAGS=$TAGS"

  if uses "${INPUT_WORKDIR}"; then
    changeWorkingDirectory
  fi

  echo "${INPUT_PASSWORD}" | docker login -u "${INPUT_USERNAME}" --password-stdin "${INPUT_REGISTRY}"

  FIRST_TAG=$(echo "$TAGS" | cut -d ' ' -f1)
  DOCKERNAME="${INPUT_NAME}:${FIRST_TAG}"
  BUILDPARAMS="--build-arg BUILD_RFC3339=$(date -u +"%Y-%m-%dT%H:%M:%SZ") --build-arg COMMIT=$GITHUB_SHA"
  CONTEXT="."

  if uses "${INPUT_DOCKERFILE}"; then
    useCustomDockerfile
  fi
  if uses "${INPUT_BUILDARGS}"; then
    addBuildArgs
  fi
  if uses "${INPUT_CONTEXT}"; then
    CONTEXT="${INPUT_CONTEXT}"
  fi
  if usesBoolean "${INPUT_CACHE}"; then
    useBuildCache
  fi
  if usesBoolean "${INPUT_SNAPSHOT}"; then
    useSnapshot
  fi

  push

  echo "::set-output name=tag::${FIRST_TAG}"
  DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' ${DOCKERNAME})
  echo "::set-output name=digest::${DIGEST}"

  docker logout
}

function sanitize() {
  if [ -z "${1}" ]; then
    >&2 echo "Unable to find the ${2}. Did you set with.${2}?"
    exit 1
  fi
}

function isPartOfTheName() {
  [ "$(echo "${INPUT_NAME}" | sed -e "s/${1}//g")" != "${INPUT_NAME}" ]
}

function translateDockerTag() {
  local BRANCH
  BRANCH=$(echo "${GITHUB_REF}" | sed -e "s/refs\/heads\///g" | sed -e "s/\//-/g")
  if isGitTag; then

    # If starts with v and it is semver remove the "v" prefix
    # adapted from https://gist.github.com/rverst/1f0b97da3cbeb7d93f4986df6e8e5695 to accept major (v1) and minor (v1.1) 
    if [[ $INPUT_TAG =~ ^v(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?(\.(0|[1-9][0-9]*))?(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$ ]]; then
      TAG="${INPUT_TAG:1}"
    else
      TAG=$INPUT_TAG
    fi

    TAGS=$TAG

    # If is master and is not a pre-release
    if [[ $TAG =~ ^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?(\.(0|[1-9][0-9]*))?$ ]]; then
      TAGS="$TAGS latest"

      IFS='.' read -a strarr <<< "$TAG"
      if [ -n "${strarr[2]}" ]; then
          TAGS="$TAGS ${strarr[0]}.${strarr[1]}"
      fi
      if [ -n "${strarr[1]}" ]; then
          TAGS="$TAGS ${strarr[0]}"
      fi
    fi

  elif isOnMaster; then
    TAGS="edge ${GITHUB_SHA}"
  else
    TAGS="${BRANCH} ${BRANCH}-${SHORT_SHA} ${GITHUB_SHA}"
  fi
}

function isOnMaster() {
  [[ "${BRANCH}" =~ ^(master|main)$ ]]
}

function isGitTag() {
  [ -n "$INPUT_TAG" ]
}

function changeWorkingDirectory() {
  cd "${INPUT_WORKDIR}"
}

function useCustomDockerfile() {
  BUILDPARAMS="${BUILDPARAMS} -f ${INPUT_DOCKERFILE}"
}

function addBuildArgs() {
  for ARG in $(echo "${INPUT_BUILDARGS}" | tr ',' '\n'); do
    BUILDPARAMS="${BUILDPARAMS} --build-arg ${ARG}"
    echo "::add-mask::${ARG}"
  done
}

function useBuildCache() {
  if docker pull "${DOCKERNAME}" 2>/dev/null; then
    BUILDPARAMS="$BUILDPARAMS --cache-from ${DOCKERNAME}"
  fi
}

function uses() {
  [ -n "${1}" ]
}

function usesBoolean() {
  [ -n "${1}" ] && [ "${1}" = "true" ]
}

function useSnapshot() {
  local TIMESTAMP
  TIMESTAMP=$(date +%Y%m%d%H%M%S)
  local SNAPSHOT_TAG="${TIMESTAMP}${SHORT_SHA}"
  TAGS="${TAGS} ${SNAPSHOT_TAG}"
  echo ::set-output name=snapshot-tag::"${SNAPSHOT_TAG}"
}

function push() {
  local BUILD_TAGS=""
  for TAG in ${TAGS}
  do
    BUILD_TAGS="${BUILD_TAGS}-t ${INPUT_NAME}:${TAG} "
  done
  docker build ${INPUT_BUILDOPTIONS} ${BUILDPARAMS} ${BUILD_TAGS} ${CONTEXT}

  for TAG in ${TAGS}
  do
    docker push "${INPUT_NAME}:${TAG}"
  done
}

main

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
  GIT_BRANCH=$(echo "${GITHUB_REF}" | sed -e "s/refs\/heads\///g" | sed -e "s/\//-/g")

  if [ "$GITHUB_REF_TYPE" == "tag" ]; then
    INPUT_TAG=${GITHUB_REF_NAME}
  else
    INPUT_TAG=${TRAVIS_TAG}
  fi

  echo "INPUT_NAME=${INPUT_NAME}"
  echo "GITHUB_SHA=${GITHUB_SHA}"
  echo "GITHUB_REF=${GITHUB_REF}"
  echo "INPUT_TAG=${INPUT_TAG}"
  echo "GIT_BRANCH=${GIT_BRANCH}"

  # Prevents building and pushing images when pull_request.
  # This is an additional control in case we allow in Travis access to secret env variables from
  # pull requests from forks (DOCKER_PASSWORD).
  # This could lead to generate "edge" tags if pushed from master branch, or overwritting a branch tag.
  # TODO: For Github Actions we should review what is the behavoiur.
  if [ "$TRAVIS_EVENT_TYPE" == "pull_request" ]; then
    >&2 echo "Disabled build and push on pull-requests"
    exit 1
  fi

  sanitize "${INPUT_NAME}" "name"
  sanitize "${INPUT_USERNAME}" "username"
  sanitize "${INPUT_PASSWORD}" "password"

  REGISTRY_NO_PROTOCOL=${INPUT_REGISTRY#"https://"}
  if [ -n "$INPUT_REGISTRY" ] && ! isPartOfTheName "${REGISTRY_NO_PROTOCOL}"; then
    INPUT_NAME="${REGISTRY_NO_PROTOCOL}/${INPUT_NAME}"
  fi

  translateDockerTag
  echo "TAGS=$TAGS"

  echo "${INPUT_PASSWORD}" | docker login -u "${INPUT_USERNAME}" --password-stdin "${INPUT_REGISTRY}"

  push

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
  if [ -n "$INPUT_TAG" ]; then

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

  elif [[ "${GIT_BRANCH}" =~ ^(master|main)$ ]]; then
    TAGS="edge ${GITHUB_SHA}"
  else
    TAGS="${GIT_BRANCH} ${GIT_BRANCH}-${SHORT_SHA} ${GITHUB_SHA}"
  fi
}

function push() {
  BUILDPARAMS=()
  BUILDPARAMS+=("--build-arg" "BUILD_RFC3339=$(date -u +"%Y-%m-%dT%H:%M:%SZ")") 
  BUILDPARAMS+=("--build-arg" "COMMIT=$GITHUB_SHA")
  BUILDPARAMS+=("--label" "org.opencontainers.image.title=$INPUT_NAME")
  BUILDPARAMS+=("--label" "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')")
  BUILDPARAMS+=("--cache-to" "type=inline")
  BUILDPARAMS+=("--cache-from" "type=registry,ref=$INPUT_NAME:edge")
  if [ -n "$INPUT_DOCKERFILE" ]; then
    BUILDPARAMS+=("-f" "${INPUT_DOCKERFILE}")
  fi
  if [ -n "$INPUT_BUILDARGS" ]; then
    for ARG in $(echo "${INPUT_BUILDARGS}" | tr ',' '\n'); do
      BUILDPARAMS+=("--build-arg" "${ARG}")
    done
  fi

  BUILDPARAMS+=("--platform" "${INPUT_PLATFORM:-"linux/amd64"}")
  for tag in ${TAGS}
  do
    BUILDPARAMS+=("--tag" "${INPUT_NAME}:${tag}")
  done
  for par in ${INPUT_BUILDOPTIONS}
  do
    BUILDPARAMS+=("$par")
  done
  BUILDPARAMS+=("${INPUT_CONTEXT:-.}")

  # See travis_wait
  ( for i in $(seq 30); do sleep 60 && echo "hearthbeat: ${i}m"; done ) &
  pid1=$!

  echo "BUILDPARAMS=${BUILDPARAMS[*]}"
  docker buildx build "${BUILDPARAMS[@]}" --push

  kill -9 "$pid1"
}

# Enable buildkit
DOCKER_BUILDKIT=${DOCKER_BUILDKIT:-1}

if ! docker buildx version ; then
  INPUT_BUILDX_VERSION=${INPUT_BUILDX_VERSION:-v0.11.2}
  echo "Buildx not available ... installing"
  mkdir -vp ~/.docker/cli-plugins/
  curl --silent -L "https://github.com/docker/buildx/releases/download/$INPUT_BUILDX_VERSION/buildx-$INPUT_BUILDX_VERSION.linux-amd64" > ~/.docker/cli-plugins/docker-buildx
  chmod a+x ~/.docker/cli-plugins/docker-buildx
  docker buildx version
fi

docker buildx create --use

main

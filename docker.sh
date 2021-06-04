#!/bin/bash

# Copyright 2020 Adevinta
set -e

function docker_init() {
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
  GITHUB_REF=${GITHUB_REF:-$TRAVIS_PULL_REQUEST_BRANCH}   # In case of pull request we want the originating branch, not the target.
  GITHUB_REF=${GITHUB_REF:-$TRAVIS_BRANCH}

  GITHUB_SHORT_SHA=$(echo "${GITHUB_SHA}" | cut -c1-7)

  echo "INPUT_NAME=${INPUT_NAME}"
  echo "GITHUB_SHA=${GITHUB_SHA}"
  echo "GITHUB_REF=${GITHUB_REF}"

  sanitize "${INPUT_NAME}" "name"
  sanitize "${INPUT_USERNAME}" "username"
  sanitize "${INPUT_PASSWORD}" "password"

  REGISTRY_NO_PROTOCOL=$(echo "${INPUT_REGISTRY}" | sed -e 's/^https:\/\///g')
  if [ -n "$INPUT_REGISTRY" ] && [[ ${INPUT_NAME} == *${REGISTRY_NO_PROTOCOL}* ]]; then
    INPUT_NAME="${REGISTRY_NO_PROTOCOL}/${INPUT_NAME}"
  fi

  echo "${INPUT_PASSWORD}" | docker login -u "${INPUT_USERNAME}" --password-stdin "${INPUT_REGISTRY}"

  if [ -n "$INPUT_TAGS" ]; then
    TAGS=${INPUT_TAGS//,/ }
  else 
    local BRANCH
    BRANCH=$(echo "${GITHUB_REF}" | sed -e "s|refs/heads|/|g" | sed -e "s|/|-|g")

    # Has a custom tag
    if [[ $INPUT_NAME =~ ':' ]]; then
      TAGS=$(echo "${INPUT_NAME}" | cut -d':' -f2)
      INPUT_NAME=$(echo "${INPUT_NAME}" | cut -d':' -f1)
    elif [ "${BRANCH}" = "master" ]; then
      TAGS="latest latest-${GITHUB_SHORT_SHA}"
    elif [[ "$GITHUB_REF" =~ 'refs/tags' ]] && [ "${INPUT_TAG_NAMES}" = "true" ]; then
      TAGS=${GITHUB_REF//refs\/tags/}
    elif [[ "$GITHUB_REF" =~ 'refs/tags' ]]; then
      TAGS="latest"
    elif [[ "$GITHUB_REF" =~ 'refs/pull' ]]; then
      TAGS="${GITHUB_SHA}"
    else
      TAGS="${BRANCH} ${BRANCH}-${GITHUB_SHORT_SHA}"
    fi;

    # Always tag with the full SHA
    if [[ ! $TAGS =~ $GITHUB_SHA ]]; then
      TAGS="${TAGS} ${GITHUB_SHA}"
    fi

  fi

  if [ "${INPUT_SNAPSHOT}" = "true" ]; then
    local TIMESTAMP
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    local SNAPSHOT_TAG="${TIMESTAMP}${GITHUB_SHORT_SHA}"
    TAGS="${TAGS} ${SNAPSHOT_TAG}"
    echo ::set-output name=snapshot-tag::"${SNAPSHOT_TAG}"
  fi

  echo "TAGS=$TAGS"
}

function sanitize() {
  if [ -z "${1}" ]; then
    >&2 echo "Unable to find the ${2}. Did you set with.${2}?"
    exit 1
  fi
}

function docker_build() {
  if [ -e "${INPUT_WORKDIR}" ]; then
    cd "${INPUT_WORKDIR}"
  fi

  FIRST_TAG=$(echo "$TAGS" | cut -d ' ' -f1)
  DOCKERNAME="${INPUT_NAME}:${FIRST_TAG}"
  BUILDPARAMS="--build-arg BUILD_RFC3339=$(date -u +"%Y-%m-%dT%H:%M:%SZ") --build-arg COMMIT=$GITHUB_SHA"
  CONTEXT="."

  if [ "${DOCKER_BUILDKIT}" = "1" ]; then
    BUILDPARAMS="${BUILDPARAMS} --progress=plain"
  fi

  if [ -n "${INPUT_BUILDOPTIONS}" ]; then
    BUILDPARAMS="${BUILDPARAMS} ${INPUT_BUILDOPTIONS}"
  fi

  if [ -n "${INPUT_DOCKERFILE}" ]; then
    BUILDPARAMS="${BUILDPARAMS} -f ${INPUT_DOCKERFILE}"
  fi
  if [ -n "${INPUT_BUILDARGS}" ]; then
    for ARG in $(echo "${INPUT_BUILDARGS}" | tr ',' '\n'); do
      BUILDPARAMS="${BUILDPARAMS} --build-arg ${ARG}"
      echo "::add-mask::${ARG}"
    done
  fi
  if [ -n "${INPUT_CONTEXT}" ]; then
    CONTEXT="${INPUT_CONTEXT}"
  fi
  if [ "${INPUT_CACHE}" = "true" ]; then
    if docker pull "${DOCKERNAME}" 2>/dev/null; then
      BUILDPARAMS="$BUILDPARAMS --cache-from ${DOCKERNAME}"
    fi
  fi

  local BUILD_TAGS=""
  for TAG in ${TAGS}
  do
    BUILD_TAGS="${BUILD_TAGS}-t ${INPUT_NAME}:${TAG} "
  done
  echo "docker build ${BUILDPARAMS} ${BUILD_TAGS} ${CONTEXT}"
  eval "docker build ${BUILDPARAMS} ${BUILD_TAGS} ${CONTEXT}"
}

function docker_push() {
  for TAG in ${TAGS}
  do
    eval "docker push ${INPUT_NAME}:${TAG}"
  done

  echo "::set-output name=tag::${FIRST_TAG}"
  DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' ${DOCKERNAME})
  echo "::set-output name=digest::${DIGEST}"
}

function docker_all() {
    docker_init

    docker_build

    docker_push

    docker logout
}

docker_init

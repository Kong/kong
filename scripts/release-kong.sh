#!/usr/bin/env bash

# This script is currently used by .github/workflows/release.yml to release Kong to Pulp.
set -eo pipefail

source .requirements

KONG_VERSION=$(bash scripts/grep-kong-version.sh)
KONG_RELEASE_LABEL=${KONG_RELEASE_LABEL:-$KONG_VERSION}

PULP_HOST=${PULP_HOST:-"https://api.download-dev.konghq.com"}
PULP_USERNAME=${PULP_USERNAME:-"admin"}
PULP_PASSWORD=${PULP_PASSWORD:-}

PULP_DOCKER_IMAGE="kong/release-script"

# Variables used by the release script
ARCHITECTURE=${ARCHITECTURE:-amd64}
PACKAGE_TYPE=${PACKAGE_TYPE:-deb}
ARTIFACT_TYPE=${ARTIFACT_TYPE:-debian}

ARTIFACT_PREFIX=${ARTIFACT_PREFIX:-"bazel-bin/pkg"}
ARTIFACT=${ARTIFACT:-"kong.deb"}
ARTIFACT_VERSION=${ARTIFACT_VERSION:-}

KONG_ARTIFACT=$ARTIFACT_PREFIX/$ARTIFACT

# Retries a command a configurable number of times with backoff.
#
# The retry count is given by ATTEMPTS (default 5), the initial backoff
# timeout is given by TIMEOUT in seconds (default 1.)
#
# Successive backoffs double the timeout.
function with_backoff {
  local max_attempts=${ATTEMPTS-5}
  local timeout=${TIMEOUT-5}
  local attempt=1
  local exitCode=0

  while (( $attempt < $max_attempts ))
  do
    if "$@"
    then
      return 0
    else
      exitCode=$?
    fi

    echo "Failure! Retrying in $timeout.." 1>&2
    sleep $timeout
    attempt=$(( attempt + 1 ))
    timeout=$(( timeout * 2 ))
  done

  if [[ $exitCode != 0 ]]
  then
    echo "You've failed me for the last time! ($*)" 1>&2
  fi

  return $exitCode
}

# TODO: remove this once we have a better way to determine if we are releasing
case "$ARTIFACT_TYPE" in
  debian|ubuntu)
    OUTPUT_FILE_SUFFIX=".$ARTIFACT_VERSION.$ARCHITECTURE.deb"
    ;;
  rhel)
    OUTPUT_FILE_SUFFIX=".rhel$ARTIFACT_VERSION.$ARCHITECTURE.rpm"
    ;;
  alpine)
    OUTPUT_FILE_SUFFIX=".$ARCHITECTURE.apk.tar.gz"
    ;;
  amazonlinux)
    OUTPUT_FILE_SUFFIX=".aws.$ARCHITECTURE.rpm"
    ;;
  src)
    OUTPUT_FILE_SUFFIX=".tar.gz"
    ;;
esac


DIST_FILE="$KONG_PACKAGE_NAME-$KONG_RELEASE_LABEL$OUTPUT_FILE_SUFFIX"

function push_package () {

  local dist_version="--dist-version $ARTIFACT_VERSION"

  # TODO: CE gateway-src

  if [ "$ARTIFACT_TYPE" == "alpine" ]; then
    dist_version=
  fi

  if [ "$ARTIFACT_VERSION" == "18.04" ]; then
    dist_version="--dist-version bionic"
  fi
  if [ "$ARTIFACT_VERSION" == "20.04" ]; then
    dist_version="--dist-version focal"
  fi
  if [ "$ARTIFACT_VERSION" == "22.04" ]; then
    dist_version="--dist-version jammy"
  fi

  # test for sanitized github actions input
  if [[ -n "$(echo "$PACKAGE_TAGS" | tr -d 'a-zA-Z0-9._,')" ]]; then
    echo 'invalid characters in PACKAGE_TAGS'
    echo "passed to script: ${PACKAGE_TAGS}"
    tags=''
  else
    tags="$PACKAGE_TAGS"
  fi

  set -x
  release_args=''

  if [ -n "${tags:-}" ]; then
    release_args="${release_args} --tags ${tags}"
  fi

  release_args="${release_args} --package-type gateway"
  if [[ "$EDITION" == "enterprise" ]]; then
    release_args="${release_args} --enterprise"
  fi

  # pre-releases go to `/internal/`
  if [[ "$OFFICIAL_RELEASE" == "true" ]]; then
    release_args="${release_args} --publish"
  else
    release_args="${release_args} --internal"
  fi

  docker run \
    -e PULP_HOST="$PULP_HOST" \
    -e PULP_USERNAME="$PULP_USERNAME" \
    -e PULP_PASSWORD="$PULP_PASSWORD" \
    -e VERBOSE \
    -e CLOUDSMITH_API_KEY \
    -e CLOUDSMITH_DRY_RUN \
    -e IGNORE_CLOUDSMITH_FAILURES \
    -e USE_CLOUDSMITH \
    -e USE_PULP \
    -v "$(pwd)/$KONG_ARTIFACT:/files/$DIST_FILE" \
    -i $PULP_DOCKER_IMAGE \
          --file "/files/$DIST_FILE" \
          --dist-name "$ARTIFACT_TYPE" $dist_version \
          --major-version "${KONG_VERSION%%.*}.x" \
          $release_args

  if [[ $? -ne 0 ]]; then
    exit 1
  fi
}

with_backoff push_package

echo -e "\nReleasing Kong '$KONG_RELEASE_LABEL' of '$ARTIFACT_TYPE $ARTIFACT_VERSION' done"

exit 0

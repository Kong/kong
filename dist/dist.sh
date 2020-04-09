#!/usr/bin/env bash

# This script acts as a proxy between kong-ee and kong-distributions
# Reads a kong-distributions version from the .requirements file
# and uses that version transparently.

set -e

LOCAL_PATH=$(dirname "$(realpath "$0")")

LOCAL_KONG_PATH=$LOCAL_PATH/..
KONG_DISTRIBUTIONS_VERSION=${KONG_DISTRIBUTIONS_VERSION:-$(grep KONG_DISTRIBUTIONS_VERSION $LOCAL_KONG_PATH/.requirements | sed -e 's/.*=//' | tr -d '\n')}
KONG_DISTRIBUTIONS_VERSION=${KONG_DISTRIBUTIONS_VERSION:-master}

function on_exit() {
  # Cleanup
  rm -rf $KONG_DIST_PATH
}

KONG_DIST_PATH=$(mktemp -d /tmp/kong-dist-XXXXX)
trap on_exit EXIT

git clone -b $KONG_DISTRIBUTIONS_VERSION https://"$GITHUB_TOKEN"@github.com/Kong/kong-distributions.git $KONG_DIST_PATH

# This is for package.sh
export OUTPUT_DIR=$LOCAL_PATH/output
export LOCAL_KONG_PATH=$LOCAL_KONG_PATH
# This is for release.sh
export BUILD_DIR=$OUTPUT_DIR

ACTION=$1
shift

if [[ $ACTION == "build" ]]; then
  $KONG_DIST_PATH/package.sh "$@"
elif [[ $ACTION == "release" ]]; then
  # We have 0 trust that the release script works if it does not run
  # within its folder. So:
  pushd $KONG_DIST_PATH
    ./release.sh "$@"
  popd
else
  echo $ACTION "$@"
fi


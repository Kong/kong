#!/usr/bin/env bash

# This script acts as a proxy between kong-ee and kong-distributions
# Reads a kong-distributions version from the .requirements file
# and uses that version transparently.

set -e

LOCAL_PATH=$(dirname "$(realpath "$0")")

# Provides exit traps
source $LOCAL_PATH/../scripts/common.sh

LOCAL_KONG_PATH=$LOCAL_PATH/..
KONG_DISTRIBUTIONS_VERSION=${KONG_DISTRIBUTIONS_VERSION:-$(grep KONG_DISTRIBUTIONS_VERSION $LOCAL_KONG_PATH/.requirements | sed -e 's/.*=//' | tr -d '\n')}
KONG_DISTRIBUTIONS_VERSION=${KONG_DISTRIBUTIONS_VERSION:-master}

KONG_DOCKER_KONG_VERSION=${KONG_DOCKER_KONG_VERSION:-$(grep KONG_DOCKER_KONG_VERSION $LOCAL_KONG_PATH/.requirements | sed -e 's/.*=//' | tr -d '\n')}
KONG_DOCKER_KONG_VERSION=${KONG_DOCKER_KONG_VERSION:-master}

git_clone_tmp() {
  local repo=${1:?repo is required}
  local ref=${2:?ref is required}
  tmpath=$(mktemp -d "/tmp/kong-$repo-XXXXX")
  on_exit "rm -rf $tmpath"

  git clone -b ${ref} https://"$GITHUB_TOKEN"@github.com/Kong/${repo}.git $tmpath
}

# This is for package.sh
export CACHE_DIR=${CACHE_DIR:-/tmp/kong-dist-cache}
export OUTPUT_DIR=$LOCAL_PATH/output
export LOCAL_KONG_PATH=$LOCAL_KONG_PATH
export KONG_DOCKER_VERSION=${KONG_DOCKER_KONG_VERSION}
# This is for release.sh
export BUILD_DIR=$OUTPUT_DIR

ACTION=$1
shift

case $ACTION in
  release)
    git_clone_tmp kong-distributions $KONG_DISTRIBUTIONS_VERSION
    # We have 0 trust that the release script works if it does not run
    # within its folder. So:
    pushd $tmpath
      ./release.sh "$@"
    popd
    ;;
  get)
    git_clone_tmp kong-distributions $KONG_DISTRIBUTIONS_VERSION
    clear_exit
    echo $tmpath
    ;;
  *)
    git_clone_tmp kong-distributions $KONG_DISTRIBUTIONS_VERSION
    $tmpath/package.sh $ACTION "$@"
    ;;
esac

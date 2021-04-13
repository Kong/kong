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

use_local() {
  local path=${!1}

  if [[ -n $path ]] &&
     [[ -d $path ]]; then
    # Assign local path
    tmpath=$path
    return 0
  fi

  return 1
}

# This is for package.sh
export CACHE_DIR=${CACHE_DIR:-/tmp/kong-dist-cache}
export OUTPUT_DIR=$LOCAL_PATH/output
export LOCAL_KONG_PATH=$LOCAL_KONG_PATH
export DOCKER_KONG_VERSION=${KONG_DOCKER_KONG_VERSION}
# This is for release.sh
export BUILD_DIR=$OUTPUT_DIR

ACTION=$1
shift

case $ACTION in
  release)
    use_local KONG_DISTRIBUTIONS_PATH || git_clone_tmp kong-distributions $KONG_DISTRIBUTIONS_VERSION
    # We have 0 trust that the release script works if it does not run
    # within its folder. So:
    pushd $tmpath
      ./release.sh "$@"
    popd
    ;;
  bintray-release)
    use_local DOCKER_KONG_PATH || git_clone_tmp docker-kong $KONG_DOCKER_KONG_VERSION
    pushd $tmpath
      ./bintray-release.sh "$@"

      # TODO: Remove below after Bintray sunset
      # Handle push to freemium Bintray repository
      IS_LATEST=0
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -u)
            USERNAME="$2"
            shift
            ;;
          -k)
            PASSWORD="$2"
            shift
            ;;
          -p)
            PLATFORM="$2"
            shift
            ;;
          -R)
            RELEASE_SCOPE="$(echo "$2" | awk '{print tolower($0)}')"
            shift
            ;;
          -l)
            IS_LATEST=1
            ;;
          -v)
            VERSION="$2"
            shift
            ;;
        esac
        shift
      done
      if [[ "$RELEASE_SCOPE" == "ga" ]]; then
        docker login -u $USERNAME -p $PASSWORD kong-docker-kong-gateway-docker.bintray.io

        docker tag kong-docker-kong-enterprise-edition-docker.bintray.io/kong-enterprise-edition:"$VERSION"-"$PLATFORM" \
                   kong-docker-kong-gateway-docker.bintray.io/kong-enterprise-edition:"$VERSION"-"$PLATFORM"
        docker push kong-docker-kong-gateway-docker.bintray.io/kong-enterprise-edition:"$VERSION"-"$PLATFORM"

        if [[ $IS_LATEST -eq 1 ]]; then
          docker tag kong-docker-kong-enterprise-edition-docker.bintray.io/kong-enterprise-edition:"$VERSION"-"$PLATFORM" \
                     kong-docker-kong-gateway-docker.bintray.io/kong-enterprise-edition:latest
          docker push kong-docker-kong-gateway-docker.bintray.io/kong-enterprise-edition:latest
        fi
      fi
      # TODO: Remove above after Bintray sunset
    popd
    ;;
  get)
    git_clone_tmp kong-distributions $KONG_DISTRIBUTIONS_VERSION
    clear_exit
    echo $tmpath
    ;;
  *)
    use_local KONG_DISTRIBUTIONS_PATH || git_clone_tmp kong-distributions $KONG_DISTRIBUTIONS_VERSION
    $tmpath/package.sh $ACTION "$@"
    ;;
esac

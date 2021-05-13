#!/usr/bin/env bash

# This script acts as a proxy between kong-ee and kong-distributions
# Reads a kong-distributions version from the .requirements file
# and uses that version transparently.

set -e

LOCAL_PATH=$(dirname "$(realpath "$0")")

# Provides exit traps
# shellcheck disable=SC1091
source "$LOCAL_PATH/../scripts/common.sh"

LOCAL_KONG_PATH=$LOCAL_PATH/..
KONG_DISTRIBUTIONS_VERSION=${KONG_DISTRIBUTIONS_VERSION:-$(grep KONG_DISTRIBUTIONS_VERSION "$LOCAL_KONG_PATH/.requirements" | sed -e 's/.*=//' | tr -d '\n')}
KONG_DISTRIBUTIONS_VERSION=${KONG_DISTRIBUTIONS_VERSION:-master}
KONG_DOCKER_KONG_VERSION=${KONG_DOCKER_KONG_VERSION:-$(grep KONG_DOCKER_KONG_VERSION "$LOCAL_KONG_PATH/.requirements" | sed -e 's/.*=//' | tr -d '\n')}
FOUNDATION_VERSION=${FOUNDATION_VERSION:-$(grep FOUNDATION_VERSION "$LOCAL_KONG_PATH/.requirements" | sed -e 's/.*=//' | tr -d '\n')}
FOUNDATION_VERSION=${FOUNDATION_VERSION:-master}

git_clone_tmp() {
  local repo=${1:?repo is required}
  local ref=${2:?ref is required}
  tmpath=$(mktemp -d "/tmp/kong-$repo-XXXXX")
  on_exit "rm -rf $tmpath"

  git clone -b "$ref" "https://$GITHUB_TOKEN@github.com/Kong/$repo.git" "$tmpath"
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

function usage {
cat << EOF
Usage: $0 action [options...]
Options:
  -V, --verbose    echo every command that gets executed
  -h, --help       display this help

Commands:
  release             publish artifacts to Pulp
  docker-hub-release  push and tag containers on Docker Hub
  get                 clone kong-distributions version in .requirements
  *                   execute kong-distributions package script with action

EOF
}

function main {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  # This is for package.sh
  export CACHE_DIR=${CACHE_DIR:-/tmp/kong-dist-cache}
  export OUTPUT_DIR=$LOCAL_PATH/output
  export LOCAL_KONG_PATH=$LOCAL_KONG_PATH
  export DOCKER_KONG_VERSION=${KONG_DOCKER_KONG_VERSION}
  # This is for release.sh
  export BUILD_DIR=$OUTPUT_DIR

  # Do not parse a starting --help|-h as an action
  local action
  ! [[ $1 =~ ^- ]] && action=$1 && shift

  local unparsed_args=()
  while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
      -V|--verbose)
        set -x
        unparsed_args+=("$1") # Pass verbose option along to other scripts
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        unparsed_args+=("$1")
        ;;
    esac
    shift
  done

  case $action in
    release)
      use_local KONG_DISTRIBUTIONS_PATH || git_clone_tmp kong-distributions "$KONG_DISTRIBUTIONS_VERSION"
      # We have 0 trust that the release script works if it does not run
      # within its folder. So:
      (
        cd "$tmpath"
        ./release.sh "${unparsed_args[@]}"
      )
      ;;
    docker-hub-release)
      use_local FOUNDATION_PATH || git_clone_tmp foundation "$FOUNDATION_VERSION"

      # Only assign kong-docker version is set
      # Note: the foundation scripting logic handles this as kong-docker value
      #       has never been set
      local docker_kong_flag
      if [[ -n "$KONG_DOCKER_KONG_VERSION" ]]; then
        docker_kong_flag="-d $KONG_DOCKER_KONG_VERSION"
      fi
      (
        cd "$tmpath"
        # shellcheck disable=SC2086
        fast-track/fast-track docker-image "${unparsed_args[@]}" $docker_kong_flag
      )
      ;;
    get)
      git_clone_tmp kong-distributions "$KONG_DISTRIBUTIONS_VERSION"
      clear_exit
      cd "$tmpath"
      ;;
    *)
      use_local KONG_DISTRIBUTIONS_PATH || git_clone_tmp kong-distributions "$KONG_DISTRIBUTIONS_VERSION"
      "$tmpath/package.sh" "$action" "${unparsed_args[@]}"
      ;;
  esac
}

main "$@"

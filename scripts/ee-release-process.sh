#!/usr/bin/env bash
#
# example run:
# ee-release-process.sh 2.2.0.1

set -eEuo pipefail
shopt -s inherit_errexit

LOCAL_PATH=$(dirname $(realpath $0))
source $LOCAL_PATH/common.sh

# Get the default using the GitHub API
get_default_branch() {
  local org=$1
  local repo=$2  # Make sure the GitHub username and token are available

  [[ -z $GITHUB_USERNAME ]] &&  die "GITHUB_USERNAME is not set."
  [[ -z $GITHUB_TOKEN ]] && die "GITHUB_TOKEN/GITHUB_USERNAME is not set."

  local branch=$(http -a "$GITHUB_USERNAME:$GITHUB_TOKEN" GET https://api.github.com/repos/$org/$repo \
              | jq -r ".default_branch")

  if [[ "$branch" == "null" ]]; then
    return 1
  fi

  echo $branch
}

# update_default_branch() {
#   local org=$1
#   local repo=$2  # Make sure the GitHub username and token are available
#   local new_def_branch=$3

#   [[ -z $GITHUB_USERNAME ]] &&  die "GITHUB_USERNAME is not set."
#   [[ -z $GITHUB_TOKEN ]] && die "GITHUB_TOKEN/GITHUB_USERNAME is not set."

#   http -a "$GITHUB_USERNAME:$GITHUB_TOKEN" PATCH "https://api.github.com/repos/$org/$repo" "default_branch=$new_def_branch"
# }


runs_in_def_branch() {
  local def_br=$(get_default_branch kong kong-ee)
  [[ "$(git branch --show-current)" == "$def_br" ]]
}


dep_version () {
  grep "^\s*${1}=" .requirements |
    head -1 |
    sed -e 's/.*=//' |
    tr -d '\n'
}


is_linked_to_kong_distributions_def_branch() {
  local def_br=$(get_default_branch kong kong-distributions)

  [[ "$(dep_version KONG_DISTRIBUTIONS_VERSION)" == "$def_br" ]] ||
    die "Not in the kong-distributions default branch: ${def_br}."
}


update_meta() {
  meta=kong/enterprise_edition/meta.lua
  sed -i "s/ x = [0-9]*/ x = ${1}/" $meta
  sed -i "s/ y = [0-9]*/ y = ${2}/" $meta
  sed -i "s/ z = [0-9]*/ z = ${3}/" $meta
  sed -i "s/ e = [0-9]*/ e = ${4}/" $meta
}


update_jenkinsfile() {
  sed -i "s/^\\s*KONG_VERSION\\s*=.*/    KONG_VERSION = \"${1}\"/" Jenkinsfile
}


parse_args() {
  [[ $# -eq 0 ]] && die "Usage: $0 <version>"
  version="$1"
  local version_split=$(echo $version | tr '.' '\n')
  IFS='.' readarray -t version_array <<< "$version_split"

  if [[ -z ${version_array[3]} ]]; then
    die "not enough version numbers"
  fi
}

next_branch_for_version() {
  echo "next/${version_array[0]}.${version_array[1]}.x.x"
}


update_kd_in_requirements() {
  sed -i "s@KONG_DISTRIBUTIONS_VERSION=.*@KONG_DISTRIBUTIONS_VERSION=${1}@" .requirements
}

# magic fero!
function download_github_repo_file() {
  local org=$1
  local repo=$2
  local branch=$3
  local file=$4
  local downloaded_filename=$(mktemp /tmp/githubapi_downloaded_file.XXXXXXXXX)

  # Make sure the GitHub username and token are available
  [[ -z $GITHUB_USERNAME ]] && ( >&2 echo "GITHUB_USERNAME is not set" ; return 1 )
  [[ -z $GITHUB_TOKEN ]] && ( >&2 echo "GITHUB_TOKEN is not set" ; return 1 )

  # Get the file using the GitHub API
  http -a $GITHUB_USERNAME:$GITHUB_TOKEN \
       https://api.github.com/repos/$org/$repo/contents/$file \
       ref=="$branch" \
       | jq -r ".content" | base64 --decode > $downloaded_filename

  echo $downloaded_filename
}


# check from pongo master, that all 4-number tags in kong-ee have a
# corresponding line in pongo:/assets/kong_EE_versions.ver
ensure_pongo_versions() {
  echo "- checking pongo: "
  local f=$(download_github_repo_file kong kong-pongo master "assets/kong_EE_versions.ver")
  ! grep -Fvf <(grep -P "^\d\.\d\.\d\.\d$" "$f") <(git tag | grep -P "^\d\.\d\.\d\.\d$")
}

main() {
  parse_args "$@"

  # validate_args

  ensure_pongo_versions

  update_meta "${version_array[@]}"
  update_jenkinsfile "$version"

  update_kd_in_requirements "$(next_branch_for_version)"


  $LOCAL_PATH/copyright-checker

  if runs_in_def_branch; then
    echo "run version checker and bump-plugin"
    # is_linked_to_kong_distributions_def_branch
    # $LOCAL_PATH/version-checker
    # $LOCAL_PATH/bump-plugin
  fi



  # do_things
  # cleanup
}

main "$@"

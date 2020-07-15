#!/usr/bin/env bash

ON_EXIT=("${ON_EXIT[@]}")
EXIT_RES=

function on_exit_fn {
  EXIT_RES=$?
  for cb in "${ON_EXIT[@]}"; do $cb || true; done
  # read might hang on ctrl-c, this is a hack to finish the script for real
  clear_exit
  exit $EXIT_RES
}

trap on_exit_fn EXIT SIGINT

function on_exit {
  ON_EXIT+=("$@")
}


function clear_exit {
  trap - EXIT SIGINT
}


function colorize() {
  local color="39" # default
  case $1 in
    black)
      color="30"
      ;;
    red|err|error)
      color="31"
      ;;
    green|ok)
      color="32"
      ;;
    yellow|warn)
      color="33"
      ;;
    blue)
      color="34"
      ;;
    magenta)
      color="35"
      ;;
    cyan)
      color="36"
      ;;
    light-gray|light-grey)
      color="37"
      ;;
    dark-gray|drak-grey)
      color="90"
      ;;
    light-red)
      color="91"
      ;;
    light-green)
      color="92"
      ;;
    light-yellow)
      color="93"
      ;;
    light-blue)
      color="94"
      ;;
    light-magenta)
      color="95"
      ;;
    light-cyan)
      color="96"
      ;;
    white)
      color="97"
      ;;
  esac
  shift
  local str=$*

  echo -en "\033[1;${color}m"
  echo -en "$*"
  echo -en "\033[0m"
}


function err {
  >&2 echo -e "$*"
  exit 1
}

function warn {
  >&2 echo $(colorize yellow WARNING: $*)
}


function confirm {
  local ans=${2:-"y|Y"}
  [[ $FORCE == 1 ]] && return 0
  read -r -p "$1 ($ans)? "
  [[ $REPLY =~ $ans ]]
}


parse_version() {
  [[ -z $1 ]] || [[ -z $2 ]] && >&2 echo "parse_version() requires two arguments" && exit 1

  local ver
  local subj=$1

  if [[ $subj =~ ^[^0-9]*(.*) ]]; then
    subj=${BASH_REMATCH[1]}

    local re='^(-rc[0-9]+$)?[.]?([0-9]+|[a-zA-Z]+)?(.*)$'

    while [[ $subj =~ $re ]]; do
      if [[ ${BASH_REMATCH[1]} != "" ]]; then
        ver="$ver.${BASH_REMATCH[1]}"
      fi

      if [[ ${BASH_REMATCH[2]} != "" ]]; then
        ver="$ver.${BASH_REMATCH[2]}"
      fi

      subj="${BASH_REMATCH[3]}"
      if [[ $subj == "" ]]; then
        break
      fi
    done

    ver="${ver:1}"

    IFS='.' read -r -a $2 <<< "$ver"
  fi
}

version_eq() {
  local version_a version_b

  parse_version $1 version_a
  parse_version $2 version_b

  # Note that we are indexing on the b components, ie: 1.11.100 == 1.11
  for index in "${!version_b[@]}"; do
    [[ "${version_a[index]}" != "${version_b[index]}" ]] && return 1
  done

  return 0
}

version_lt() {
  local version_a version_b

  parse_version $1 version_a
  parse_version $2 version_b

  for index in "${!version_a[@]}"; do
    if [[ ${version_a[index]} =~ ^[0-9]+$ ]]; then
      [[ "${version_a[index]}" -lt "${version_b[index]}" ]] && return 0
      [[ "${version_a[index]}" -gt "${version_b[index]}" ]] && return 1

    else
      [[ "${version_a[index]}" < "${version_b[index]}" ]] && return 0
      [[ "${version_a[index]}" > "${version_b[index]}" ]] && return 1
    fi
  done

  return 1
}

version_gt() {
  (version_eq $1 $2 || version_lt $1 $2) && return 1
  return 0
}

version_lte() {
  (version_lt $1 $2 || version_eq $1 $2) && return 0
  return 1
}

version_gte() {
  (version_gt $1 $2 || version_eq $1 $2) && return 0
  return 1
}


parse_integer() {
  [[ -z $1 ]] || [[ -z $2 ]] && >&2 echo "parse_integer() requires two arguments" && exit 1

  local value=$1
  local argv=$2

  if ! [[ "$argv" =~ ^\-?[0-9]+$ ]]; then
    err "$argv is not a integer"
    exit 1
  fi
  value=$argv
}


check_requirements() {
  local verbose=0
  if [ ! -z $1 ] && [ $1 -eq 1 ]; then
    verbose=1
  fi
  local short_circuit=1
  if [ ! -z $2 ] && [ $2 -eq 0 ]; then
    short_circuit=0
  fi

  # Check for required commands
  local missing_requirement=0
  for command in ${REQUIRED_COMMANDS[@]}; do
    if hash $command >/dev/null 2>&1; then
      if [ $verbose -eq 1 ]; then
        printf "%-10s %s\n" "$command" "$(colorize ok '[OK]')"
      fi
    else
      >&2 printf "%-10s %s\n" "$command" "$(colorize err '[REQUIRED]')"
      missing_requirement=1
    fi
  done

  # Check for optional commands
  for command in ${OPTIONAL_COMMANDS[@]}; do
    if [ $verbose -eq 1 ]; then
      if hash $command >/dev/null 2>&1; then
        printf "%-10s %s\n" "$command" "$(colorize ok '[OK]')"
      else
        >&2 printf "%-10s %s\n" "$command" "$(colorize warn '[OPTIONAL]')"
      fi
    fi
  done

  if [ $missing_requirement -eq 1 ] && [ $short_circuit -eq 1 ]; then
    exit 1
  fi
}

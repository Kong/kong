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
#!/bin/bash

#-------------------------------------------------------------------------------
function commit_changelog() {
    if ! git status CHANGELOG.md | grep -q "modified:"
        then
            die "No changes in CHANGELOG.md to commit. Did you write the changelog?"
        fi

        git diff CHANGELOG.md

        CONFIRM "If everything looks all right, press Enter to commit" \
                  "or Ctrl-C to cancel."

        set -e
        git add CHANGELOG.md
        git commit -m "docs(changelog) add $1 changes"
        git log -n 1
}

#-------------------------------------------------------------------------------
function bump_homebrew() {
   curl -L -o "kong-$version.tar.gz" "https://bintray.com/kong/kong-src/download_file?file_path=kong-$version.tar.gz"
   sum=$(sha256sum "kong-$version.tar.gz" | awk '{print $1}')
   sed -i 's/kong-[0-9.]*.tar.gz/kong-'$version'.tar.gz/' Formula/kong.rb
   sed -i 's/sha256 ".*"/sha256 "'$sum'"/' Formula/kong.rb
}

#-------------------------------------------------------------------------------
function bump_vagrant() {
   sed -i 's/version = "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"/version = "'$version'"/' Vagrantfile
   sed -i 's/`[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*`/`'$version'`/' README.md
}

#-------------------------------------------------------------------------------
function ensure_recent_luarocks() {
   if ! ( luarocks upload --help | grep -q temp-key )
   then
      if [ `uname -s` = "Linux" ]
      then
         set -e
         source .requirements
         lv=3.2.1
         pushd /tmp
         rm -rf luarocks-$lv
         mkdir -p luarocks-$lv
         cd luarocks-$lv
         curl -L -o "luarocks-$lv-linux-x86_64.zip" https://luarocks.github.io/luarocks/releases/luarocks-$lv-linux-x86_64.zip
         unzip luarocks-$lv-linux-x86_64.zip
         export PATH=/tmp/luarocks-$lv/luarocks-$lv-linux-x86_64:$PATH
         popd
      else
         die "Your LuaRocks version is too old. Please upgrade LuaRocks."
      fi
   fi
}

#-------------------------------------------------------------------------------
function make_github_release_file() {
   versionlink=$(echo $version | tr -d .)
   cat <<EOF > release-$version.txt
$version

**Download Kong $version and run it now:**

- https://konghq.com/install/
- [Docker Image](https://hub.docker.com/_/kong/)

Links:
- [$version Changelog](https://github.com/Kong/kong/blob/master/CHANGELOG.md#$versionlink)
EOF
}

#-------------------------------------------------------------------------------
function bump_docs_kong_versions() {
   $LUA -e '
      local fd_in = io.open("app/_data/kong_versions.yml", "r")
      local fd_out = io.open("app/_data/kong_versions.yml.new", "w")
      local version = "'$version'"

      local state = "start"
      local version_line
      for line in fd_in:lines() do
         if state == "start" then
            if line:match("^  release: \"'$major'.'$minor'.x\"") then
               state = "version"
            end
            fd_out:write(line .. "\n")
         elseif state == "version" then
            if line:match("^  version: \"") then
               version_line = line
               state = "edition"
            end
         elseif state == "edition" then
            if line:match("^  edition.*community.*") then
               fd_out:write("  version: \"'$version'\"\n")
               state = "wait_for_luarocks_version"
            else
               fd_out:write(version_line .. "\n")
               state = "start"
            end
            fd_out:write(line .. "\n")
         elseif state == "wait_for_luarocks_version" then
            if line:match("^  luarocks_version: \"") then
               fd_out:write("  luarocks_version: \"'$version'-0\"\n")
               state = "last"
            else
               fd_out:write(line .. "\n")
            end
         elseif state == "last" then
            fd_out:write(line .. "\n")
         end
      end
      fd_in:close()
      fd_out:close()
   '
   mv app/_data/kong_versions.yml.new app/_data/kong_versions.yml
}

#-------------------------------------------------------------------------------
function prepare_changelog() {
   $LUA -e '
      local fd_in = io.open("CHANGELOG.md", "r")
      local fd_out = io.open("CHANGELOG.md.new", "w")
      local version = "'$version'"

      local state = "start"
      for line in fd_in:lines() do
         if state == "start" then
            if line:match("^%- %[") then
               fd_out:write("- [" .. version .. "](#" .. version:gsub("%.", "") .. ")\n")
               state = "toc"
            end
         elseif state == "toc" then
            if not line:match("^%- %[") then
               state = "start_log"
            end
         elseif state == "start_log" then
            fd_out:write("\n")
            fd_out:write("## [" .. version .. "]\n")
            fd_out:write("\n")
            local today = os.date("*t")
            fd_out:write(("> Released %04d/%02d/%02d\n"):format(today.year, today.month, today.day))
            fd_out:write("\n")
            fd_out:write("<<< TODO Introduction, plus any sections below >>>\n")
            fd_out:write("\n")
            fd_out:write("### Fixes\n")
            fd_out:write("\n")
            fd_out:write("##### Core\n")
            fd_out:write("\n")
            fd_out:write("##### CLI\n")
            fd_out:write("\n")
            fd_out:write("##### Configuration\n")
            fd_out:write("\n")
            fd_out:write("##### Admin API\n")
            fd_out:write("\n")
            fd_out:write("##### PDK\n")
            fd_out:write("\n")
            fd_out:write("##### Plugins\n")
            fd_out:write("\n")
            fd_out:write("\n")
            fd_out:write("[Back to TOC](#table-of-contents)\n")
            fd_out:write("\n")
            state = "log"
         elseif state == "log" then
            local prev_version = line:match("^%[(%d+%.%d+%.%d+)%]: ")
            if prev_version then
               fd_out:write("[" .. version .. "]: https://github.com/Kong/kong/compare/" .. prev_version .."..." .. version .. "\n")
               state = "last"
            end
         end

         fd_out:write(line .. "\n")
      end
      fd_in:close()
      fd_out:close()
   '
   mv CHANGELOG.md.new CHANGELOG.md
}

#-------------------------------------------------------------------------------
function step() {
   box="   "
   color="$nocolor"
   if [ "$version" != "<x.y.z>" ]
   then
      if [ -e "/tmp/.step-$1-$version" ]
      then
         color="$green"
         box="[x]"
      else
         color="$bold"
         box="[ ]"
      fi
   fi
   echo -e "$color $box Step $c) $2"
   echo "        $0 $version $1 $3"
   echo -e "$nocolor"
   c="$[c+1]"
}

#-------------------------------------------------------------------------------
function update_docker {
    if [ -d ../docker-kong ]
    then
        cd ../docker-kong
    else
        cd ..
        git clone https://github.com/kong/docker-kong
        cd docker-kong
    fi

    git pull
    git checkout -B "release/$1"

    set -e
    ./update.sh "$1"
}

#-------------------------------------------------------------------------------
function die() {
   echo
   echo -e "$red$bold*** $@$nocolor"
   echo "See also: $0 --help"
   echo
   exit 1
}

#-------------------------------------------------------------------------------
function SUCCESS() {
   echo
   echo -e "$green$bold****************************************$nocolor$bold"
   for line in "$@"
   do
      echo "$line"
   done
   echo -e "$green$bold****************************************$nocolor"
   echo
   touch /tmp/.step-$step-$version
   exit 0
}

#-------------------------------------------------------------------------------
function CONFIRM() {
   echo
   echo -e "$cyan$bold----------------------------------------$nocolor$bold"
   for line in "$@"
   do
      echo "$line"
   done
   echo -e "$cyan$bold----------------------------------------$nocolor"
   read
}

#-------------------------------------------------------------------------------
# Dependency checks
#-------------------------------------------------------------------------------

function dep_check() {

hub --version &> /dev/null || die "hub is not in PATH. Get it from https://github.com/github/hub"

if resty -v &> /dev/null
then
   LUA=resty
elif lua -v &> /dev/null
then
   LUA=lua
else
   die "Lua interpreter is not in PATH. Install any Lua or OpenResty to run this script."
fi

}

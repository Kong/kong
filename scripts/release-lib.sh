#!/bin/bash

red="\033[0;31m"
green="\033[0;32m"
cyan="\033[0;36m"
bold="\033[1m"
nocolor="\033[0m"

GITHUB_ORG=${GITHUB_ORG:-Kong}

scripts_folder=$(dirname "$0")

browser="echo"
if command -v firefox > /dev/null 2>&1
then
  browser=firefox
elif which xdg-open > /dev/null 2>&1
then
  browser=xdg-open
elif which open > /dev/null 2>&1
then
  browser=open
fi

EDITOR="${EDITOR-$VISUAL}"

#-------------------------------------------------------------------------------
function need() {
  req="$1"

  if ! type -t "$req" &>/dev/null; then
     echo "Required command $req not found."
     exit 1
  fi
}

#-------------------------------------------------------------------------------
function check_requirements() {
   need git
   need hub
   need sed
}


#-------------------------------------------------------------------------------
function yesno() {
  echo "$1"
  read -r
  if [[ "$REPLY" =~ ^[yY] ]]; then
    return 0
  fi
  return 1
}

#-------------------------------------------------------------------------------
function check_milestone() {
  if yesno "Visit the milestones page (https://github.com/$GITHUB_ORG/kong/milestone) and ensure PRs are merged. Press 'y' to open it or Ctrl-C to quit"; then
    $browser https://github.com/$GITHUB_ORG/kong/milestones
  fi

  CONFIRM "If everything looks all right, press Enter to continue"
  SUCCESS "All PRs are merged. Proceeding!"
}

#-------------------------------------------------------------------------------
function check_dependencies() {
  if yesno "Ensure Kong dependencies in the rockspec are bumped to their latest patch version. Press 'y' to open Kong's rockspec or Ctrl+C to quit"; then
    $EDITOR ./*.rockspec
  fi

  CONFIRM "If everything looks all right, press Enter to continue"
  SUCCESS "All dependencies are bumped. Proceeding!"
}

#-------------------------------------------------------------------------------
function write_changelog() {
  version=$1
  if ! grep -q "\[$version\]" CHANGELOG.md
  then
     prepare_changelog
  fi

  CONFIRM "Press Enter to open your text editor ($EDITOR) to edit CHANGELOG.md" \
          "or Ctrl-C to cancel."

  $EDITOR CHANGELOG.md

  SUCCESS "If you need to further edit the changelog," \
          "you can run this step again."
          "If it is ready, you can proceed to the next step" \
          "which will commit it:" \
          "    $0 $version commit_changelog"
}

#-------------------------------------------------------------------------------
function commit_changelog() {
  version=$1

  if ! git status CHANGELOG.md | grep -q "modified:"
  then
      die "No changes in CHANGELOG.md to commit. Did you write the changelog?"
  fi

  git diff CHANGELOG.md

  CONFIRM "If everything looks all right, press Enter to commit" \
            "or Ctrl-C to cancel."

  set -e
  git add CHANGELOG.md
  git commit -m "docs(changelog): add $version changes"
  git log -n 1

  SUCCESS "The changelog is now committed locally." \
          "You are ready to run the next step:" \
          "    $0 $version update_copyright"
}

#-------------------------------------------------------------------------------
function update_copyright() {
  version=$1

  PDIR=$(dirname "$scripts_folder")

  if ! (docker build -t kong/update-copyright ${scripts_folder} && docker run -v ${PDIR}:/workspace --rm kong/update-copyright)
  then
    die "Could not update copyright file. Check logs for missing licenses, add hardcoded ones if needed"
  fi

  git add COPYRIGHT

  git commit -m "docs(COPYRIGHT): update copyright for $version"
  git log -n 1

  SUCCESS "The COPYRIGHT file is updated locally." \
          "You are ready to run the next step:" \
          "    $0 $version update_admin_api_def"
}

#-------------------------------------------------------------------------------
function update_admin_api_def() {
  version=$1

  if ! "$scripts_folder/gen-admin-api-def.sh"
  then
    die "Could not update kong-admin-api.yml file. Check script output for any error messages."
  fi

  git add kong-admin-api.yml

  git commit -m "docs(kong-admin-api.yml): update Admin API definition for $1"
  git log -n 1

  SUCCESS "The kong-admin-api.yml file is updated locally." \
         "You are ready to run the next step:" \
         "    $0 $version version_bump"
}


#-------------------------------------------------------------------------------
function bump_homebrew() {
   curl -L -o "kong-$version.tar.gz" "https://download.konghq.com/gateway-src/kong-$version.tar.gz"
   sum=$(sha256sum "kong-$version.tar.gz" | awk '{print $1}')
   sed -i.bak 's/KONG_VERSION = "[0-9.]*"/KONG_VERSION = "'$version'"/' Formula/kong.rb
   sed -i.bak 's/sha256 ".*"/sha256 "'$sum'"/' Formula/kong.rb
}

#-------------------------------------------------------------------------------
function bump_vagrant() {
   sed -i.bak 's/version = "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"/version = "'$version'"/' Vagrantfile
   sed -i.bak 's/`[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*`/`'$version'`/' README.md
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
- [$version Changelog](https://github.com/$GITHUB_ORG/kong/blob/$version/CHANGELOG.md#$versionlink)
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
            if line:match("^  edition.*gateway%-oss.*") then
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
function announce() {
    local version="$1.$2.$3"

    if [ "$3" != "0" ]
    then
        patch_release_disclaimer="As a patch release, it only contains bug fixes; no new features and no breaking changes."
    fi

  cat <<EOF
============= USE BELOW ON KONG NATION ANNOUNCEMENT ==============
TITLE: Kong $version available!
BODY:
We’re happy to announce **Kong $version**.  $patch_release_disclaimer
:package: Download [Kong $version](https://download.konghq.com) and [upgrade your cluster](https://github.com/$GITHUB_ORG/kong/blob/master/UPGRADE.md#upgrade-to-$1$2x)!
:spiral_notepad: More info and PR links are available at the [$version Changelog](https://github.com/$GITHUB_ORG/kong/blob/master/CHANGELOG.md#$1$2$3).
:whale: The updated official Docker image is available on [Docker Hub ](https://hub.docker.com/_/kong).
As always, Happy Konging! :gorilla:
============= USE BELOW ON KONG NATION ANNOUNCEMENT ==============
We’re happy to announce *Kong $version*.  $patch_release_disclaimer
:package: Download Kong $version: https://download.konghq.com
:spiral_note_pad: More info and PR links are available at the $version Changelog: https://github.com/$GITHUB_ORG/kong/blob/master/CHANGELOG.md#$1$2$3
:whale: the updated official docker image is available on Docker Hub: https://hub.docker.com/_/kong
As always, happy Konging! :gorilla:
==================================================================
EOF

SUCCESS "Copy and paste this announcement in Kong Nation and Slack #general"
}

#-------------------------------------------------------------------------------
current_step=1
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
   echo -e "$color $box Step $current_step) $2"
   echo "        $0 $version $1 $3"
   echo -e "$nocolor"
   current_step="$[current_step+1]"
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
function merge_homebrew() {
  CONFIRM "The deploy robot should have sent a pull request to https://github.com/kong/homebrew-kong/pulls . " \
          "Make sure it gets approved and merged. Press Enter when done"
  SUCCESS "Homebrew PR merged. Proceeding!"
}

#-------------------------------------------------------------------------------
function merge_pongo() {
  CONFIRM "The deploy robot should have sent a pull request to https://github.com/kong/kong-pongo/pulls . " \
          "Make sure it gets approved and merged."
  SUCCESS "Pongo PR merged. Proceeding!"
}

#-------------------------------------------------------------------------------
function merge_vagrant() {
  CONFIRM "The release robot should have sent a PR to the kong-vagrant repo: https://github.com/$GITHUB_ORG/kong-vagrant . " \
          "Make sure it gets approved and merged. Press Enter when done"
  SUCCESS "Vagrant PR merged. Proceeding!"
}

#-------------------------------------------------------------------------------
function docs_pr() {
  branch=$1

  if [ -d ../docs.konghq.com ]
  then
     cd ../docs.konghq.com
  else
     cd ..
     git clone git@github.com:$GITHUB_ORG/docs.konghq.com.git
     cd docs.konghq.com
  fi
  git checkout main
  git pull
  git checkout -B "$branch"
  bump_docs_kong_versions

  git diff

  CONFIRM "If everything looks all right, press Enter to commit and send a PR to git@github.com:$GITHUB_ORG/docs.konghq.com.git" \
          "or Ctrl-C to cancel."

  set -e
  git add app/_data/kong_versions.yml
  git commit --allow-empty -m "chore(*): update release metadata for $version"

  git push --set-upstream origin "$branch"
  hub pull-request -b main -h "$branch" -m "Release: $version" -l "pr/please review,pr/do not merge"

  SUCCESS "Make sure you give Team Docs a heads-up" \
          "once the release is pushed to the main repo." \
          "When the main release PR is approved, you can proceed to:" \
          "    $0 $version merge"
}

#-------------------------------------------------------------------------------
function submit_release_pr() {
  base=$1
  branch=$2
  version=$3
  prerelease=$4

  if ! git log -n 1 | grep -q "release: $version"
  then
    die "Release commit is not at the top of the current branch. Did you commit the version bump?"
  fi

  git log

  CONFIRM "Press Enter to push the branch and open the release PR" \
    "or Ctrl-C to cancel."

  set -e
  git push --set-upstream origin "$branch"
  hub pull-request -b "$base" -h "$branch" -m "Release: $version" -l "pr/please review,pr/do not merge"

  if [ "$prerelease" != "" ]
  then
      docs_pr_note="In the mean time, you can run the 'docs_pr' step:    $0 $version docs_pr"
  fi

  SUCCESS "Now get the above PR reviewed and approved." \
    "Once it is approved, you can continue to the 'merge' step." \
    "$docs_pr_note"
}

#-------------------------------------------------------------------------------
function approve_docker() {
  CONFIRM "The internal build system should have created a pull request in the docker-kong repo: " \
          "https://github.com/$GITHUB_ORG/docker-kong/pulls . Make sure it gets approved before continuing " \
          "to the step 'merge_docker'. Press Enter when done."
  SUCCESS "Docker PR approved. Proceeding!"
}

#-------------------------------------------------------------------------------
function merge_docker() {
  branch=$1
  version=$2

  if [ -d ../docker-kong ]
  then
     cd ../docker-kong
  else
     cd ..
     git clone git@github.com:$GITHUB_ORG/docker-kong.git
     cd docker-kong
  fi

  set -e
  git checkout "$branch"
  git pull
  git checkout master
  git pull
  git merge "$branch"
  git push
  git tag -s "$version" -m "$version"
  git push origin "$version"

  make_github_release_file

  hub release create -F "release-$version.txt" "$version"
  rm -f release-$version.txt

  SUCCESS "Now you can run the next step:" \
          "    $0 $version submit_docker"
}

#-------------------------------------------------------------------------------
function submit_docker() {
  version=$1

  if [ -d ../docker-kong ]
  then
     cd ../docker-kong
  else
     cd ..
     git clone git@github.com:$GITHUB_ORG/docker-kong.git
     cd docker-kong
  fi

  set -e
  ./submit.sh -m "$version"

  SUCCESS "Once this is approved in the main repo," \
          "run the procedure for generating the RedHat container."
}

#-------------------------------------------------------------------------------
function upload_luarock() {
  rockspec=$1
  luarocks_api_key=$2
  if ! [ "$luarocks_api_key" ]
  then
     die "Kong API key for LuaRocks is required as an argument."
  fi

  set -e
  ensure_recent_luarocks

  luarocks --version

  luarocks upload --temp-key="$luarocks_api_key" "$rockspec" --force

  SUCCESS "The LuaRocks entry is now up!"
}

#-------------------------------------------------------------------------------
function approve_docker() {
  CONFIRM "The internal build system should have created a pull request in the docker-kong repo: " \
          "https://github.com/$GITHUB_ORG/docker-kong/pulls . Make sure it gets approved before continuing " \
          "to the step 'merge_docker'. Press Enter when done."
  SUCCESS "Docker PR approved. Proceeding!"
}

#-------------------------------------------------------------------------------
function merge_docker() {
  branch=$1
  version=$2

  if [ -d ../docker-kong ]
  then
     cd ../docker-kong
  else
     cd ..
     git clone git@github.com:$GITHUB_ORG/docker-kong.git
     cd docker-kong
  fi

  set -e
  git checkout "$branch"
  git pull
  git checkout master
  git pull
  git merge "$branch"
  git push
  git tag -s "$version" -m "$version"
  git push origin "$version"

  make_github_release_file

  hub release create -F "release-$version.txt" "$version"
  rm -f release-$version.txt

  SUCCESS "Now you can run the next step:" \
          "    $0 $version submit_docker"
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
function submit_docker() {
  version=$1

  if [ -d ../docker-kong ]
  then
     cd ../docker-kong
  else
     cd ..
     git clone git@github.com:$GITHUB_ORG/docker-kong.git
     cd docker-kong
  fi

  set -e
  ./submit.sh -m "$version"

  SUCCESS "Once this is approved in the main repo," \
          "run the procedure for generating the RedHat container."
}

#-------------------------------------------------------------------------------
function upload_luarock() {
  rockspec=$1
  luarocks_api_key=$2
  if ! [ "$luarocks_api_key" ]
  then
     die "Kong API key for LuaRocks is required as an argument."
  fi

  set -e
  ensure_recent_luarocks

  luarocks --version

  luarocks upload --temp-key="$luarocks_api_key" "$rockspec" --force

  SUCCESS "The LuaRocks entry is now up!"
}


if resty -v &> /dev/null
then
   LUA=resty
elif lua -v &> /dev/null
then
   LUA=lua
else
   die "Lua interpreter is not in PATH. Install any Lua or OpenResty to run this script."
fi


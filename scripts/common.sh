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
- [$version Changelog](https://github.com/Kong/kong/blob/$version/CHANGELOG.md#$versionlink)
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

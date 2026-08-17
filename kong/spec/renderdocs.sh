#!/bin/bash

# auto-doc renderer
#
# will watch the spec directory and upon changes automatically
# render the helper documentation using `ldoc .`
# resulting docs are in ./spec/docs/index.html

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
pushd $SCRIPT_DIR

watched_files=$(find . -name '*.lua')

if [ -z "$watched_files" ]; then
    echo "Nothing to watch, abort"
    exit 1
else
    echo "watching: $watched_files"
fi

previous_checksum="dummy"
while true ; do
    checksum=$(md5 $watched_files | md5)
    if [ "$checksum" != "$previous_checksum" ]; then
        ldoc .
        result=$?
        if [ $result -ne 0 ]; then
            echo -e "\033[0;31mldoc failed, exitcode: $result\033[0m"
            echo
        else
            echo
            echo "docs updated at: $(pwd)/docs/index.html"
            echo -e "\033[1;33mwatching for changes...\033[0m"
            echo
        fi
    fi
    previous_checksum="$checksum"
    sleep 1
done


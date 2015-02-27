#!/bin/bash

NEEDED_ROCKS="busted luacov luacov-coveralls luacheck"

for rock in ${NEEDED_ROCKS} ; do
  if ! command -v ${rock} &> /dev/null ; then
    echo ${rock} not found, installing via luarocks...
    luarocks install ${rock}
  fi
done

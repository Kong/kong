#!/usr/bin/env bash

# this runs on the host, before the Kong container is started


DESERIALISER_VERSION=$(grep openapi3 < kong-plugin-request-validator-*.rockspec | sed 's/^.*[^0-9]\([0-9]*\.[0-9]*\.[0-9]*\).*$/\1/')

if pushd lua-resty-openapi3-deserializer > /dev/null; then
  if git checkout "$DESERIALISER_VERSION"; then
    # version found, done
    popd > /dev/null
    exit 0
  fi
  git checkout master
  git pull

else
  token=${GITHUB_TOKEN// /}  # trim whitespace just in case

  if [[ "$token" == "" ]]; then
    git clone https://github.com/Kong/lua-resty-openapi3-deserializer.git || exit 1
  else
    git clone https://$token:@github.com/Kong/lua-resty-openapi3-deserializer.git || exit 1
  fi
  pushd lua-resty-openapi3-deserializer  > /dev/null
fi

git checkout "$DESERIALISER_VERSION"
popd > /dev/null

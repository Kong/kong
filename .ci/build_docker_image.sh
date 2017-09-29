#!/usr/bin/env bash
set -e

if [ ${TRAVIS_PULL_REQUEST} != "false" ]; then
  exit 0
fi

docker login -u="$DOCKER_USERNAME" -p="$DOCKER_PASSWORD"

git clone https://github.com/Mashape/docker-kong.git
git clone https://"$GITHUB_TOKEN"@github.com/Mashape/kong-distributions.git
pushd kong-distributions
docker pull hutchic/docker-packer

docker run -it --rm \
  -v $PWD:/src \
  -v /tmp:/tmp \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e KONG_CORE_BRANCH=master \
  -e KONG_ENTERPRISE_GUI_BRANCH=master \
  -e KONG_PROXY_CACHE_BRANCH=master \
  -e KONG_ENTERPRISE_OIDC_BRANCH=master \
  -e KONG_ENTERPRISE_INTROSPECTION_BRANCH=master \
  hutchic/docker-packer /src/package.sh -p alpine -e

popd
sudo mv kong-distributions/output/kong-*.tar.gz docker-kong/kong.tar.gz
docker build -t mashape/kong-enterprise:"$DOCKER_TAG_NAME" docker-kong/

docker push mashape/kong-enterprise:"$DOCKER_TAG_NAME"
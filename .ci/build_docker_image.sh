#!/usr/bin/env bash
set -e

if [ ${TRAVIS_PULL_REQUEST} != "false" ]; then
  exit 0
fi

docker login -u="$DOCKER_USERNAME" -p="$DOCKER_PASSWORD"

git clone https://github.com/Mashape/docker-kong.git
git clone https://"$GITHUB_TOKEN"@github.com/Mashape/kong-distributions.git
pushd kong-distributions
sed -i -e "s/^\([[:blank:]]*\)version.*$/\1version: master/" kong-images/build.yml
docker pull hutchic/docker-packer

docker run -it --rm \
  -v $PWD:/src \
  -v /tmp:/tmp \
  -v /var/run/docker.sock:/var/run/docker.sock \
  hutchic/docker-packer /src/package.sh -p alpine -e

popd
sudo mv kong-distributions/output/kong-*.tar.gz docker-kong/kong.tar.gz
sed -i -e '3 a COPY kong.tar.gz kong.tar.gz' Dockerfile
sed -i -e"/.*wget -O.*/,+1 d" docker-kong/Dockerfile

docker build -t mashape/kong-enterprise:"$DOCKER_TAG_NAME" docker-kong/

docker push mashape/kong-enterprise:"$DOCKER_TAG_NAME"
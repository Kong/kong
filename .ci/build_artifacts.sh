#!/usr/bin/env bash
set -e

if [ ${TRAVIS_PULL_REQUEST} != "false" ]; then
  exit 0
fi

docker login -u="$DOCKER_USERNAME" -p="$DOCKER_PASSWORD"

git clone https://github.com/Kong/docker-kong.git
git clone -b release/0.35 https://"$GITHUB_TOKEN"@github.com/Kong/kong-distributions.git
pushd kong-distributions
sed -i -e "s/^\([[:blank:]]*\)version.*$/\1version: master/" kong-images/build.yml
docker pull mashape/docker-packer

docker run -it --rm \
  -v $PWD:/src \
  -v /tmp:/tmp \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e NPM_TOKEN=$NPM_TOKEN \
  mashape/docker-packer /src/package.sh -p alpine -u "$BINTRAY_USER" -k "$BINTRAY_API_KEY" --ee --dev --verbose

docker run -it --rm \
  -v $PWD:/src \
  -v /tmp:/tmp \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e NPM_TOKEN=$NPM_TOKEN \
  -e TRAVIS_BUILD_NUMBER=$TRAVIS_BUILD_NUMBER \
  mashape/docker-packer /src/package.sh -p ubuntu:16.04 -u "$BINTRAY_USER" -k "$BINTRAY_API_KEY" --ee --dev --verbose

VERSION=`dpkg-deb -f output/kong-enterprise-edition-*.xenial.all.deb Version`
./release.sh -u $BINTRAY_USER -k $BINTRAY_API_KEY -v ${VERSION} -p ubuntu:16.04 -c

popd
sudo mv kong-distributions/output/kong-*.tar.gz docker-kong/alpine/kong.tar.gz
sed -i -e '3 a COPY kong.tar.gz kong.tar.gz' docker-kong/alpine/Dockerfile
sed -i -e"/.*wget -O.*/,+1 d" docker-kong/alpine/Dockerfile
sed -i -e '/apk update.*/a  && apk add gnupg \\' docker-kong/alpine/Dockerfile
sed -i -e '/^USER kong/d' docker-kong/alpine/Dockerfile


docker build --no-cache -t mashape/kong-enterprise:"$DOCKER_TAG_NAME" docker-kong/alpine/

docker push mashape/kong-enterprise:"$DOCKER_TAG_NAME"

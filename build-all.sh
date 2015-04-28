#!/bin/bash

set -o errexit

if ! [ "$(uname)" = "Darwin" ]; then
  echo "Run this script from OS X"
  exit 1
fi

if [ -z "$S3_ACCESS_KEY" ]; then echo "S3_ACCESS_KEY is unset" && exit 1; fi
if [ -z "$S3_SECRET" ]; then echo "S3_SECRET is unset" && exit 1; fi
if [ -z "$S3_REPO" ]; then echo "S3_REPO is unset" && exit 1; fi

platforms=( centos:5 centos:6 centos:7 debian:6 debian:7 ubuntu:12.04.5 ubuntu:14.04.2 )

VERSIONS_LOCATION="https://raw.githubusercontent.com/Mashape/kong/master/versions.sh"
SCRIPT_LOCATION="https://raw.githubusercontent.com/Mashape/kong/master/package-build.sh"

for i in "${platforms[@]}"
do
  echo "Building for $i"
  if [[ $i == centos* ]]; then
    eval 'docker run $i /bin/bash -c "export S3_ACCESS_KEY=\"'$S3_ACCESS_KEY'\" && export S3_SECRET=\"'$S3_SECRET'\" && export S3_REPO=\"'$S3_REPO'\" && yum -y install wget && wget $VERSIONS_LOCATION --no-check-certificate && wget -O - $SCRIPT_LOCATION --no-check-certificate | /bin/bash"'
  else
    eval 'docker run $i /bin/bash -c "export S3_ACCESS_KEY=\"'$S3_ACCESS_KEY'\" && export S3_SECRET=\"'$S3_SECRET'\" && export S3_REPO=\"'$S3_REPO'\" && apt-get update && apt-get -y install wget && wget $VERSIONS_LOCATION --no-check-certificate && wget -O - $SCRIPT_LOCATION --no-check-certificate | /bin/bash"'
  fi
done

# Also do OS X
/bin/bash -c "export S3_ACCESS_KEY=\"'$S3_ACCESS_KEY'\" && export S3_SECRET=\"'$S3_SECRET'\" && export S3_REPO=\"'$S3_REPO'\" && sh package-build.sh"
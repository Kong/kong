#!/bin/bash

set -o errexit

platforms=( centos:5 centos:6 centos:7 debian:6 debian:7 ubuntu:12.04.5 ubuntu:14.04.2 )

VERSIONS_LOCATION="https://raw.githubusercontent.com/Mashape/kong/fix/build/versions.sh"
SCRIPT_LOCATION="https://raw.githubusercontent.com/Mashape/kong/fix/build/package-build.sh"

for i in "${platforms[@]}"
do
  echo "Building for $i"
  if [[ $i == centos* ]]; then
  	eval 'docker run $i /bin/bash -c "export S3_ACCESS_KEY=\"'$S3_ACCESS_KEY'\" && export S3_SECRET=\"'$S3_SECRET'\" && export S3_REPO=\"'$S3_REPO'\" && yum -y install wget && wget $VERSIONS_LOCATION --no-check-certificate && wget -O - $SCRIPT_LOCATION --no-check-certificate | /bin/bash"'
  else
  	eval 'docker run $i /bin/bash -c "export S3_ACCESS_KEY=\"'$S3_ACCESS_KEY'\" && export S3_SECRET=\"'$S3_SECRET'\" && export S3_REPO=\"'$S3_REPO'\" && apt-get update && apt-get -y install wget && wget $VERSIONS_LOCATION --no-check-certificate && wget -O - $SCRIPT_LOCATION --no-check-certificate | /bin/bash"'
  fi
done

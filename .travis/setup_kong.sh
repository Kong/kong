#!/bin/bash

source ./versions.sh

sudo apt-get update
sudo apt-get install wget curl tar make gcc perl unzip git liblua${LUA_VERSION%.*}-0-dev lsb-release

PLATFORM=`lsb_release -cs`
wget https://github.com/Mashape/kong/releases/download/0.2.1/kong-0.2.1.${PLATFORM}_all.deb

# Install Kong
sudo apt-get install sudo netcat lua5.1 openssl libpcre3 dnsmasq
sudo dpkg -i ./.travis/kong-*.precise_all.deb
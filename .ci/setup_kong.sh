#!/bin/bash

KONG_VERSION=0.5.4

sudo apt-get update

# Installing dependencies required to build development rocks
sudo apt-get install wget curl tar make gcc unzip git

# Installing dependencies required for Kong
sudo apt-get install sudo netcat openssl libpcre3 dnsmasq uuid-dev

# Installing Kong and its dependencies
sudo apt-get install lsb-release

KONG_FILE="kong-"$KONG_VERSION"."`lsb_release -cs`"_all.deb"
curl -L -o $KONG_FILE http://54.231.14.48/kong-assets/kong-0.5.4featinvalidations.precise_all.deb

sudo dpkg -i $KONG_FILE

export PATH=$PATH:/usr/local/bin/

sudo luarocks remove kong --force
sudo rm -rf /etc/kong
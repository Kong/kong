#!/bin/bash

KONG_VERSION=0.5.0

sudo apt-get update

# Installing dependencies required to build development rocks
sudo apt-get install wget curl tar make gcc unzip git liblua5.1-0-dev

# Installing dependencies required for Kong
sudo apt-get install sudo netcat lua5.1 openssl libpcre3 dnsmasq

# Installing Kong and its dependencies
sudo apt-get install lsb-release

KONG_FILE="kong-"$KONG_VERSION"."`lsb_release -cs`"_all.deb"
curl -L -o $KONG_FILE https://github.com/Mashape/kong/releases/download/$KONG_VERSION/$KONG_FILE
sudo dpkg -i $KONG_FILE

sudo luarocks remove kong --force
sudo rm -rf /etc/kong
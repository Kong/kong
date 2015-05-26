#!/bin/bash

source ./versions.sh

sudo apt-get update

# Installing dependencies required to build development rocks
sudo apt-get install wget curl tar make gcc unzip git liblua5.1-0-dev

# Installing dependencies required for Kong
sudo apt-get install sudo netcat lua5.1 openssl libpcre3 dnsmasq

# Installing Kong and its dependencies
sudo dpkg -i ./.travis/kong-*.precise_all.deb

# Removing Kong only
sudo luarocks remove kong --force
sudo rm -rf /etc/kong
sudo rm -rf /usr/local/kong
#!/bin/bash

KONG_VERSION=0.5.4

sudo apt-get update
sudo apt-get install openssl libpcre3 dnsmasq uuid-dev lsb-release

KONG_PKG="kong-"$KONG_VERSION"."`lsb_release -cs`"_all.deb"
curl -L -o $KONG_PKG https://github.com/Mashape/kong/releases/download/$KONG_VERSION/$KONG_PKG
sudo dpkg -i $KONG_PKG

sudo luarocks remove kong --force
sudo rm -rf /etc/kong

#!/bin/bash

apt-get update

# Installing dependencies required to build development rocks
apt-get install wget curl tar make gcc unzip git liblua5.1-0-dev

# Installing dependencies required for Kong
apt-get install sudo netcat lua5.1 openssl libpcre3 dnsmasq

# Installing Kong and its dependencies
dpkg -i ./.travis/kong-0.3.0travis.precise_all.deb

luarocks remove kong --force
rm -rf /etc/kong
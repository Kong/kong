#!/bin/bash

command -v ssh-agent >/dev/null || ( sudo apt-get update -y && sudo apt-get install openssh-client -y )
eval $(ssh-agent -s)

mkdir -p ~/.ssh
chmod 700 ~/.ssh
mv $GITHUB_SSH_KEY ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa
ssh-add ~/.ssh/id_rsa
ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

git config --global user.email office@mashape.com
git config --global user.name mashapedeployment
git config --global url.ssh://git@github.com/.insteadOf https://github.com/

curl -fsSLo hub.tar.gz https://github.com/github/hub/releases/download/v2.14.2/hub-linux-amd64-2.14.2.tgz
tar -xzf hub.tar.gz -C /tmp
sudo mv /tmp/hub*/bin/hub /usr/local/bin/hub
sudo apt-get update
sudo apt-get install -yf lua5.2 liblua5.2

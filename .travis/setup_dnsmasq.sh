#!/bin/bash

sudo apt-get update && sudo apt-get install dnsmasq sudo
echo -e "user=root" | sudo tee /etc/dnsmasq.conf
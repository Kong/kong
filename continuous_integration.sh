#!/bin/sh
echo '1.kong continuous integration start...'
echo "2.check if we need to update the rockspec file:$1"
if [ $1 != "false" ]; then
	echo '3.checkout latest kong-customer-plugins-0.8.3-0.rockspec from https://github.com/kensou97/kong...'
	curl https://raw.githubusercontent.com/kensou97/kong/master/kong-custom-plugins-0.8.3-0.rockspec > /usr/local/kong/plugins/kong-custom-plugins-0.8.3-0.rockspec
else
	echo '3.there is no need to update the rock spec file,skip it...'
fi
cd /usr/local/kong/plugins/
echo '4.install latest kong-custom-plugins using luarocks...'
echo 'Zj4xyBkgjd'| sudo -S /usr/local/bin/luarocks install kong-custom-plugins-0.8.3-0.rockspec
echo '5.restart kong...'
echo 'Zj4xyBkgjd'|sudo -S /usr/local/bin/kong stop
echo 'Zj4xyBkgjd'|sudo -S /usr/local/bin/kong start

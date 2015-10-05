-- LDoc configuration file
-- See: https://github.com/stevedonovan/LDoc
--
-- LDoc installation;
--    luarocks install ldoc
--
-- Generate the documentation from the Kong codebase;
--    ldoc .
--

project='Kong'
title='Kong by Mashape'
description='Kong manages Microservices & APIs in a secure and extensible way'
format='discount'
file={'./kong/', './bin/kong'}
dir='doc'
readme='readme.md'
sort=true
sort_modules=true
not_luadoc=true
all=false

project='Kong'
title='public API'
description='Description of the Kong public API used for developing and testing custom plugins'
format="markdown"
file={
--[[
  './kong/dao/',
  './kong/tools/',
  './spec/',
]]
"./kong/pdk"
}
dir='doc'
--readme='readme.md'
sort=true
sort_modules=true
--not_luadoc=true
backtick_references=false
no_lua_ref=true

all=false

custom_tags = {
  { "phases", title = "Phases" },
}


-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cfg = require("luarocks.core.cfg")
assert(cfg.init())
-- print(require("inspect")(cfg))

local fs = require "luarocks.fs"
fs.init()

local queries = require("luarocks.queries")
local search = require("luarocks.search")

local name = arg[1]
local tree = arg[2]
local install_dest = arg[3]

local query = queries.new(name, nil, nil, true)

local _, ver = assert(search.pick_installed_rock(query))

if install_dest:sub(-1) ~= "/" then
    install_dest = install_dest .. "/"
end
-- HACK
cfg.lua_interpreter = "luajit"
cfg.sysconfdir = install_dest .. "etc/luarocks"
cfg.variables["LUA_DIR"] = install_dest .. "openresty/luajit"
cfg.variables["LUA_INCDIR"] = install_dest .. "openresty/luajit/include/luajit-2.1" 
cfg.variables["LUA_BINDIR"] = install_dest .. "openresty/luajit/bin"

local wrap = fs.wrap_script

wrap(
    string.format("%s/lib/luarocks/rocks-5.1/luarocks/%s/bin/%s", tree, ver, name),
    string.format("%s/bin/%s", tree, name), "one", name, ver) 

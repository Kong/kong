local pl_file = require "pl.file"
local pl_config = require "pl.config"
local pl_stringio = require "pl.stringio"

local f = assert(pl_file.read('./kong.conf.default'))
local s = pl_stringio.open(f)
local c = assert(pl_config.read(s))
s:close()
local inspect = require "inspect"
print(inspect(c))

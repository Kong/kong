#!/usr/bin/env resty

-- This file must be executed from the root folder, i.e.
-- ./autodoc/pdk/generate.lua
setmetatable(_G, nil)

local lfs = require("lfs")
local pl_utils = require "pl.utils"
local cjson = require "cjson"

local fmt = string.format

-- prepare output folder
lfs.mkdir("autodoc")
lfs.mkdir("autodoc/output")
lfs.mkdir("autodoc/output/pdk")

print("Building PDK docs...")

-- Generate navigation yml
local cmd = "ldoc -q -i --filter autodoc/pdk/ldoc/filters.nav ./kong/pdk"
local ok, code, stdout, stderr = pl_utils.executeex(cmd)
assert(ok and code == 0, stderr)
local outputpath = "autodoc/output/_pdk_nav.yml"
local outfd = assert(io.open(outputpath, "w+"))
outfd:write(stdout)
outfd:close()
print("  Wrote " .. outputpath)

-- Obtain the list of modules in json form & parse it
local cmd = 'ldoc -q -i --filter autodoc/pdk/ldoc/filters.json ./kong/pdk'
local ok, code, stdout, stderr = pl_utils.executeex(cmd)
assert(ok and code == 0, stderr)
local modules = cjson.decode(stdout)

local outputfolder = "autodoc/output/pdk"
for _,module in ipairs(modules) do
  local outputpath = fmt("%s/%s.md", outputfolder, module.name)
  cmd = fmt("ldoc -q -c autodoc/pdk/ldoc/config.ld %s && mv ./%s.md %s",
            module.file,
            module.generated_name,
            outputpath)
  local ok, code, _, stderr = pl_utils.executeex(cmd)
  assert(ok and code == 0, stderr)
  print("  Wrote " .. outputpath)
end

#!/usr/bin/env resty

-- This file must be executed from the root folder, i.e.
-- ./autodoc/upgrading/generate.lua
setmetatable(_G, nil)

local lfs = require("lfs")

local header = [[
---
# Generated via autodoc/upgrading/generate.lua in the kong/kong repo
title: Upgrade Kong Gateway OSS
badge: oss
---

This document guides you through the process of upgrading {{site.ce_product_name}} to the **latest version**.
To upgrade to prior versions, find the version number in the
[Upgrade doc in GitHub](https://github.com/Kong/kong/blob/master/UPGRADE.md).

]]


lfs.mkdir("autodoc")
lfs.mkdir("autodoc/output")
local outpath = "autodoc/output/upgrading.md"

print("Building upgrading.md")

local input = assert(io.open("UPGRADE.md", "r+"))

-- Keep skipping lines until "## Suggested upgrade path"
local line
while true do
  line = input:read()
  if line == nil then
    error("Could not find the `## Suggested upgrade path` line")
  end
  if line:match("## Suggested upgrade path") then
    break
  end
end

-- Read everything until THE SECOND "## Upgrade to xxx" line
local buffer = { line }
local upgrade_counter = 0

while true do
  line = input:read()
  if line == nil then
    error("Could not find two `## Upgrade to xxx` lines")
  end


  if line:match("## Upgrade to ") then
    upgrade_counter = upgrade_counter + 1
    if upgrade_counter == 2 then
      break
    end
  end

  buffer[#buffer + 1] = line
end

input:close()

-- Write header + selected body to output
local output = assert(io.open(outpath, "w+"))
output:write(header)
output:write(table.concat(buffer, "\n"))
output:close()


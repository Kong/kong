#!/usr/bin/env resty

-- This file must be executed from the root folder, i.e.
-- ./autodoc/cli/generate.lua
setmetatable(_G, nil)

local lfs = require("lfs")

local data = require("autodoc.cli.data")

local cmds = {}
for file in lfs.dir("kong/cmd") do
  local cmd = file:match("(.*)%.lua$")
  if cmd and cmd ~= "roar" and cmd ~= "init" then
    table.insert(cmds, cmd)
  end
end
table.sort(cmds)

lfs.mkdir("autodoc")
lfs.mkdir("autodoc/output")
local outpath = "autodoc/output/cli.md"
local outfd = assert(io.open(outpath, "w+"))

outfd:write(data.header)

local function write(str)
  outfd:write(str)
  outfd:write("\n")
end

print("Building CLI docs...")

for _, cmd in ipairs(cmds) do
  write("")
  write("### kong " .. cmd)
  write("")
  if data.command_intro[cmd] then
    write((("\n"..data.command_intro[cmd]):gsub("\n%s+", "\n"):gsub("^\n", "")))
  end
  write("```")
  local pd = io.popen("bin/kong " .. cmd .. " --help 2>&1")
  local info = pd:read("*a")
  info = info:gsub(" %-%-v[^\n]+\n", "")
  info = info:gsub("\nOptions:\n$", "")
  write(info)
  pd:close()
  write("```")
  write("")
  write("[Back to top](#introduction)")
  write("")
  write("---")
  write("")
end

outfd:write(data.footer)

outfd:close()

print("  Wrote " .. outpath)

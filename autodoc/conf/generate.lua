#!/usr/bin/env resty

-- This file must be executed from the root folder, i.e.
-- ./autodoc/conf/generate.lua
setmetatable(_G, nil)

local lfs = require("lfs")

local data = require("autodoc.conf.data")
local parser = require("autodoc.conf.parser")

-- "EXAMPLE of teXT" => "Example Of Text". NGINX and DNS are kept uppercase
local function titleize(str)
  return str:gsub("(%a)([%w_']*)", function(first, rest)
    return first:upper()..rest:lower()
  end):gsub("Nginx", "NGINX"):gsub("Dns", "DNS")
end

-- Given a text, wrap it to the given max width
local function word_wrap(text, newline_prefix, width)
  width = width or 80

  local remaining = width
  local res = {}
  local line = {}

  for word in text:gmatch("%S+") do
    if #word + 1 > remaining then
      res[#res + 1] = table.concat(line, " ")
      if newline_prefix then
        word = newline_prefix .. word
      end
      line = { word }
      remaining = width - #word

    else
      line[#line + 1] = word
      remaining = remaining - (#word + 1)
    end
  end

  res[#res + 1] = table.concat(line, " ")
  return table.concat(res, "\n")
end

-- Formats a description's markdown by:
-- * Applying word-wrap of 80 characters to ps and uls
-- * Keeping code sections intact
-- * Fixing spacing and consistently adding empty lines between blocks.
local function format_description(description)
  local blocks_buffer = {}
  for i, block in ipairs(description) do
    if block.type == "ul" then

      local items_buffer = {}
      for j, line in ipairs(block.items) do
        items_buffer[j] = word_wrap("- " .. line, "  ")
      end
      blocks_buffer[i] = table.concat(items_buffer, "\n")

    elseif block.type == "code" then
      blocks_buffer[i] = table.concat({ "```", block.text, "```" }, "\n")

    else
      blocks_buffer[i] = word_wrap(block.text)
    end
  end
  return table.concat(blocks_buffer, "\n\n")
end


-- Given a list of markdown blocks, format it as a single line, for putting inside a table cell.
-- uls or code blocks will just raise an error.
local function format_description_as_line(description)
  local blocks_buffer = {}
  local len = 0
  for i, block in ipairs(description) do
    if i > 1 then
      len = len + 1
      blocks_buffer[len] = " "
    end

    if block.type == "ul" then
      error("Cannot format a markdown ul as a line for a table. Use an HTML table instead")
    elseif block.type == "code" then
      error("Cannot format markdown code as a line for a table. Use an HTML table instead")
    else
      len = len + 1
      blocks_buffer[len] = string.gsub(block.text, "\n", " ")
    end
  end

  return table.concat(blocks_buffer)
end


local function format_default(default)
  return default and "`" .. default .. "`" or "none"
end


local table_header = [[
name   | description  | default
-------|--------------|----------]]


local inputpath = "kong.conf.default"
local infd = assert(io.open(inputpath, "r"))
local lines = {}
for line in infd:lines() do
  table.insert(lines, line)
end
infd:close()

local parsed = assert(parser.parse(lines))

lfs.mkdir("autodoc")
lfs.mkdir("autodoc/output")
local outpath = "autodoc/output/configuration.md"
local outfd = assert(io.open(outpath, "w+"))

outfd:write(data.header)


local function write(str)
  outfd:write(str)
  outfd:write("\n")
end

print("Building Configuration docs...")

for _, section in ipairs(parsed) do
  write("")
  write("### " .. titleize(section.name) .. " section")
  write("")
  if section.description and #section.description > 0 then
    write(format_description(section.description))
    write("")
    write("---")
    write("")
  end

  local pg_found = false
  local cassandra_found = false
  local render_as_table = false

  for _, var in ipairs(section.vars) do

    if string.match(var.name, "^pg_.+$") then
      render_as_table = true
      if not pg_found then
        pg_found = true
        write("")
        write("#### Postgres settings")
        write("")
        write(table_header)
      end

    elseif string.match(var.name, "^cassandra_.+$") then
      render_as_table = true
      if not cassandra_found then
        cassandra_found = true
        write("")
        write("#### Cassandra settings")
        write("")
        write(table_header)
      end

    else
      if render_as_table then
        write("")
      end
      render_as_table = false
    end

    if render_as_table then
      write("**" .. var.name ..
            "** | " .. format_description_as_line(var.description) ..
              " | " .. format_default(var.default))

    else
      write("#### " .. var.name)
      write("")
      write(format_description(var.description))
      write("")
      write("Default: " .. format_default(var.default))
      write("")
      write("---")
      write("")
    end
  end
end

outfd:write(data.footer)

outfd:close()

print("  Wrote " .. outpath)

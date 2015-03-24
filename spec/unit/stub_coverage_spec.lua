-- This file requires all .lua files from kong's src/ folder in order to compute the real coverage
-- since not all files are currently unit tested and the coverage is erroneous.

local utils = require "kong.tools.utils"

-- Stub DAO for lapis controllers
_G.dao = {}

local lua_sources = utils.retrieve_files(".//src", { exclude_dir_pattern = "cli", file_pattern = ".lua" })

for _, source_link in ipairs(lua_sources) do
  local source_file = dofile(source_link)
end

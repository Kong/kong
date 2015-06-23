-- This file requires all .lua files from kong's kong/ folder in order to compute the real coverage
-- since not all files are currently unit tested and the coverage is erroneous.

local IO = require "kong.tools.io"

-- Stub DAO for lapis controllers
_G.dao = {}

local lua_sources = IO.retrieve_files("./kong", { exclude_dir_patterns = {"cli", "vendor", "filelog", "reports"}, file_pattern = ".lua$" })

for _, source_link in ipairs(lua_sources) do
  dofile(source_link)
end

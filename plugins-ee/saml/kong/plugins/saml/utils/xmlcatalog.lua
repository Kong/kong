-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local datafile = require "datafile"
local ffi = require "ffi"


local xml2 = ffi.load "xml2"


ffi.cdef([[
  int xmlLoadCatalog(const char *filename);
  ]])


local function load(path)
  local catalog_load_result = xml2.xmlLoadCatalog(assert(datafile.path(path)))
  if catalog_load_result ~= 0 then
    error("cannot load XML catalog " .. path)
  end
end


return {
  load = load,
}

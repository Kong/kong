local ffi = require "ffi"


ffi.cdef [[
  int isatty(int fd);
]]


local function isatty()
  return ffi.C.isatty(0) == 1
end


return {
  isatty = isatty,
}

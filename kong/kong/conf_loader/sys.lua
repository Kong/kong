local ffi = require "ffi"
local C = ffi.C


ffi.cdef([[
  struct group *getgrnam(const char *name);
  struct passwd *getpwnam(const char *name);
  int unsetenv(const char *name);
]])


return {
  getgrnam = C.getgrnam,
  getpwnam = C.getpwnam,

  getenv   = os.getenv,
  unsetenv = C.unsetenv,
}


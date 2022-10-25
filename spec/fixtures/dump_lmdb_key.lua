local lmdb = require("resty.lmdb")
local key = assert(arg[1])

ngx.print(lmdb.get(key))

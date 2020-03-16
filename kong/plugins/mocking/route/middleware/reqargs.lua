-- TODO: Rewrite needed
local reqargs = require "resty.reqargs"
local remove  = os.remove
local pairs   = pairs
local function cleanup(self)
    local files = self.files
    for _, f in pairs(files) do
        if f.n then
            for i = 1, f.n do
                remove(f[i].temp)
            end
        else
            remove(f.temp)
        end
    end
    self.files = {}
end
return function(self)
    return function(options)
        local get, post, files = reqargs(options)
        self.route:after(cleanup)
        self.get   = get
        self.post  = post
        self.files = files
    end
end
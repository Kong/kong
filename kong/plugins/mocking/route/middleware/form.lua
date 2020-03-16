-- TODO: Rewrite needed
local form = require "resty.validation".fields
return function(self)
    self.form = form
end

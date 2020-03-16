-- TODO: Rewrite needed
local var = ngx.var
return function(self)
    self.ajax = var.http_x_requested_with == "XMLHttpRequest"
end

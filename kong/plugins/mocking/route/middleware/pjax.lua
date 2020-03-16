-- TODO: Rewrite needed
local var = ngx.var
return function(self)
    if not not var.http_x_pjax then
        self.pjax = {
            container = var.http_x_pjax_container,
            version   = var.http_x_pjax_version
        }
    end
end
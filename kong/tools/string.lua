local _M = {}


local replace_dashes
do
  if ngx and ngx.config.subsystem == "http" then

    -- 1,000,000 iterations with input of "my-header":
    -- string.gsub:        81ms
    -- ngx.re.gsub:        74ms
    -- loop/string.buffer: 28ms
    -- str_replace_char:   14ms
    local str_replace_char = require("resty.core.utils").str_replace_char

    replace_dashes = function(str)
      return str_replace_char(str or "", "-", "_")
    end

  else    -- stream subsystem
    replace_dashes = function(str)
      if not find(str or "", "-", nil, true) then
        return str
      end

      return gsub(str, "-", "_")
    end
  end
end
_M.replace_dashes = replace_dashes


return _M


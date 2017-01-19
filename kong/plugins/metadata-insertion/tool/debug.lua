return {
  print_r = function(t)
    local print_r_cache = {}
    local function sub_print_r(t, indent)
      if (print_r_cache[tostring(t)]) then
        print(indent .. "*" .. tostring(t))
      else
        print_r_cache[tostring(t)] = true
        if (type(t) == "table") then
          for pos, val in pairs(t) do
            if (type(val) == "table") then
              print(indent .. "[" .. pos .. "] => " .. tostring(t) .. " {")
              sub_print_r(val, indent .. string.rep(" ", string.len(pos) + 8))
              print(indent .. string.rep(" ", string.len(pos) + 6) .. "}")
            else
              print(indent .. "[" .. pos .. "] => " .. tostring(val))
            end
          end
        else
          print(indent .. tostring(t))
        end
      end
    end

    sub_print_r(t, "  ")
  end,
  log_r = function(t)
    local print_r_cache = {}
    local function sub_print_r(t, indent)
      if (print_r_cache[tostring(t)]) then
        ngx.log(ngx.ERR, "=== : " .. indent .. "*" .. tostring(t))
      else
        print_r_cache[tostring(t)] = true
        if (type(t) == "table") then
          for pos, val in pairs(t) do
            if (type(val) == "table") then
              ngx.log(ngx.ERR, "=== : " .. indent .. "[" .. pos .. "] => " .. tostring(t) .. " {")
              sub_print_r(val, indent .. string.rep(" ", string.len(pos) + 8))
              ngx.log(ngx.ERR, "=== : " .. indent .. string.rep(" ", string.len(pos) + 6) .. "}")
            else
              ngx.log(ngx.ERR, "=== : " .. indent .. "[" .. pos .. "] => " .. tostring(val))
            end
          end
        else
          ngx.log(ngx.ERR, "=== : " .. indent .. tostring(t))
        end
      end
    end

    sub_print_r(t, "  ")
  end
}
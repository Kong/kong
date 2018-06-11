local pl_utils = require "pl.utils"
local log = require "kong.cmd.utils.log"
local fmt = string.format


local cmd = [[ printenv ]]


local function read_all()
  log.debug("reading environment variables: %s", cmd)

  local vars = {}
  local success, ret_code, stdout, stderr = pl_utils.executeex(cmd)
  if not success or ret_code ~= 0 then
    return nil, fmt("could not read environment variables (exit code: %d): %s",
                    ret_code, stderr)
  end

  for line in stdout:gmatch("[^\r\n]+") do
    local i = string.find(line, "=") -- match first =

    if i then
      local k = string.sub(line, 1, i - 1)
      local v = string.sub(line, i + 1)

      if k and v then
        vars[k] = v
      end
    end
  end

  return vars
end


return {
  read_all = read_all,
}

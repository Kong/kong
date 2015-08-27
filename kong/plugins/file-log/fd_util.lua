local _M = {}

local fd = {}

function _M.get_fd(conf_path)
  return fd[conf_path]
end

function _M.set_fd(conf_path, file_descriptor)
  fd[conf_path] = file_descriptor
end

return _M
local _M = {}

local fd = nil

function _M.get_fd()
  return fd
end

function _M.set_fd(file_descriptor)
  fd = file_descriptor
end

return _M
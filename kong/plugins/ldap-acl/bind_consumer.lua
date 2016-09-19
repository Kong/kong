local BindConsumer = { dao = nil }

function BindConsumer:new(o)
  o = o or {} -- create object if user does not provide one
  setmetatable(o, self)
  self.__index = self
  return o
end

function BindConsumer.bind(self, username)
  local consumers = self.dao:find_all { username = username }
  if consumers then
    return consumers[1]
  end
end

return BindConsumer
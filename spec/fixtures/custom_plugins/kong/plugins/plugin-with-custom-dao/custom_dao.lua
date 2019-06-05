local CustomDAO = {}


function CustomDAO:custom_method()
  return self.strategy:custom_method()
end


return CustomDAO

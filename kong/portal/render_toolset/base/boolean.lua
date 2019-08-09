local render_print = require 'pl.pretty'.write


-- returns string reperesentation of ctx
local function print(self)
  return render_print(self.ctx)
end


return {
  print = print,
  p     = print,
}

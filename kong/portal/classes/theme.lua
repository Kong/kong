local Theme = {}

function Theme:new(conf)
  local o = {
    ctx = conf
  }

  return o
end

function Theme:colors()
  return self.ctx.colors
end

function Theme:fonts()
  return self.ctx.fonts
end

return Theme

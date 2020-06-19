local function print(self)
  return self.ctx
end


return {
  print = print,
  p     = print,
}

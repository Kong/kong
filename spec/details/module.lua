
-- totally clean the module then load it
local function reload(name)
  package.loaded[name] = nil
  return require(name)
end


return {
  reload = reload,
}

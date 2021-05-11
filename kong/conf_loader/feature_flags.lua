
local kong = kong

local feature_flags = {}

function feature_flags.set_variants(module_name, flag_name, options)
  if package.loaded[module_name] ~= nil then
    return nil, ("module %q alread loaded"):format(module_name)
  end

  if package.preload[module_name] ~= nil then
    return nil, ("module %q already modified"):format(module_name)
  end

  package.preload[module_name] = function(modname)
    if modname ~= module_name then
      return nil, ("conflict: expecting module name %q, received %q"):format(module_name, modname)
    end

    local flag_value = kong.configuration[flag_name]
    if not flag_value then
      return nil, ("flag %q has no valid value"):format(flag_name)
    end

    local module_path = options[flag_value]
    if not module_path then
      return nil, ("flag value %q for module %q not defined"):format(flag_value, module_name)
    end

    return assert(loadfile(module_path, "t"))()
  end
end

return feature_flags

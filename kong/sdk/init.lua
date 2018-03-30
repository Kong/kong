local MAJOR_VERSIONS = {
  [0] = {
    version = "0.0.1",
    modules = {
      "request",
    }
  },

  [1] = {
    version = "1.0.0",
    modules = {
      "request",
      --[[
      "upstream",
      "upstream.response",
      "response",
      "timers",
      "http",
      "utils",
      "shm",
      --]]
    }
  },

  latest = 1,
}


local _SDK = {
  major_versions = MAJOR_VERSIONS,
}


function _SDK.new(major_version)
  if major_version and type(major_version) ~= "number" then
    error("major_version must be a number", 2)
  end

  if not major_version then
    major_version = MAJOR_VERSIONS.latest
  end

  local version_meta = MAJOR_VERSIONS[major_version]

  local sdk = {
    sdk_major_version = major_version,
    sdk_version = version_meta.version,
    sdk_version_num = nil, -- TODO (not sure if needed at all)
  }

  for _, module_name in ipairs(version_meta.modules) do
    local mod = require("kong.sdk." .. module_name)

    if mod.namespace then
      -- namespaced SDK module, for the likes of:
      --   kong.request.get_scheme()
      --   kong.response.set_header()

      if not sdk[mod.namespace] then
        sdk[mod.namespace] = {}
      end

      mod.new(sdk[mod.namespace], major_version)

    else
      -- top-level namespace, directly attach the created functions to the
      -- root SDK instance. Dangeroud but elegant for methods like:
      --   kong.get_phase() -- NYI
      --   kong.do_top_level_action() -- NYI

      mod.new(sdk)
    end
  end

  return sdk
end


return _SDK

-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.admin_gui.utils"
local ee_admin_gui = require "kong.enterprise_edition.admin.gui"

local fmt = string.format
local insert = table.insert
local concat = table.concat

local select_listener = utils.select_listener
local prepare_variable = utils.prepare_variable

local _M = {}

function _M.generate_kconfig(kong_config)
  local api_listen = select_listener(kong_config.admin_listeners, {ssl = false})
  local api_port = api_listen and api_listen.port

  local api_ssl_listen = select_listener(kong_config.admin_listeners, {ssl = true})
  local api_ssl_port = api_ssl_listen and api_ssl_listen.port

  local configs = {
    ADMIN_GUI_URL = prepare_variable(kong_config.admin_gui_url),
    ADMIN_GUI_PATH = prepare_variable(kong_config.admin_gui_path),
    ADMIN_API_URL = prepare_variable(kong_config.admin_gui_api_url),
    ADMIN_API_PORT = prepare_variable(api_port),
    ADMIN_API_SSL_PORT = prepare_variable(api_ssl_port),
    ANONYMOUS_REPORTS = prepare_variable(kong_config.anonymous_reports),
  }
  ee_admin_gui.fill_ee_kconfigs(kong_config, configs)

  local out = {}
  for config, value in pairs(configs) do
    insert(out, fmt("  '%s': '%s'", config, value))
  end

  return "window.K_CONFIG = {\n" .. concat(out, ",\n") .. "\n}\n"
end

return _M

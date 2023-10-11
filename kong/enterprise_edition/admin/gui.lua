-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local utils = require "kong.admin_gui.utils"
local portal_and_vitals_allowed = require "kong.enterprise_edition.license_helpers".portal_and_vitals_allowed

local _M = {}

function _M.fill_ee_kconfigs(kong_config, config_table)
  -- we will consider rbac to be on if it is set to "both" or "on",
  -- because we don't currently support entity-level
  local rbac_enforced = kong_config.rbac == "both" or kong_config.rbac == "on"

  local portal = kong_config.portal

  if portal and not portal_and_vitals_allowed() then
    portal = false
  end

  config_table['ADMIN_GUI_AUTH'] = utils.prepare_variable(kong_config.admin_gui_auth)
  config_table['ADMIN_GUI_HEADER_TXT'] = utils.prepare_variable(kong_config.admin_gui_header_txt)
  config_table['ADMIN_GUI_HEADER_BG_COLOR'] = utils.prepare_variable(kong_config.admin_gui_header_bg_color)
  config_table['ADMIN_GUI_HEADER_TXT_COLOR'] = utils.prepare_variable(kong_config.admin_gui_header_txt_color)
  config_table['ADMIN_GUI_FOOTER_TXT'] = utils.prepare_variable(kong_config.admin_gui_footer_txt)
  config_table['ADMIN_GUI_FOOTER_BG_COLOR'] = utils.prepare_variable(kong_config.admin_gui_footer_bg_color)
  config_table['ADMIN_GUI_FOOTER_TXT_COLOR'] = utils.prepare_variable(kong_config.admin_gui_footer_txt_color)
  config_table['ADMIN_GUI_LOGIN_BANNER_TITLE'] = utils.prepare_variable(kong_config.admin_gui_login_banner_title)
  config_table['ADMIN_GUI_LOGIN_BANNER_BODY'] = utils.prepare_variable(kong_config.admin_gui_login_banner_body)
  config_table['RBAC'] = utils.prepare_variable(kong_config.rbac)
  config_table['RBAC_ENFORCED'] = utils.prepare_variable(rbac_enforced)
  config_table['RBAC_HEADER'] = utils.prepare_variable(kong_config.rbac_auth_header)
  config_table['RBAC_USER_HEADER'] = utils.prepare_variable(kong_config.admin_gui_auth_header)
  config_table['FEATURE_FLAGS'] = utils.prepare_variable(kong_config.admin_gui_flags)
  config_table['PORTAL'] = utils.prepare_variable(portal)
  config_table['PORTAL_GUI_PROTOCOL'] = utils.prepare_variable(kong_config.portal_gui_protocol)
  config_table['PORTAL_GUI_HOST'] = utils.prepare_variable(kong_config.portal_gui_host)
  config_table['PORTAL_GUI_USE_SUBDOMAINS'] = utils.prepare_variable(kong_config.portal_gui_use_subdomains)
end

return _M

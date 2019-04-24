local singletons = require "kong.singletons"
local workspaces = require "kong.workspaces"
local constants  = require "kong.constants"

local ws_constants = constants.WORKSPACE_CONFIG


describe("retrieve_ws_config", function()
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()

    singletons.configuration = {
      portal_auth = "basic-auth",
      portal_auth_conf = "{ hide_credentials = true }",
      portal_auto_approve = true,
      portal_token_exp = 3600,
      smtp_mock = true,
      portal_invite_email = true,
      portal_access_request_email = true,
      portal_approved_email = true,
      portal_reset_email = true,
      portal_reset_success_email = true,
      portal_emails_from = "hotdog@konghq.com",
      portal_emails_reply_to = "hotdog@konghq.com",
      smtp_admin_emails = {"admin@example.com"},
      portal_session_conf = {
        cookie_name = "yum",
      },
    }
  end)

  after_each(function()
    snapshot:revert()
  end)

  it("should defer to default config value when not present in db", function()
    local workspace = {
      config = {
        portal = false,
      }
    }

    local ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTH, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_auth)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTH_CONF, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_auth_conf)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTO_APPROVE, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_auto_approve)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_TOKEN_EXP, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_token_exp)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_INVITE_EMAIL, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_invite_email)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_ACCESS_REQUEST_EMAIL, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_access_request_email)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_APPROVED_EMAIL, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_reset_email)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_RESET_EMAIL, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_reset_success_email)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_RESET_SUCCESS_EMAIL, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_reset_success_email)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_EMAILS_FROM, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_emails_from)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_emails_reply_to)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_CORS_ORIGINS, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_cors_origins)
  end)

  it("should overwrite default config value when present in db", function()
    local workspace = {
      config = {
        portal_auth = "key-auth",
        portal_auth_conf = "{}",
        portal_auto_approve = false,
        portal_token_exp = 1000,
        smtp_mock = false,
        portal_invite_email = false,
        portal_access_request_email = false,
        portal_approved_email = false,
        portal_reset_email = false,
        portal_reset_success_email = false,
        portal_emails_from = "hugo@konghq.com",
        portal_emails_reply_to = "bobby@konghq.com",
        smtp_admin_emails = {"carl@example.com"},
        portal_cors_origins = {"http://foo.example", "http://bar.example"}
      }
    }

    local ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTH, workspace)
    assert.equal(ws_conf_item, workspace.config.portal_auth)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTH_CONF, workspace)
    assert.equal(ws_conf_item, workspace.config.portal_auth_conf)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTO_APPROVE, workspace)
    assert.equal(ws_conf_item, workspace.config.portal_auto_approve)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_TOKEN_EXP, workspace)
    assert.equal(ws_conf_item, workspace.config.portal_token_exp)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_INVITE_EMAIL, workspace)
    assert.equal(ws_conf_item, workspace.config.portal_invite_email)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_ACCESS_REQUEST_EMAIL, workspace)
    assert.equal(ws_conf_item, workspace.config.portal_access_request_email)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_APPROVED_EMAIL, workspace)
    assert.equal(ws_conf_item, workspace.config.portal_reset_email)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_RESET_EMAIL, workspace)
    assert.equal(ws_conf_item, workspace.config.portal_reset_success_email)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_RESET_SUCCESS_EMAIL, workspace)
    assert.equal(ws_conf_item, workspace.config.portal_reset_success_email)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_EMAILS_FROM, workspace)
    assert.equal(ws_conf_item, workspace.config.portal_emails_from)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_EMAILS_REPLY_TO, workspace)
    assert.equal(ws_conf_item, workspace.config.portal_emails_reply_to)
    ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_CORS_ORIGINS, workspace)
    assert.same(ws_conf_item, workspace.config.portal_cors_origins)
  end)

  it("should defer to default portal-auth when set to 'nil'", function()
    local workspace = {
      config = {
        portal_auth = nil,
      }
    }

    local ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTH, workspace)
    assert.equal(ws_conf_item, singletons.configuration.portal_auth)
  end)

  it("should not defer to default portal-auth when set to emtpy string", function()
    local workspace = {
      config = {
        portal_auth = '',
      }
    }

    local ws_conf_item = workspaces.retrieve_ws_config(ws_constants.PORTAL_AUTH, workspace)
    assert.equal(ws_conf_item, workspace.config.portal_auth)
  end)

  it("should return error if value not available", function()
    singletons.configuration = {
      portal_auth = "basic-auth",
    }

    local workspace = {
      config = {
        portal_auth = "key-auth",
      }
    }

    local ws_conf_item = workspaces.retrieve_ws_config('hotdog', workspace)
    assert.is_nil(ws_conf_item)
  end)

  it("should return a copy of table values to not mutate singletons", function()
    local workspace = {
      config = {}
    }

    local session_conf = workspaces.retrieve_ws_config(ws_constants.PORTAL_SESSION_CONF, workspace)
    assert.same(session_conf, singletons.configuration.portal_session_conf)
    session_conf.cookie_name = "MUTATION!"

    local session_conf_2 = workspaces.retrieve_ws_config(ws_constants.PORTAL_SESSION_CONF, workspace)
    assert.same(session_conf_2, singletons.configuration.portal_session_conf)

    assert.not_equal(session_conf_2.cookie_name, session_conf.cookie_name)
  end)

  it("should return a copy of table values to not mutate workspace config", function()
    local workspace = {
      config = {
        portal_session_conf = {
          cookie_name = "reee",
        },
      }
    }
    local session_conf = workspaces.retrieve_ws_config(ws_constants.PORTAL_SESSION_CONF, workspace)
    assert.same(session_conf, workspace.config.portal_session_conf)
    session_conf.cookie_name = "MUTATION!"

    local session_conf_2 = workspaces.retrieve_ws_config(ws_constants.PORTAL_SESSION_CONF, workspace)
    assert.same(session_conf_2, workspace.config.portal_session_conf)
    assert.not_equal(session_conf_2.cookie_name, session_conf.cookie_name)
  end)
end)

describe("build_ws_portal_gui_url", function()
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
  end)

  after_each(function()
    snapshot:revert()
  end)

  it("should place workspace as path if portal_gui_use_subdomains off", function()
    local config = {
      portal_gui_host = 'mykewlwebsite.org',
      portal_gui_protocol = 'http',
      portal_gui_use_subdomains = false,
    }

    local workspace = {
      name = "test_workspace"
    }

    local expected_url = 'http://mykewlwebsite.org/test_workspace'
    local portal_gui_url = workspaces.build_ws_portal_gui_url(config, workspace)
    assert.equal(portal_gui_url, expected_url)
  end)

  it("should place workspace as subdomain if portal_gui_use_subdomains on", function()
    local config = {
      portal_gui_host = 'mykewlwebsite.org',
      portal_gui_protocol = 'https',
      portal_gui_use_subdomains = true,
    }

    local workspace = {
      name = "test_workspace"
    }

    local expected_url = 'https://test_workspace.mykewlwebsite.org'
    local portal_gui_url = workspaces.build_ws_portal_gui_url(config, workspace)
    assert.equal(portal_gui_url, expected_url)
  end)

  it("should properly handle host with subdomain present", function()
    local config = {
      portal_gui_host = 'subdomain.mykewlwebsite.org',
      portal_gui_protocol = 'http',
      portal_gui_use_subdomains = true,
    }

    local workspace = {
      name = "test_workspace"
    }

    local expected_url = 'http://test_workspace.subdomain.mykewlwebsite.org'
    local portal_gui_url = workspaces.build_ws_portal_gui_url(config, workspace)
    assert.equal(portal_gui_url, expected_url)
  end)
end)

describe("build_ws_admin_gui_url", function()
  local snapshot

  before_each(function()
    snapshot = assert:snapshot()
  end)

  after_each(function()
    snapshot:revert()
  end)

  it("should return admin_gui_url if no workspace name", function()
    local config = {
      admin_gui_url = "http://admins-are-fun.org",
    }

    local workspace = {}

    local expected_url = "http://admins-are-fun.org"
    local admin_gui_url = workspaces.build_ws_admin_gui_url(config, workspace)
    assert.equal(admin_gui_url, expected_url)
  end)

  it("should return admin_gui_url appended with workspace name", function()
    local config = {
      admin_gui_url = 'http://admins-are-fun.org',
    }

    local workspace = {
      name = "test_workspace"
    }

    local expected_url = 'http://admins-are-fun.org/test_workspace'
    local admin_gui_url = workspaces.build_ws_admin_gui_url(config, workspace)
    assert.equal(admin_gui_url, expected_url)
  end)
end)

describe("build_ws_portal_cors_origins", function()
  it("should return portal_cors_origins if set", function()
    local workspace = {
      config = {
        portal_cors_origins = { "wow" },
        portal_gui_protocol = "http",
        portal_gui_host = "www.example.com",
      }
    }

    local origins = workspaces.build_ws_portal_cors_origins(workspace)
    assert.same({ "wow" }, origins)
  end)

  it("should derive origin from portal_gui_protocol and portal_gui_host if portal_cors_origins is empty", function()
    local workspace = {
      config = {
        portal_cors_origins = {},
        portal_gui_protocol = "http",
        portal_gui_host = "example.com",
      }
    }

    local origins = workspaces.build_ws_portal_cors_origins(workspace)
    assert.same({ "http://example.com" }, origins)
  end)

  it("should derive origin from portal_gui_protocol and portal_gui_host if portal_cors_origins is nil", function()
    local workspace = {
      config = {
        portal_gui_protocol = "http",
        portal_gui_host = "example.com",
      }
    }

    local origins = workspaces.build_ws_portal_cors_origins(workspace)
    assert.same({ "http://example.com" }, origins)
  end)

  it("should derive origin from subdoportal_gui_use_subdomains, portal_gui_protocol, and portal_gui_host if portal_cors_origins is nil", function()
    local workspace = {
      name = "wooo",
      config = {
        portal_gui_protocol = "http",
        portal_gui_host = "example.com",
        portal_gui_use_subdomains = true,
      }
    }

    local origins = workspaces.build_ws_portal_cors_origins(workspace)
    assert.same({ "http://wooo.example.com" }, origins)
  end)
end)

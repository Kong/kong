local utils = require "kong.tools.utils"
local tablex = require "pl.tablex"

local rat

local function assert_rw_allowed(tab, orig_t)
  for k, v in pairs(orig_t or {}) do
    -- reads from orig_t succeed
    local val = assert.has_no.errors(function() return tab[k] end)
    assert.equal(v, val)
  end

  local k = utils.random_string()
  local v = utils.random_string()
  -- writing new values succeeds
  assert.has_no.errors(function() tab[k] = v end)
  -- reading new values succeeds
  local val = assert.has_no.errors(function() return tab[k] end)
  assert.equal(v, val)
end

local function assert_rw_denied(tab, orig_t)
  local err_str = "race condition detected"
  for k, v in pairs(orig_t or {}) do
    -- reads from orig_t error out
    assert.error_matches(function() return nil, tab[k] == v end, err_str)
  end

  local k = utils.random_string()
  local v = utils.random_string()
  -- writing new values errors out
  assert.error_matches(function() tab[k] = v end, err_str)
  -- reading new values errors out
  assert.error_matches(function() return tab[k] == v end, err_str)
end

describe("Request aware table", function()
  local old_ngx
  local tab

  lazy_setup(function()
    old_ngx = ngx
    _G.ngx = {
      get_phase = function() return "access" end,
      var = {},
    }
    rat = require "kong.tools.request_aware_table"
  end)

  lazy_teardown(function()
    _G.ngx = old_ngx
  end)

  describe("with concurrency check enabled", function()
    local orig_t

    before_each(function()
      orig_t = {
        k1 = utils.random_string(),
        k2 = utils.random_string(),
      }
      tab = rat.new(orig_t, "on")
    end)

    it("allows access when there are no race conditions", function()
      -- create a new RAT with request_id = 1 (clear after use)
      _G.ngx.var.request_id = "1"
      assert_rw_allowed(tab, orig_t)
      tab.clear()

      -- reuse RAT with different request_id (allowed)
      _G.ngx.var.request_id = "2"
      assert_rw_allowed(tab)
    end)

    it("denies access when there are race conditions", function()
      -- create a new RAT with request_id = 1 (no clear)
      _G.ngx.var.request_id = "1"
      assert_rw_allowed(tab, orig_t)

      -- reuse RAT with different request_id (not allowed)
      _G.ngx.var.request_id = "2"
      assert_rw_denied(tab)
    end)

    it("clears the table successfully", function()
      -- create a new RAT with request_id = 1 (clear after use)
      _G.ngx.var.request_id = "1"
      assert_rw_allowed(tab, orig_t)
      tab.clear()

      assert.same(0, tablex.size(orig_t))
    end)

    it("allows defining a custom clear function", function()
      -- create a new RAT with request_id = 1 (clear after use)
      _G.ngx.var.request_id = "1"
      orig_t.persist = "persistent_value"
      assert_rw_allowed(tab, orig_t)

      -- custom clear function that keeps persistent_value
      tab.clear(function(t)
        for k in pairs(t) do
          if k ~= "persist" then
            t[k] = nil
          end
        end
      end)

      -- confirm persistent_value is the only key left
      assert.same(1, tablex.size(orig_t))
      assert.equal("persistent_value", tab.persist)

      -- clear the whole table and confirm it's empty
      tab.clear()
      assert.same(0, tablex.size(orig_t))
    end)
  end)

  describe("with concurrency check disabled", function()
    local orig_t

    before_each(function()
      orig_t = {
        k1 = utils.random_string(),
        k2 = utils.random_string(),
      }
      tab = rat.new(orig_t, "off")
    end)

    before_each(function()
      tab.clear()
    end)

    it("allows access when there are no race conditions", function()
      -- create a new RAT with request_id = 1 (clear after use)
      _G.ngx.var.request_id = "1"
      assert_rw_allowed(tab, orig_t)
      tab.clear()

      -- reuse RAT with different request_id (allowed)
      _G.ngx.var.request_id = "2"
      assert_rw_allowed(tab, orig_t)
    end)

    it("allows access when there are race conditions", function()
      -- create a new RAT with request_id = 1, (no clear)
      _G.ngx.var.request_id = "1"
      assert_rw_allowed(tab, orig_t)

      -- reuse RAT with different request_id (allowed with check disabled)
      _G.ngx.var.request_id = "2"
      assert_rw_allowed(tab, orig_t)
    end)
  end)
end)

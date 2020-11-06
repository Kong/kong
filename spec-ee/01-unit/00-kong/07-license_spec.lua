-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local lic_helper = require "kong.enterprise_edition.license_helpers"

local match = require 'luassert.match'
describe("licensing", function()
  before_each(function()
    stub(ngx, "log")
  end)

  after_each(function()
    ngx.log:revert() -- luacheck: ignore
  end)

  it("does not alert before 90 days from expiration date", function()
    lic_helper.log_license_state(os.time()+91*3600*24, os.time())
    assert.stub(ngx.log).was.called(0)
  end)

  it("does WARN from 90 days on from expiration date", function()
    lic_helper.log_license_state(os.time()+89*3600*24, os.time())
    assert.stub(ngx.log).was.called(1)
    assert.stub(ngx.log).was.called_with(ngx.WARN, match._)
  end)

  it("does ERR from 30 days on from expiration date", function()
    lic_helper.log_license_state(os.time()+29*3600*24, os.time())
    assert.stub(ngx.log).was.called(1)
    assert.stub(ngx.log).was.called_with(ngx.ERR, match._)
  end)

  it("does ERR from -1 days on from expiration date", function()
    lic_helper.log_license_state(os.time()-3600*24, os.time())
    assert.stub(ngx.log).was.called(1)
    assert.stub(ngx.log).was.called_with(ngx.CRIT, match._)
  end)
end)

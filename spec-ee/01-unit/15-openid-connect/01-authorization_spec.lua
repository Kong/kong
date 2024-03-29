-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local oic = require "kong.openid-connect"
local uri = require "kong.openid-connect.uri"


local function pushed_apushed_authorization_request_mock(self)
  return {
    client_id = self.oic.options.client_id,
    request_uri = "http://idp.test/authorize/identifier",
  }
end


describe("authorization", function ()
  describe("request", function ()
    it("it does not use proof key for code exchange by default", function ()
      local o = oic.new({
        client_id = "test",
        authorization_endpoint = "http://idp.test/authorize",
        redirect_uri = "http://example.test/",
        verify_parameters = false,
      })

      local args, err = o.authorization:request()

      assert.is_nil(err)
      assert.is_nil(args.code_verifier)
      assert.is_string(args.nonce)
      assert.is_string(args.state)
      assert.is_string(args.url)

      local url = uri.parse(args.url)

      assert.equal("http", url.scheme)
      assert.equal("idp.test", url.host)
      assert.equal("/authorize", url.path)
      assert.equal("http://example.test/", url.args.redirect_uri)
      assert.equal("code", url.args.response_type)
      assert.equal("test", url.args.client_id)
      assert.equal(args.state, url.args.state)
      assert.equal(args.nonce, url.args.nonce)
      assert.is_nil(url.args.code_challenge)
      assert.is_nil(url.args.code_challenge_method)
    end)
    it("it does not use proof key for code exchange when asked not to use it", function ()
      local o = oic.new({
        client_id = "test",
        authorization_endpoint = "http://idp.test/authorize",
        redirect_uri = "http://example.test/",
        verify_parameters = false,
        require_proof_key_for_code_exchange = false,
      })

      local args, err = o.authorization:request()

      assert.is_nil(err)
      assert.is_nil(args.code_verifier)
      assert.is_string(args.nonce)
      assert.is_string(args.state)
      assert.is_string(args.url)

      local url = uri.parse(args.url)

      assert.equal("http", url.scheme)
      assert.equal("idp.test", url.host)
      assert.equal("/authorize", url.path)
      assert.equal("http://example.test/", url.args.redirect_uri)
      assert.equal("code", url.args.response_type)
      assert.equal("test", url.args.client_id)
      assert.equal(args.state, url.args.state)
      assert.equal(args.nonce, url.args.nonce)
      assert.is_nil(url.args.code_challenge)
      assert.is_nil(url.args.code_challenge_method)
    end)
    it("it does use proof key for code exchange when asked", function ()
      local o = oic.new({
        client_id = "test",
        authorization_endpoint = "http://idp.test/authorize",
        redirect_uri = "http://example.test/",
        verify_parameters = false,
        require_proof_key_for_code_exchange = true,
      })

      local args, err = o.authorization:request()

      assert.is_nil(err)
      assert.is_string(args.code_verifier)
      assert.is_string(args.nonce)
      assert.is_string(args.state)
      assert.is_string(args.url)

      local url = uri.parse(args.url)

      assert.equal("http", url.scheme)
      assert.equal("idp.test", url.host)
      assert.equal("/authorize", url.path)
      assert.equal("http://example.test/", url.args.redirect_uri)
      assert.equal("code", url.args.response_type)
      assert.equal("test", url.args.client_id)
      assert.equal(args.state, url.args.state)
      assert.equal(args.nonce, url.args.nonce)
      assert.is_string(url.args.code_challenge)
      assert.is_string(url.args.code_challenge_method)
    end)
    it("it does use proof key for code exchange when metadata tells it is possible / required", function ()
      local o = oic.new({
        client_id = "test",
        authorization_endpoint = "http://idp.test/authorize",
        redirect_uri = "http://example.test/",
        verify_parameters = false,
      }, {
        code_challenge_methods_supported = {
          "plain",
          "S256"
        },
      })

      local args, err = o.authorization:request()

      assert.is_nil(err)
      assert.is_string(args.code_verifier)
      assert.is_string(args.nonce)
      assert.is_string(args.state)
      assert.is_string(args.url)

      local url = uri.parse(args.url)

      assert.equal("http", url.scheme)
      assert.equal("idp.test", url.host)
      assert.equal("/authorize", url.path)
      assert.equal("http://example.test/", url.args.redirect_uri)
      assert.equal("code", url.args.response_type)
      assert.equal("test", url.args.client_id)
      assert.equal(args.state, url.args.state)
      assert.equal(args.nonce, url.args.nonce)
      assert.is_string(url.args.code_challenge)
      assert.is_string(url.args.code_challenge_method)

      o = oic.new({
        client_id = "test",
        authorization_endpoint = "http://idp.test/authorize",
        redirect_uri = "http://example.test/",
        verify_parameters = false,
      }, {
        require_proof_key_for_code_exchange = true,
      })

      args, err = o.authorization:request()

      assert.is_nil(err)
      assert.is_string(args.code_verifier)
      assert.is_string(args.nonce)
      assert.is_string(args.state)
      assert.is_string(args.url)

      url = uri.parse(args.url)

      assert.equal("http", url.scheme)
      assert.equal("idp.test", url.host)
      assert.equal("/authorize", url.path)
      assert.equal("http://example.test/", url.args.redirect_uri)
      assert.equal("code", url.args.response_type)
      assert.equal("test", url.args.client_id)
      assert.equal(args.state, url.args.state)
      assert.equal(args.nonce, url.args.nonce)
      assert.is_string(url.args.code_challenge)
      assert.is_string(url.args.code_challenge_method)
    end)
    it("it does not use pushed authorization request by default", function ()
      local o = oic.new({
        client_id = "test",
        authorization_endpoint = "http://idp.test/authorize",
        redirect_uri = "http://example.test/",
        verify_parameters = false,
      })

      o.authorization.pushed_authorization_request = pushed_apushed_authorization_request_mock

      local args, err = o.authorization:request()

      assert.is_nil(err)
      assert.is_string(args.nonce)
      assert.is_string(args.state)
      assert.is_string(args.url)

      local url = uri.parse(args.url)

      assert.equal("http", url.scheme)
      assert.equal("idp.test", url.host)
      assert.equal("/authorize", url.path)
      assert.equal("http://example.test/", url.args.redirect_uri)
      assert.equal("code", url.args.response_type)
      assert.equal("test", url.args.client_id)
      assert.equal(args.state, url.args.state)
      assert.equal(args.nonce, url.args.nonce)

      assert.is_nil(url.args.request_uri)
    end)
    it("it does not use pushed authorization request when asked not to use it", function ()
      local o = oic.new({
        client_id = "test",
        authorization_endpoint = "http://idp.test/authorize",
        redirect_uri = "http://example.test/",
        verify_parameters = false,
        require_pushed_authorization_requests = false,
      })

      o.authorization.pushed_authorization_request = pushed_apushed_authorization_request_mock

      local args, err = o.authorization:request()

      assert.is_nil(err)
      assert.is_string(args.nonce)
      assert.is_string(args.state)
      assert.is_string(args.url)

      local url = uri.parse(args.url)

      assert.equal("http", url.scheme)
      assert.equal("idp.test", url.host)
      assert.equal("/authorize", url.path)
      assert.equal("http://example.test/", url.args.redirect_uri)
      assert.equal("code", url.args.response_type)
      assert.equal("test", url.args.client_id)
      assert.equal(args.state, url.args.state)
      assert.equal(args.nonce, url.args.nonce)

      assert.is_nil(url.args.request_uri)
    end)
    it("it does use pushed authorization request when asked", function ()
      local o = oic.new({
        client_id = "test",
        authorization_endpoint = "http://idp.test/authorize",
        redirect_uri = "http://example.test/",
        verify_parameters = false,
        require_pushed_authorization_requests = true,
      })

      o.authorization.pushed_authorization_request = pushed_apushed_authorization_request_mock

      local args, err = o.authorization:request()

      assert.is_nil(err)
      assert.is_string(args.nonce)
      assert.is_string(args.state)
      assert.is_string(args.url)

      local url = uri.parse(args.url)

      assert.equal("http", url.scheme)
      assert.equal("idp.test", url.host)
      assert.equal("/authorize", url.path)
      assert.is_nil(url.args.redirect_uri)
      assert.is_nil(url.args.response_type)
      assert.equal("test", url.args.client_id)
      assert.is_nil(url.args.state)
      assert.is_nil(url.args.nonce)

      assert.equal("http://idp.test/authorize/identifier", url.args.request_uri)
    end)
    it("it does use pushed authorization request when metadata requires it", function ()
      local o = oic.new({
        client_id = "test",
        authorization_endpoint = "http://idp.test/authorize",
        redirect_uri = "http://example.test/",
        verify_parameters = false,
      }, {
        require_pushed_authorization_requests = true,
      })

      o.authorization.pushed_authorization_request = pushed_apushed_authorization_request_mock

      local args, err = o.authorization:request()

      assert.is_nil(err)
      assert.is_string(args.nonce)
      assert.is_string(args.state)
      assert.is_string(args.url)

      local url = uri.parse(args.url)

      assert.equal("http", url.scheme)
      assert.equal("idp.test", url.host)
      assert.equal("/authorize", url.path)
      assert.is_nil(url.args.redirect_uri)
      assert.is_nil(url.args.response_type)
      assert.equal("test", url.args.client_id)
      assert.is_nil(url.args.state)
      assert.is_nil(url.args.nonce)

      assert.equal("http://idp.test/authorize/identifier", url.args.request_uri)
    end)
  end)
end)

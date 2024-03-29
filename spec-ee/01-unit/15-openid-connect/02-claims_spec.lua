-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local claims = require "kong.openid-connect.claims"
local oic = require "kong.openid-connect"
local jwks = require "kong.openid-connect.jwks"

describe("claimshandler. fetches distributed claims", function ()
    local t_jwks = jwks.new()

    it("fetches distributed claims. success", function ()
      -- create stub for oic:userinfo
      local return_value = {payment_info={credit_card="cc_num"}}
      stub(oic, "userinfo").returns(return_value, nil)
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local id_token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          _claim_names = {
            payment_info = "src1",
          },
          _claim_sources = {
            src1 = {
              endpoint = "http://httpbin.org/json",
              access_token = "xxxx"
            },
          }
        }
      }

      -- do not pass internal access_token since id_token's claim_sources has one
      local claimshandler = claims.new(id_token, nil, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_truthy(ok)
      assert.is_nil(err)
      assert.is_nil(id_token.payload._claim_names)
      assert.is_nil(id_token.payload._claim_sources)
      assert.is_same(id_token.payload.payment_info, {credit_card="cc_num"})
    end)

    it("claimsendpoint does not contain claim", function ()
      -- create stub for oic:userinfo
      local return_value = {payment_info={empty="example_value"}}
      stub(oic, "userinfo").returns(return_value, nil)
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          _claim_names = {
            shipping_info = "src2",
          },
          _claim_sources = {
            src2 = {
              endpoint = "http://httpbin.org/json",
              access_token = "xxxx"
            },
          }
        }
      }

      -- do not pass internal access_token since id_token's claim_sources has one
      local claimshandler = claims.new(token, nil, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_falsy(ok)
      assert.is_equal("Could not find claim <shipping_info> in endpoint return", err)
    end)

   it("claim already exists", function ()
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      stub(oic, "userinfo").returns({}, nil)
      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          shipping_info = "foo",
          _claim_names = {
            shipping_info = "src2",
          },
          _claim_sources = {
            src2 = {
              endpoint = "http://httpbin.org/json",
              access_token = "xxxx"
            },
          }
        }
      }

      -- decode (fetching distributed claims)
      local claimshandler = claims.new(token, nil, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_nil(ok)
      assert.is_equal("Requested claim <shipping_info> already exists in \
                          the payload. Retrieving it would overwrite \
                          the existing one.", err)
    end)

    it("no distributed claims are present", function ()
      -- create stub for oic:userinfo
      local return_value = {payment_info={empty="example_value"}}
      stub(oic, "userinfo").returns(return_value, nil)
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
        }
      }

      -- decode (fetching distributed claims)
      local claimshandler = claims.new(token, nil, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_not_nil(ok)
      assert.is_nil(err)
    end)

    it("distributed claims_names are present but no claim_sources", function ()
      -- create stub for oic:userinfo
      local return_value = {payment_info={empty="example_value"}}
      stub(oic, "userinfo").returns(return_value, nil)
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          shipping_info = "foo",
          _claim_names = {
            shipping_info = "src2",
          },
        }
      }

      local claimshandler = claims.new(token, nil, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_nil(ok)
      assert.is_equal("Found _claim_names but no _claim_sources in payload.", err)
    end)

    it("claims_names is not a table", function ()
      -- create stub for oic:userinfo
      local return_value = {payment_info={empty="example_value"}}
      stub(oic, "userinfo").returns(return_value, nil)
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          shipping_info = "foo",
          _claim_names = "src1"
        }
      }

      local claimshandler = claims.new(token, nil, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_nil(ok)
      assert.is_equal("_claim_names must be of type table", err)
    end)

    it("no endpoint attribute", function ()
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      stub(oic, "userinfo").returns({}, nil)
      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          _claim_names = {
            shipping_info = "src2",
          },
          _claim_sources = {
            src2 = {
              access_token = "xxxx"
            },
          }
        }
      }

      local claimshandler = claims.new(token, nil, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_nil(ok)
      assert.is_equal("Could not find endpoint", err)
    end)

    it("no access_token", function ()
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      stub(oic, "userinfo").returns({}, nil)
      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          _claim_names = {
            shipping_info = "src2",
          },
          _claim_sources = {
            src2 = {
              endpoint = "http://httpbin.org/json",
            },
          }
        }
      }

      local claimshandler = claims.new(token, nil, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_nil(ok)
      assert.is_equal("Contacting a userinfo_endpoint without an access_token is currently not supported", err)
    end)

    it("no access_token provided, falling back to access token of parent request", function ()
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      local return_value = {shipping_info={foo="example_value"}}
      stub(oic, "userinfo").returns(return_value, nil)
      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          _claim_names = {
            shipping_info = "src2",
          },
          _claim_sources = {
            src2 = {
              endpoint = "http://httpbin.org/json",
              -- no access_token is provided but we use the one from the parent request
            },
          }
        }
      }
      local access_token = "MTQ0NjJkZmQ5OTM2NDE1ZTZjNGZmZjI3"

      local claimshandler = claims.new(token, access_token, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_truthy(ok)
      assert.is_nil(err)
      assert.is_nil(token.payload._claim_names)
      assert.is_nil(token.payload._claim_sources)
    end)

  it("no access_token provided, falling back to access token of parent request. the endpoint returns a bad response", function ()
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      stub(oic, "userinfo").returns(nil, "unauthorized")
      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          _claim_names = {
            shipping_info = "src2",
          },
          _claim_sources = {
            src2 = {
              endpoint = "http://httpbin.org/json",
              -- no access_token is provided but we use the one from the parent request
            },
          }
        }
      }
      local access_token = "MTQ0NjJkZmQ5OTM2NDE1ZTZjNGZmZjI3"

      local claimshandler = claims.new(token, access_token, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_falsy(ok)
      assert.is_not_nil(err)
      assert.is_not_nil(token.payload._claim_names)
      assert.is_not_nil(token.payload._claim_sources)
      assert.same(err, "unauthorized")

    end)

    it("multiple claims with the same endpoint", function ()
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      local return_value = {payment_info={credit_card="cc_num"}, shipping_info={address="xyz_addr"}}
      stub(oic, "userinfo").returns(return_value, nil)

      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          _claim_names = {
            shipping_info = "src2",
            payment_info = "src2",
          },
          _claim_sources = {
            src2 = {
              endpoint = "http://httpbin.org/json",
              access_token = "xxxx"
            },
          }
        }
      }

      local claimshandler = claims.new(token, nil, _oic)
      local _, err = claimshandler:resolve_distributed_claims()
      assert.is_not_nil(token)
      assert.is_nil(token.payload._claim_names)
      assert.is_nil(token.payload._claim_sources)
      assert.is_same(token.payload.payment_info, {credit_card="cc_num"})
      assert.is_same(token.payload.shipping_info, {address="xyz_addr"})
      assert.is_nil(err)
    end)

    it("multiple claims with the a different endpoint", function ()
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      local return_value = {payment_info={credit_card="cc_num"}, shipping_info={address="xyz_addr"}}
      stub(oic, "userinfo").returns(return_value, nil)

      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          _claim_names = {
            shipping_info = "src2",
            payment_info = "src1",
          },
          _claim_sources = {
            src2 = {
              endpoint = "http://httpbin.org/json",
              access_token = "xxxx"
            },
            src1 = {
              endpoint = "http://httpbin.org/json",
              access_token = "xxxx"
            },
          }
        }
      }

      local claimshandler = claims.new(token, nil, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_truthy(ok)
      assert.is_not_nil(token)
      assert.is_nil(token.payload._claim_names)
      assert.is_nil(token.payload._claim_sources)
      assert.is_same(token.payload.payment_info, {credit_card="cc_num"})
      assert.is_same(token.payload.shipping_info, {address="xyz_addr"})
      assert.is_nil(err)
    end)

    it("multiple claims with but one claim_source is not found", function ()
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      local return_value = {payment_info={credit_card="cc_num"}}
      stub(oic, "userinfo").returns(return_value, nil)

      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          _claim_names = {
            shipping_info = "src2",
            payment_info = "src1",
          },
          _claim_sources = {
            src1 = {
              endpoint = "http://httpbin.org/json",
              access_token = "xxxx"
            },
          }
        }
      }

      local claimshandler = claims.new(token, nil, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_falsy(ok)
      assert.is_same("Could not find reference for shipping_info", err)
    end)
end)

describe("claimshandler tests for AzureAD", function ()
    -- AzureAD docs: https://docs.microsoft.com/en-us/graph/api/directoryobject-getmembergroups?view=graph-rest-1.0&tabs=http
    -- spec: https://openid.net/specs/openid-connect-core-1_0.html#AggregatedDistributedClaims

    -- azureAD does not return spec conformant data structures. The specification's examples suggests that the
    -- received payload should have keys that match the key in `claim_names`.
    -- AzureAD returns
    -- {
    -- "@odata.context": "https://graph.microsoft.com/v1.0/$metadata#Collection(Edm.String)",
    -- "value": [1,2,3]
    -- }

    local t_jwks = jwks.new()

    it("fetches distributed claims -> [getmembergroups] single_claim_name", function ()
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      local return_value = {["@odata.context"]={"https://url.to.graphdb.com"}, value={"group1", "group2", "group3"}}
      stub(oic, "userinfo").returns(return_value, nil)

      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          _claim_names = {
            groups = "src1",
          },
          _claim_sources = {
            src1 = {
              endpoint = "https://graph.windows.net/xxxxxx/users/xxxx/getmembergroups",
              access_token = "xxxx"
            },
          }
        }
      }
      local claimshandler = claims.new(token, nil, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_truthy(ok)
      assert.is_not_nil(token)
      assert.is_nil(token.payload._claim_names)
      assert.is_nil(token.payload._claim_sources)
      assert.is_same({"group1", "group2", "group3"}, token.payload.groups)
      assert.is_nil(err)
    end)

    it("fetches distributed claims -> [getmembergroups] multiple_claim_name", function ()
      -- create oic instance with assigned keys
      local _oic = oic.new({}, {}, t_jwks.keys)
      local return_value = {["@odata.context"]={"https://url.to.graphdb.com"}, value={"group1", "group2", "group3"}}
      stub(oic, "userinfo").returns(return_value, nil)

      -- pick a HS256 jwk
      local jwk = _oic.keys["HS256"]
      -- assemble token scaffold
      local token = {
        jwk = jwk,
        payload = {
          email = "foo@bar.com",
          _claim_names = {
            groups = "src1",
            whatever = "src1",
          },
          _claim_sources = {
            src1 = {
              endpoint = "https://graph.windows.net/xxxxxx/users/xxxx/getmembergroups",
              access_token = "xxxx"
            },
          }
        }
      }
      local claimshandler = claims.new(token, nil, _oic)
      local ok, err = claimshandler:resolve_distributed_claims()
      assert.is_falsy(ok)
      assert.is_not_nil(token)
      assert.is_not_nil(token.payload._claim_names)
      assert.is_not_nil(token.payload._claim_sources)
      assert.is_same("Found <value> in response but could not decide which claim_name to assign it to.", err)
    end)
end)

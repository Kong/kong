-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local crypt  = require "kong.plugins.saml.utils.crypt"

local PLUGIN_NAME = "saml"


describe(PLUGIN_NAME .. " -> AuthnRequest creation", function()
    local CLEARTEXT = "Jennie, a sealyham terrier, lives a comfortable life. However, she feels that she lacks something and sets out on an adventure in the middle of the night that will change her life drastically."
    it("can decrypt what it encrypts", function()
        local key = crypt.generate_key()
        local cipher = crypt.encrypt(CLEARTEXT, key)
        assert.matches("^[a-zA-Z0-9/=+]+$", cipher)
        local decrypted = crypt.decrypt(cipher, key)
        assert.equals(CLEARTEXT, decrypted)
    end)
end)

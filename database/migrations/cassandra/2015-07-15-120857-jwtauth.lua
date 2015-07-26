local Migration = {
  name = "2015-07-15-120857-jwtauth",

  up = function(options)
    return [[
     ALTER TABLE jwtauth_credentials ADD secret_is_base64_encoded boolean;
    ]]
  end,

  down = function(options)
    return [[
      ALTER TABLE jwtauth_credentials DROP secret_is_base64_encoded;
    ]]
  end
}

return Migration

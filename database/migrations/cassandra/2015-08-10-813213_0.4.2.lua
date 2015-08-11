local Migration = {
  name = "2015-08-10-813213_0.4.2",

  up = function(options)
    return [[
      ALTER TABLE apis ADD preserve_host boolean;
    ]]
  end,

  down = function(options)
    return [[
      ALTER TABLE apis DROP preserve_host;
    ]]
  end
}

return Migration

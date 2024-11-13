local cjson_decode = require("cjson").decode


return {
  _stream = function(data)
    local json = cjson_decode(data)
    local action = json.action or "echo"

    if action == "echo" then
      return json.payload, json.err

    elseif action == "rep" then
      return string.rep("1", json.rep or 0)

    elseif action == "throw" then
      error(json.err or "error!")
    end
  end,
}

local _M = {}

local ANSWERS = {
  y = true,
  Y = true,
  yes = true,
  YES = true,
  n = false,
  N = false,
  no = false,
  NO = false
}

function _M.confirm(question)
  local answer
  repeat
    io.write(question.." [Y/n] ")
    answer = ANSWERS[io.read("*l")]
  until answer ~= nil

  return answer
end

return _M

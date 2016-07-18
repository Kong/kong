local ErrorCode = {
  ['99100001'] = '参数%s不允许为NULL',
  ['99100002'] = '参数%s不允许为空',
  ['99100003'] = '参数%s格式不符合%s',
  ['99100004'] = '参数%s超过最大长度%s',
  ['99100005'] = '参数%s不足最小长度%s',
  ['99100006'] = '参数%s大于最大值%s',
  ['99100007'] = '参数%s小于最小值%s',
  ['99100008'] = '参数%s邮件地址不合法',
  ['99100009'] = '参数%s手机号不合法',
  ['99100010'] = '参数%sURL格式不合法',
  ['99100011'] = '参数%s不是有效的整数',
  ['99100012'] = '参数%s不是有效的数字',
  ['99100013'] = '参数%s不是有效的货币',
  ['99001007'] = '应用(%s)参数无效，格式不对、非法值、越界等'
}

local Response = {
  state = nil,
  result = nil,
  ts = os.time() * 1000,
  sign = nil,
  error = nil,
  stringResult = nil,
  format = "json",
  validSign = nil,
  error = nil
}

function Response:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function Response:success() self.state = "SUCCESS" return self end

function Response:fail() self.state = "FAILURE" return self end

function Response:format(format) self.format = format return self end

function Response:error(code, message) self.error = { code = code, message = message, subErrors = {} } return self end

function Response:requestValidatorError(appKey) self.error = { code = '99001007', message = string.format(ErrorCode['99001007'], appKey), subErrors = {} } return self end

function Response:appendSubError(code, a, b) table.insert(self.error.subErrors, { code = code, message = string.format(ErrorCode[code], a, b) }) return self end

return function() return Response, ErrorCode end

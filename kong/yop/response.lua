local responses = require "kong.tools.responses"

local ErrorCode = {
  ['99001001'] = '应用(%s)无效或不存在,请确认appKey正确且应用状态正常',
  ['99001002'] = '服务(%s)无效或不存在,请根据API文档确认服务地址及版本是否正确',
  ['99001003'] = '服务(%s)不可用,服务暂时禁用或已下线，请关注API平台公告',
  ['99001004'] = '应用(%s)权限不够、非法访问,请确保已开通此API权限',
  ['99001005'] = '应用(%s)不允许的HTTP方法:%s',
  ['99001006'] = '应用(%s)缺少必要的参数:%s',
  ['99001007'] = '应用(%s)参数无效，格式不对、非法值、越界等',
  ['99001008'] = '应用(%s)签名无效',
  ['99001009'] = '应用(%s)报文解密失败',
  ['99001010'] = '应用(%s)编码错误,请使用UTF-8对请求参数值进行编码',
  ['99001011'] = '应用(%s)业务异常',
  ['99001012'] = '应用(%s)会话无效或已过期',
  ['99001013'] = '应用(%s)调用超过最大处理时长%s毫秒',
  ['99001014'] = '应用(%s)调用次数超限',
  ['99001015'] = '应用(%s)调用并发数超限',
  ['99001016'] = '应用(%s)调用频次超限',
  ['99001017'] = '应用(%s)应用余量不足',
  ['99001018'] = '应用(%s)文件上传失败，原因:%s',
  ['99001019'] = '应用(%s)文件格式不对，正确格式为：<文件格式>@<文件内容>',
  ['99001020'] = '应用(%s)报文加解密异常',
  ['99001021'] = '应用(%s)非白名单IP，当前IP:%s',
  ['99999000'] = '应用(%s)系统异常，请稍后重试',
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
  state = "SUCCESS",
  result = nil,
  ts = nil,
  sign = nil,
  error = nil,
  stringResult = nil,
  format = "json",
  validSign = nil
}

function Response:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  o.ts = os.time() * 1000
  return o
end

function Response:success() self.state = "SUCCESS" return self end

function Response:fail() self.state = "FAILURE" return self end

function Response:formats(format) self.format = format return self end

function Response:errors(code, p1, p2, p3) self.error = { code = code, message = string.format(ErrorCode[code], p1, p2, p3) } return self end

function Response:requestValidatorError(appKey) self.error = { code = '99001007', message = string.format(ErrorCode['99001007'], appKey), subErrors = {} } return self end

function Response:appendSubError(code, a, b) table.insert(self.error.subErrors, { code = code, message = string.format(ErrorCode[code], a, b) }) return self end

local function sendValidateError(appKey, code, a, b)
  responses.send(200, Response:new():fail():requestValidatorError(appKey):appendSubError(code, a, b))
end

function Response.validateNullException(p) sendValidateError(p.app, "99100001", p.name) end

function Response.validateBlankException(p) sendValidateError(p.app, "99100002", p.name) end

function Response.validateEmailException(p) sendValidateError(p.app, "99100008", p.name) end

function Response.validateMobileException(p) sendValidateError(p.app, "99100009", p.name) end

function Response.validateLengthMoreException(p, rule) sendValidateError(p.app, "99100004", p.name, rule.max) end

function Response.validateLengthLessException(p, rule) sendValidateError(p.app, "99100005", p.name, rule.min) end

function Response.validateRangeMoreException(p, rule) sendValidateError(p.app, "99100006", p.name, rule.max) end

function Response.validateRangeLessException(p, rule) sendValidateError(p.app, "99100007", p.name, rule.min) end

function Response.validateIntException(p) sendValidateError(p.app, "99100011", p.name) end

function Response.validatePatternException(p, rule) sendValidateError(p.app, "99100003", p.name, rule) end

function Response.apiNotExistException(apiUri) responses.send(200, Response:new():fail():errors("99001002", apiUri)) end

function Response.apiUnavailableException(apiUri) responses.send(200, Response:new():fail():errors("99001003", apiUri)) end

function Response.appUnavailableException(appKey) responses.send(200, Response:new():fail():errors("99001001", appKey)) end

function Response.missParameterException(appKey, requiredParameter) responses.send(200, Response:new():fail():errors("99001006", appKey, requiredParameter)) end

function Response.notAllowdHttpMethodException(appKey, method) responses.send(200, Response:new():fail():errors("99001005", appKey, method)) end

function Response.notAllowdIpException(appKey, ip) responses.send(200, Response:new():fail():errors("99001021", appKey, ip)) end

function Response.permessionDeniedException(appKey) responses.send(200, Response:new():fail():errors("99001004", appKey)) end

function Response.signException(appKey) responses.send(200, Response:new():fail():errors("99001008", appKey)) end

function Response.decryptException(appKey) responses.send(200, Response:new():fail():errors("99001009", appKey)) end



return function() return Response, ErrorCode end

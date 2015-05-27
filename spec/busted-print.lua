local ansicolors = require 'ansicolors'

return function(options)
  local handler = require 'busted.outputHandlers.utfTerminal'(options)

  handler.fileStart = function(file)
    io.write('\n' .. ansicolors('%{cyan}' .. file.name) .. ':')
  end

  handler.testStart = function(element, parent, status, debug)
    io.write('\n  ' .. handler.getFullName(element) .. ' ... ')
    io.flush()
  end

  local busted = require 'busted'

  busted.subscribe({ 'file', 'start' }, handler.fileStart)
  busted.subscribe({ 'test', 'start' }, handler.testStart)

  return handler
end

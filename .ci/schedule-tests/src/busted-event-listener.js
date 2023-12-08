const fs = require('node:fs/promises')
const net = require('net')
const readline = require('readline')

const bustedEventListener = async (unixSocketPath, handler) => {
  // Remove the socket if it exists
  try {
    await fs.unlink(unixSocketPath)
  } catch (_) {
    // ignore
  }

  const server = net.createServer((stream) => {
    const rl = readline.createInterface({
      input: stream,
      crlfDelay: Infinity, // Treat CR LF as a single newline
    })

    rl.on('line', (line) => {
      handler(JSON.parse(line))
    })
  })

  server.listen(unixSocketPath)

  return server
}

module.exports = bustedEventListener

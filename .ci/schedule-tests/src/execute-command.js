const { spawn } = require('child_process')

const executeCommand = async (command, env) => {
  const childProcess = spawn(command, [], { env, shell: true })

  let output = ''

  const handleOutput = (data) => {
    const text = data.toString()
    process.stdout.write(text)
    output += text
  }
  childProcess.stdout.on('data', handleOutput)
  childProcess.stderr.on('data', handleOutput)

  return new Promise((resolve, reject) => {
    childProcess.on('close', (exitStatus) => {
      resolve({ exitStatus, output })
    })

    childProcess.on('error', (err) => {
      reject({ existStatus: 'error', output: `${err}` })
    })
  })
}

module.exports = executeCommand

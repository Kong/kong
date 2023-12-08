const fs = require('fs')
const ms = require('ms')
const { AsciiTable3, AlignmentEnum } = require('ascii-table3')

const executeCommand = require('./execute-command')
const appendToFile = require('./append-to-file')
const bustedEventListener = require('./busted-event-listener')

const readTestsToRun = (testsToRunFile, failedTestFilesFile) => {
  file = testsToRunFile
  if (fs.existsSync(failedTestFilesFile)) {
    console.log(`Rerunning failed tests from ${failedTestFilesFile}`)
    file = failedTestFilesFile
  } else {
    console.log(`Running tests from ${testsToRunFile}`)
  }

  return fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).map(JSON.parse)
}

const testRunner = async (
  pullRequest,
  workflowId,
  runAttempt,
  runnerNumber,
  testsToRunFile,
  failedTestFilesFile,
  testFileRuntimeFile
) => {
  const testsToRun = readTestsToRun(testsToRunFile, failedTestFilesFile)
  console.log(`Running ${testsToRun.length} tests`)

  const saveTestResult = async (test, exitStatus, output) => {
    if (pullRequest) {
      // Implement saving test result for pull request
      // You can use relevant Node.js GitHub API libraries for this
      // Example: octokit.issues.createComment({...});
    }
  }

  const bustedEventPath = `/tmp/busted-runner-${runnerNumber}`

  const bustedToDatadogStatus = {
    success: 'pass',
    error: 'error',
    failure: 'fail',
  }

  const runtimes = []

  const runTest = async (test) => {
    const { suite, exclude_tags, environment, filename } = test
    const listener = await bustedEventListener(bustedEventPath, ({ event, args }) => {
      switch (event) {
        case 'file:end':
          const { duration } = args[0]
          appendToFile(testFileRuntimeFile, `${suite}\t${filename}\t${duration}`)
          runtimes.push({ suite, filename, estimated: test.duration * 1000, elapsed: duration * 1000 })
      }
    })

    try {
      const excludeTagsOption = exclude_tags ? `--exclude-tags="${exclude_tags}"` : ''
      const command = `bin/busted --helper=spec/busted-ci-helper.lua -o gtest --Xoutput --color ${excludeTagsOption} "${filename}"`
      console.log(`### running ${command}`)
      const { exitStatus, output } = await executeCommand(command, {
        ...process.env,
        ...environment,
        BUSTED_EVENT_PATH: bustedEventPath,
      })
      // fixme do we want to wait until the suite:end event?  It seems to me that as the busted process has exited when
      // we reach this point, there should be no buffered data left.

      await saveTestResult(test, exitStatus, output)

      if (exitStatus !== 0) {
        console.log(`\nTest failed with exit status: ${exitStatus} ($output)`)
        return false
      }

      return true
    } catch (error) {
      console.log(error.message)
      return false
    } finally {
      listener.close()
    }
  }

  const failedTests = []
  for (let i = 0; i < testsToRun.length; i++) {
    console.log(`\n### Running file #${i + 1} of ${testsToRun.length}\n`)
    if (!(await runTest(testsToRun[i]))) {
      failedTests.push(testsToRun[i])
    }
  }

  let total = runtimes.reduce(
    (total, test) => {
      const { suite, filename, estimated, elapsed } = test
      total.estimated += estimated
      total.elapsed += elapsed
      if (Math.abs(estimated - elapsed) > 10000) {
        total.deviations.push(test)
      }
      return total
    },
    { estimated: 0, elapsed: 0, deviations: [] }
  )
  console.log(`
### Runtime analysis

Estimated total runtime: ${ms(Math.floor(total.estimated))}
Actual total runtime...: ${ms(Math.floor(total.elapsed))}
Total deviation........: ${ms(Math.floor(total.elapsed - total.estimated))}\n`)

  if (total.deviations.length) {
    console.log(
      new AsciiTable3('Deviating test files')
        .setHeading('Suite', 'File', 'Estimated', 'Actual', 'Deviation')
        .setAligns([
          AlignmentEnum.LEFT,
          AlignmentEnum.LEFT,
          AlignmentEnum.RIGHT,
          AlignmentEnum.RIGHT,
          AlignmentEnum.RIGHT,
        ])
        .addRowMatrix(
          total.deviations.map(({ suite, filename, estimated, elapsed }) => [
            suite,
            filename,
            ms(Math.floor(estimated)),
            ms(Math.floor(elapsed)),
            ms(Math.floor(elapsed - estimated)),
          ])
        )
        .toString()
    )
  }

  if (failedTests.length > 0) {
    console.log(`\n${failedTests.length} test files failed:\n`)
    console.log(failedTests.map(({ suite, filename }) => `\t${suite}\t${filename}`).join('\n'))
    console.log('')
    fs.writeFileSync(failedTestFilesFile, failedTests.map(JSON.stringify).join('\n'))
    process.exit(1)
  }

  process.exit(0)
}

module.exports = testRunner

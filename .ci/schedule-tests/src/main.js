const commander = require('commander')
const path = require('node:path')
const findGitRoot = require('find-git-root')
const schedule = require('./schedule')
const downloadStatistics = require('./download-statistics')
const combineStatistics = require('./combine-statistics')
const testRunner = require('./test-runner')
const repoRoot = () => path.join(findGitRoot(), '..')

const parseIntegerArgument = (value) => {
  // parseInt takes a string and a radix
  const parsedValue = parseInt(value, 10)
  if (isNaN(parsedValue)) {
    throw new commander.InvalidArgumentError('Not a number.')
  }
  return parsedValue
}

const cli = () => {
  commander.program
    .command('schedule')
    .description(
      'create test task files based on a test suite definition and historic runtime data'
    )
    .argument('<suite-definitions>', 'JSON file with suite definitions')
    .argument('<runtime-data>', 'text file with historic runtime data')
    .argument('<output-prefix>', 'filename prefix for generated task files')
    .argument(
      '<worker-count>',
      'number of test worker processes to schedule for',
      parseIntegerArgument
    )
    .action(
      (suiteDefinitionFile, runtimeDataFile, outputPrefix, workerCount) => {
        schedule(
          suiteDefinitionFile,
          runtimeDataFile,
          repoRoot(),
          outputPrefix,
          workerCount
        )
      }
    )

  commander.program
    .command('download-statistics')
    .argument('<owner>', 'repository owner')
    .argument('<repo>', 'repository name')
    .argument('<workflow-name>', 'workflow (file) name')
    .argument('<directory>', 'local directory to download the files to')
    .action(downloadStatistics)

  commander.program
    .command('combine-statistics')
    .argument(
      '<directory>',
      'local directory containing the downloaded statistics'
    )
    .argument(
      '<output-filename>',
      'name of the combined statistics file to write'
    )
    .action(combineStatistics)

  commander.program
    .command('test-runner')
    .argument('<prNumber>', 'Pull request number')
    .argument('<workflowId>', 'Workflow ID')
    .argument('<runAttempt>', 'Run attempt')
    .argument('<runnerNumber>', 'Runner number')
    .argument('<testsToRunFile>', 'Tests to run file')
    .argument('<failedTestFilesFile>', 'Failed test files file')
    .argument('<testFileRuntimeFile>', 'File to write runtime statistics to')
    .action(testRunner)

  commander.program
    .command('help')
    .description('Display help')
    .action(() => {
      commander.program.outputHelp()
    })

  commander.program.parse(process.argv)

  // Display help if no sub-command is provided
  if (!process.argv.slice(2).length) {
    commander.program.outputHelp()
  }
}

cli()

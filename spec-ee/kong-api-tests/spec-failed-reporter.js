/* eslint-disable @typescript-eslint/no-var-requires */
const { execSync } = require('child_process');
const { Spec } = require('mocha/lib/reporters');
const fs = require('fs');
const path = require('path');
const { isCI } = require('./support/config/environment');

const fileName = 'failed-tests.txt';
const reportFile = path.resolve(process.cwd(), fileName);
const failedSpecs = [];

/**
 * Extending Mocha's custom spec reporter to write failed spec file names to a failed-tests.txt file
 */
class CustomSpecReporter extends Spec {
  constructor(runner, options) {
    super(runner, options);

    if (isCI() || process.env.GKE === 'true') {
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      runner.on('fail', (test, err) => {
        // create the report file it doesn't exist
        if (!fs.existsSync(reportFile)) {
          fs.writeFileSync(reportFile, '');
        }

        let specFile = test.file.split('kong-api-tests/').pop();

        if (!failedSpecs.includes(specFile)) {
          console.log(`This failed test will be rerun: ${specFile}`);
          failedSpecs.push(specFile);
          try {
            return execSync(`echo ${specFile} >> failed-tests.txt`, {
              stdio: 'inherit',
            });
          } catch (error) {
            console.log(
              `Something went wrong while writing failed test filenames to a file: ${error}`
            );
          }
        }
      });
    }
  }
}

module.exports = CustomSpecReporter;

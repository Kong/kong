require('dotenv').config();
const { v4: uuidv4 } = require('uuid');

const addRootHooks = () => {
  const testApp = process.env.TEST_APP;
  if (!testApp) {
    throw new Error('No value provided for environment variable: TEST_APP');
  }
  let hooks = [];
  switch (testApp) {
    case 'gateway':
      hooks.push('test/gateway/_hooks.ts');
      break;
    case 'koko':
      hooks.push('test/koko/_hooks.ts');
      break;
    default:
      throw new Error(`TEST_APP: ${testApp} is not currently supported`);
  }
  return hooks.join(',');
};

module.exports = {
  extension: ['.spec.ts'],
  reporter: 'mocha-multi-reporters',
  reporterOptions: `configFile=.mocharc.js,cmrOutput=xunit+output+${uuidv4()}`,
  reporterEnabled: 'spec-failed-reporter.js,xunit',
  xunitReporterOptions: {
    output: 'results/test-results-{id}.xml',
  },
  require: `ts-node/register,tsconfig-paths/register,test/_fixtures.ts,${addRootHooks()}`,
  timeout: '180000',
  ui: 'bdd',
};

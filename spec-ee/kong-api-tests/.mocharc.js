require('dotenv').config();
const { v4: uuidv4 } = require('uuid');

const addRootHooks = () => {
  let hooks = [];
  hooks.push('/test/gateway/_hooks.ts');
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
  timeout: '60000',
  ui: 'bdd',
};

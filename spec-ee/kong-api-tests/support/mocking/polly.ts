import { Polly } from '@pollyjs/core';
import NodeHttpAdapter from '@pollyjs/adapter-node-http';
import FSPersister from '@pollyjs/persister-fs';
import * as path from 'path';
import { PollyConfig } from '../interfaces/polly'

Polly.register(NodeHttpAdapter);
Polly.register(FSPersister);

// pollyjs configuration options can be found here https://netflix.github.io/pollyjs/#/configuration

/**
 * Returns new polly insance with some predefined configurations
 * @param {string} name - name of the recording
 * @param {object} PollyConfig- pollyjs configuration, all configurations except name are optional
 * @returns {object} - new polly instance
 */
export const createPolly = (name, config?: PollyConfig): Polly => {
  return new Polly(name, {
    // configuring polly for http requests and filesystem storage for the recordings
    adapters: ['node-http'],
    persister: 'fs',
    persisterOptions: {
      fs: {
        recordingsDir: path.resolve(process.cwd(), `./support/mocking/${name}`),
      }
    },
    // The Polly mode
    mode: config?.mode || 'replay',
    // Set the log level for the polly instance
    logLevel: config?.logLevel || 'info',
    // If a request's recording is not found, pass-through to the server and record the response
    recordIfMissing: true,
    // After how long the recorded request will be considered expired from the time it was persisted
    expiresIn: '30d',
    // What should occur when Polly tries to use an expired recording in replay mode
    expiryStrategy: 'warn',
    matchRequestsBy: {
      headers: false
    }
  });
}

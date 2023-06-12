import { execSync } from 'child_process';
import { logDebug } from './logging';
import Os from 'os';

/**
 * Run a given command
 *
 * @param {string} command - the command to be run
 */
export const execCustomCommand = (command) => {
  let result;

  try {
    result = execSync(command, { encoding: 'utf-8', stdio: [] });
    logDebug(result);
  } catch (e: any) {
    result = e;
    logDebug(e.stderr);
  }

  return result;
};

/**
 * Checks if tests are running on arm64 linux platform (arm64 linux is GH arm64 runner)
 * @returns {boolean}
 */
export const checkForArm64 = () => {
  const currentArch = Os.arch();
  const currentPlatform = Os.platform();

  return currentArch === 'arm64' && currentPlatform === 'linux';
};

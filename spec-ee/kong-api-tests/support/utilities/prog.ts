import { execSync } from 'child_process';
import { logDebug } from './logging';

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

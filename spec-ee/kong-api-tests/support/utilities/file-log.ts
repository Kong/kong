import { expect } from '../assert/chai-expect';

/**
 * Validates the content of a File-Log Plugin generated log file.
 * Each request is logged separately as a JSON object, with entries separated by new lines (\n).
 * The function checks for the existence of specific keys and optionally validates their values.
 * 
 * @param {string} logContent - The content of the log file as a string.
 * @param {Array<{testKey: string, shouldExist: boolean, expectedTestValue?: string}>} validations - 
 * An array of objects defining the keys to check. 
 * Each object should contain:
 * - `testKey`: The key path (in dot notation) to check within each log entry.
 * - `shouldExist`: A boolean indicating whether the key should exist.
 * - `expectedTestValue` (optional): If provided, the function will also check if the key's value matches this.
 */


export const checkLogPropertyAndValue = (
  logContent: string,
  validations: { testKey: string, shouldExist: boolean, expectedTestValue?: string }[]
) => {
  const logEntries = logContent.trim().split('\n');

  validations.forEach(({ testKey, shouldExist, expectedTestValue }) => {
    let keyExists = false;
    let valueMatches = false;

    for (const entry of logEntries) {
      try {
        const logObject = JSON.parse(entry);
        const keys = testKey.split('.'); // Split the key by dot notation
        let value: any = logObject;

        for (const key of keys) {
          if (value === undefined) {
            keyExists = false;
            break;
          }
          value = value[key];
        }

        if (value !== undefined) {
          keyExists = true;
          if (expectedTestValue !== undefined && value === expectedTestValue) {
            valueMatches = true;
            break;
          }
        }
      } catch (error) {
        console.error('Failed to parse JSON:', entry, error);
      }
    }

    // Assertions based on existence and value checks
    if (expectedTestValue !== undefined) {
      expect(valueMatches, `Expected value ${expectedTestValue} not found in JSON property ${testKey}`).to.be.true;
    } else {
      expect(keyExists, `Expected key ${testKey} to ${shouldExist ? 'exist' : 'not exist'} in any JSON object`).to.equal(shouldExist);
    }
  });
};

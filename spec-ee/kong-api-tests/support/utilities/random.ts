import { v4 as uuidv4 } from 'uuid';

/**
 * @returns {string} - Random string
 */
export const randomString = () => {
  return uuidv4().toUpperCase().split('-')[4];
};

/**
 * @param {number} waitTime - number in milliseconds to wait
 */
export const wait = async (waitTime: number) => {
  return await new Promise((resolve) => setTimeout(resolve, waitTime));
};

/**
 * Find match of a given regex in a given string and return Boolean
 * @param {string} regexPattern to search for
 * @param {string} targetString
 * @param {string} testOrExec - either 'test' or 'exec' to control the return value
 * @returns {boolean}
 */
export const findRegex = (regexPattern, targetString, testOrExec = 'test') => {
  const regex = new RegExp(regexPattern, 'g');
  return testOrExec === 'test' ? regex.test(targetString) : regex.exec(targetString);
};

/**
 * Find number of matches of a given regex in a given string and return count
 * @param {string} regexPattern to search for
 * @param {string} targetString
 * @returns {number}
 */
export const regexCount = (regexPattern, targetString) => {
  const regex = new RegExp(regexPattern, 'g');
  return (targetString.match(regex) || []).length;
};
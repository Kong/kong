import { gatewayAuthHeader } from '../config/gateway-vars';
import { logDebug } from './logging';
import * as fs from 'fs';
import _ from 'lodash';
import path from 'path';
const { authHeaderKey, authHeaderValue } = gatewayAuthHeader();
import { execCustomCommand } from '@support';

/**
 * Construct a decK command with the given cmd component
 * @param {object} string - the actual deck command
 */
export const constructDeckCommand = (cmd) => {
  const finalCommand = `deck gateway ${cmd} --headers "${authHeaderKey}: ${authHeaderValue}"`;

  logDebug(`built deck cmd -> ${finalCommand}`);
  return finalCommand;
};

/**
 * Construct and execute a deck command
 * @param {string} cmd - the deck command component
 * @returns {string} - the result of executing the command
 */
export const executeDeckCommand = (cmd: string) => {
  const finalCommand = constructDeckCommand(cmd);
  return execCustomCommand(finalCommand);
};

export const readDeckConfig = (deckFileName: string): object | any=> {
  try {
    const fileContent = fs.readFileSync(`./${deckFileName}`, 'utf8');
    return JSON.parse(fileContent);
  } catch (error) {
    console.error(`Error reading or parsing ${deckFileName}:`, error);
    return undefined;
  }
}

/**
 * Modify or remove keys in the deck configuration JSON file.
 * @param {string} deckFileName - The path to the JSON file.
 * @param {string | string[]} paths - The path(s) to modify or remove
 * @param {any} [value] - The value to set. If undefined, the key will be removed.
 * @returns {boolean} - Indicates if any modifications were made.
 */
export const modifyDeckConfig = (
  deckFileName: string,
  paths: string | string[],
  value?: any
): boolean => {
  try {
    const data = readDeckConfig(deckFileName);
    if (!data) {
      throw new Error('Failed to load JSON data');
    }

    const pathsArray = Array.isArray(paths) ? paths : [paths];
    const valuesArray = Array.isArray(value) ? value : [value];
    let isModified = false;

    pathsArray.forEach((path, index) => {
      const valueToSet = valuesArray[index];

      if (valueToSet === undefined) {
        // Remove the key if the value is undefined
        if (_.has(data, path)) {
          _.unset(data, path);
          isModified = true;
        } else {
          console.log(`Path "${path}" not found in ${deckFileName}, nothing to remove.`);
        }
      } else {
        // Set or modify the key with the provided value
        _.set(data, path, valueToSet);
        isModified = true;
      }
    });

    if (isModified) {
      fs.writeFileSync(deckFileName, JSON.stringify(data, null, 2), 'utf8');
      console.log(`Updated paths in ${deckFileName} successfully`);
      return true;
    } else {
      console.log(`No changes made for paths in ${deckFileName}`);
      return false;
    }
  } catch (error) {
    console.error(`Error modifying ${deckFileName}:`, error);
    return false;
  }
};

/**
 * Backs up the specified JSON file by creating a .bak copy.
 * @param {string} filePath - The path to the JSON file to back up.
 * @returns {string} - The path to the backup file created.
 */
export const backupJsonFile = (filePath: string): string => {
  const dir = path.dirname(filePath);
  const backupFilePath = path.join(dir, `${path.basename(filePath)}.bak`);

  try {
    // Check if the original file exists
    if (!fs.existsSync(filePath)) {
      throw new Error(`File does not exist: ${filePath}`);
    }

    // Copy the original JSON file to the backup location
    fs.copyFileSync(filePath, backupFilePath);
    console.log(`Backup created at ${backupFilePath}`);
    return backupFilePath;
  } catch (error) {
    console.error(`Error backing up the file:`, error);
    throw new Error(`Error backing up the file: ${error}`);
  }
};

/**
 * Restores the original JSON file from the backup.
 * @param {string} filePath - The path to the original JSON file to restore.
 * @param {string} backupFilePath - The path to the backup file to restore from.
 */
export const restoreJsonFile = (filePath: string, backupFilePath: string): void => {
  try {
    // Check if the backup file exists
    if (!fs.existsSync(backupFilePath)) {
      throw new Error(`Backup file does not exist: ${backupFilePath}`);
    }

    // Restore the original file from the backup
    fs.copyFileSync(backupFilePath, filePath);
    console.log(`Restored ${filePath} from ${backupFilePath}`);

    // Delete the backup file after successful restoration
    fs.unlinkSync(backupFilePath);
    console.log(`Deleted backup file ${backupFilePath}`);
  } catch (error) {
    console.error(`Error restoring the file:`, error);
    throw new Error(`Error backing up the file: ${error}`);
  }
};
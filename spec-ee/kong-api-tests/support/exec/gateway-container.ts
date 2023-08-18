import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import { isGwNative } from 'support/config/gateway-vars';

/**
 * Sets Kong Gateway target container variables
 * @param {object} targetEnvironmentVariables - {KONG_PORTAL: 'on', KONG_VITALS: 'off'}
 * @param {string} containerName - target docker kong container name, default is 'kong-cp'
 */
export const setGatewayContainerEnvVariable = (
  targetEnvironmentVariables: object,
  containerName
) => {
  const isKongNative = isGwNative();
  const newVars: any = [];
  let restartCommand;

  for (const envVar in targetEnvironmentVariables) {
    const modifiedVar = `-e ${envVar}=${targetEnvironmentVariables[envVar]}`;
    newVars.push(modifiedVar);
  }

  const finalVars = newVars.join(' ');

  if (isKongNative) {
    restartCommand =
      containerName === 'kong-dp1'
        ? `kong restart -c kong-dp.conf`
        : `kong restart -c kong.conf`;
  } else {
    restartCommand = 'kong reload';
  }

  try {
    return execSync(
      `kongVars="${finalVars}" command="${restartCommand}" make gwContainerName=${containerName} update_kong_container_env_var`,
      { stdio: 'inherit' }
    );
  } catch (error) {
    console.log(
      `Something went wrong during updating the container environment variable: ${error}`
    );
  }
};

/**
 * Stops Gateway in CI and starts it with a custom env variable
 * @param {string} targetEnvironmentVariables - space separated env variables e.g. `GW_ENTERPRISE=false PG_SSL=true`
 */
export const startGwWithCustomEnvVars = (
  targetEnvironmentVariables: string
) => {
  try {
    return execSync(
      `make envVars="${targetEnvironmentVariables}" custom_start_gw`,
      { stdio: 'inherit' }
    );
  } catch (error) {
    console.log(
      `Something went wrong while restarting gateway with custom environment variables: ${error}`
    );
  }
};

/**
 * Reads given kong container logs
 * @param {string} containerName - target docker kong container name
 * @param {number} numberOfLinesToRead - the number of lines to read from logs
 */
export const getGatewayContainerLogs = (
  containerName,
  numberOfLinesToRead = 4
) => {
  const isKongNative = isGwNative();
  const logFile = path.resolve(process.cwd(), 'error.log');

  const command = isKongNative
    ? `docker cp "${containerName}":/var/error.log ${logFile}`
    : `docker logs $(docker ps -aqf name="${containerName}") --tail ${numberOfLinesToRead} 2>&1 | cat > error.log`;

  try {
    // using | cat as simple redirection like &> or >& doesn't work in CI Ubuntu
    execSync(command);
    const logs = execSync(`tail -n ${numberOfLinesToRead} ${logFile}`);
    console.log(`Printing current log slice of kong container: \n${logs}`);

    // remove logs file
    if (fs.existsSync(logFile)) {
      fs.unlinkSync(logFile);
      console.log(`\nSuccessfully removed target file: 'error.log'`);
    }

    return logs;
  } catch (error) {
    console.log('Something went wrong while reading the container logs');
  }
};

/**
 * Get the kong version from running docker container
 * @param {string} containerName
 * @returns {string}
 */
export const getKongVersionFromContainer = (containerName = 'kong-cp') => {
  const containers = execSync(`docker ps --format '{{.Names}}'`).toString();
  if (!containers.includes(containerName)) {
    throw new Error(
      `The docker container with name ${containerName} was not found`
    );
  }

  try {
    const version = execSync(
      `docker exec ${containerName} /bin/bash -c "kong version"`,
      { stdio: ['inherit', 'pipe', 'pipe'] }
    );

    return version.toString().trim();
  } catch (error) {
    console.log(
      `Something went wrong while getting kong container version: ${error}`
    );
  }
};

/**
 * Run docker start on db container
 * @param {string} containerName - name of the container to start
 * @param {string} command - command to run, can be either stop or start
 */
export const runDockerContainerCommand = async (containerName, command) => {
  // stop docker postgres database container
  const result = await execSync(`docker ${command} ${containerName}`);
  return result.toString('utf-8');
};

import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import { getKongContainerName, isGwNative } from 'support/config/gateway-vars';

/**
 * Sets Kong Gateway target container variables
 * @param {object} targetEnvironmentVariables - {KONG_PORTAL: 'on', KONG_VITALS: 'off'}
 * @param {string} containerName - target docker kong container name, default is 'kong-cp'
 */
export const setGatewayContainerEnvVariable = (
  targetEnvironmentVariables: object,
  containerName: string
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
    throw new Error(
      `Something went wrong during updating the container environment variable: ${error}`
    );
  }
};

/**
 * Reload gateway
 * @param {string} containerName - target docker kong container name, default is 'kong-cp'
 */
export const reloadGateway = (
  containerName: string = getKongContainerName()
) => {
  const command = 'kong reload'

  try {
    return execSync(
      `docker exec $(docker ps -aqf name=${containerName}) ${command}`,
      { stdio: 'inherit' }
    );
  } catch (error) {
    console.log(
      `Something went wrong during reloading the gateway: ${error}`
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
    throw new Error(
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

/**
 * Generates code snippet and deploys a Konnect Data Plane via Docker in the same network as other test 3rd party services
 * @param {string} controlPlaneEndpoint - Konnect control_plane_endpoint
 * @param {string} telemetryEndpoint - Konnect telemetry_endpoint
 * @param {string} cert - the generated certificate file
 * @param {string} privateKey - the generated private key file
 * @param {string} gatewayDpImage - target gateway image for the data plane
 * @param {string} targetOS- Options are: 'docker' - default, macosintel, macosarm
 * @param {number} dataPlaneCount - number of data planes to deploy, default is 1
 */
export const deployKonnectDataPlane = (controlPlaneEndpoint, telemetryEndpoint, cert, privateKey, gatewayDpImage, targetOS = 'docker', dataPlaneCount = 1) => {
  let osConfig: string
  let dockerNetwork: string

  // Define Platform as in Konnect Platform dropdown menu
  if (targetOS === 'macosintel') {
    osConfig = 'macOsIntelOS'
  } else if (targetOS === 'macosarm') {
    osConfig = 'macOsArmOS'
  } else {
    osConfig = 'linuxdockerOS'
  }

  const staticInstructions = `-e "KONG_ROLE=data_plane" \
  -e "KONG_DATABASE=off" \
  -e "KONG_VITALS=off" \
  -e "KONG_CLUSTER_MTLS=pki" \
  -e "KONG_CLUSTER_CONTROL_PLANE=${controlPlaneEndpoint}:443" \
  -e "KONG_CLUSTER_SERVER_NAME=${controlPlaneEndpoint}" \
  -e "KONG_CLUSTER_TELEMETRY_ENDPOINT=${telemetryEndpoint}:443" \
  -e "KONG_CLUSTER_TELEMETRY_SERVER_NAME=${telemetryEndpoint}" \
  -e "KONG_CLUSTER_CERT=${cert}" \
  -e "KONG_CLUSTER_CERT_KEY=${privateKey}" \
  -e "KONG_LUA_SSL_TRUSTED_CERTIFICATE=system" \
  -e "KONG_KONNECT_MODE=on" \
  -e "KONG_CLUSTER_DP_LABELS=created-by:quickstart,type:docker-${osConfig}"`

  // if the target test network exists, create cdp container in that network
  try {
    execSync(`docker network ls | grep 'gateway-docker-compose-generator_kong-ee-net'`);
    dockerNetwork = '--net gateway-docker-compose-generator_kong-ee-net'
  } catch (error) {
    dockerNetwork = ''
  }

  for(let i = 1; i <= dataPlaneCount; i++) {
    const port1 = 8000 + (i-1) * 10
    const port2 = 8443 + (i-1) * 10

    const dpCodeSnippet = `docker run --name konnect-dp${i} ${dockerNetwork} -d \
    ${staticInstructions} \
    -p ${port1}:8000 \
    -p ${port2}:8443 \
    ${gatewayDpImage}`

    try {
      execSync(dpCodeSnippet, { stdio: 'inherit' });
      console.info(`Successfully deployed the Konnect data plane named: konnect-dp${i} \n`)
    } catch (error) {
      console.error('Something went wrong while deploying the Konnect data plane', error);
    }
  }
}

/**
 * Stops and removes the target container
 * @param {string} containerName 
 */
export const stopAndRemoveTargetContainer = (containerName) => {
    try {
      execSync(`docker stop ${containerName}; docker rm ${containerName} -f`, { stdio: 'inherit' });
      console.info(`Successfully removed the ${containerName} docker container`)
    } catch (error) {
      console.error(`Something went wrong while removing the ${containerName} docker container`, error);
    }
  }
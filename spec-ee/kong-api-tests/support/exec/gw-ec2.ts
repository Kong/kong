import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Stop all active docker services in Gateway EC2 instance
 */
export const safeStopGateway = () => {
  try {
    return execSync(`make safe_stop_gw`, { stdio: 'inherit' });
  } catch (error) {
    console.log('All EC2 Docker services were shut down');
  }
};

/**
 * Pull the nightly master image and Start the Gateway
 */
export const startGateway = () => {
  try {
    execSync(`make pull_nightly_master`, { stdio: 'inherit' });
    return execSync(`make start_gw_classic`, { stdio: 'inherit' });
  } catch (error) {
    console.log('Classic Mode Gateway was started!');
  }
};

/**
 * Remove secret pem file if that was created during test execution
 * @param {string} fileName
 */
export const removeSecretFile = (fileName) => {
  const createdSecretFile = path.resolve(process.cwd(), fileName);

  if (fs.existsSync(createdSecretFile)) {
    fs.unlinkSync(createdSecretFile);
    console.log(`\nSuccessfully removed target file: ${fileName}`);
  }

  return;
};

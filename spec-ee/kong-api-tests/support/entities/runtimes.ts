const RUNTIME_GROUP_IDS: { [key: string]: string } = {};

/**
 * Set the runtime group ID for the current run
 * @param {string} runtimeGroupId runtime group id
 * @param {string} runtimeGroupName runtime group name (default: default)
 */
export const setRuntimeGroupId = (
  runtimeGroupId: string,
  runtimeGroupName = 'default'
): void => {
  RUNTIME_GROUP_IDS[runtimeGroupName] = runtimeGroupId;
};

/**
 * Get the runtime group ID for the current run
 * @param {string} runtimeGroupName runtime group name (default: default)
 * @returns {string} runtime group id
 */
export const getRuntimeGroupId = (runtimeGroupName = 'default'): string => {
  if (runtimeGroupName in RUNTIME_GROUP_IDS) {
    return RUNTIME_GROUP_IDS[runtimeGroupName];
  }
  return '<RUNTIME_GROUP_ID>';
};

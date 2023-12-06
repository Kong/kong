/**
 * Wait for the `assertions` does not throw any exceptions.
 * @param assertions - The assertions to be executed.
 * @param timeout - The timeout in milliseconds.
 * @param interval - The interval in milliseconds.
 * @param verbose - Verbose logs in case of error
 * @returns {Promise<void>} - Asnyc void promise.
 */
export const eventually = async (
  assertions: () => Promise<void>,
  timeout = 30000,
  interval = 3000,
  verbose = false,
): Promise<void> => {
  let errorMsg = '';

  while (timeout >= 0) {
    const start = Date.now();
    try {
      await assertions();
      return;
    } catch (error: any) {
      const end = Date.now();
      if (verbose) {
        errorMsg = error.message;
        console.log(errorMsg);
        console.log(
            `** Assertion(s) Failed -- Retrying in ${interval / 1000} seconds **`
        );
      }
      await new Promise((resolve) => setTimeout(resolve, interval));
      timeout -= interval + (end - start);
    }
  }
  throw new Error(errorMsg);
};

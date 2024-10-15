import { isCI } from '@support';

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
  timeout = 120000,
  interval = 3000,
  verbose = false,
): Promise<void> => {
  let errorMsg = '';
  // enable verbose logs in GH Actions for debugability
  verbose = isCI() ? true : verbose

  while (timeout >= 0) {
    const start = Date.now();
    try {
      await assertions();
      return;
    } catch (error: any) {

      if (verbose) { // Inside CI environment, do exponential backoff
        interval *= 2; // Double the delay for the next attempt
        interval +=  Math.random() * 1000; // Add jitter

        errorMsg = error.message;
        console.log(errorMsg);
        console.log(
            `** Assertion(s) Failed -- Retrying in ${interval / 1000} seconds **`
        );
      }
      await new Promise((resolve) => setTimeout(resolve, interval));
      const end = Date.now();
      timeout -= interval + (end - start);
      console.log(`remaining timeout: ${timeout}`);
    }
  }
  throw new Error(errorMsg);
};

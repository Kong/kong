import * as fs from 'fs';
import * as path from 'path';


/**
 * Reads the target file and returns its contents
 * @returns {string}
 */
export const getTargetFileContent = (filename: string) => {
  const file = path.resolve(process.cwd(), filename);

  if (fs.existsSync(file)) {
    return fs.readFileSync(file, 'utf8');
  } else {
    console.error(`Couldn't read the given file at ${file}`);
  }
}

/**
 * Create a file with the given content
 */
export const createFileWithContent = (filename, content) => {
  const file = path.resolve(process.cwd(), filename);

  fs.writeFileSync(file, content);
}

/**
 * Delete the target file
 */
export const deleteTargetFile = (filename) => {
  const file = path.resolve(process.cwd(), filename);

  try {
    if (fs.existsSync(file)) {
      fs.unlinkSync(file);
      console.log(`\nSuccessfully removed target file: ${file.split('/').pop()}`);
    }
  } catch (error) {
    console.error('Something went wrong while removing the file', error);
  }
}
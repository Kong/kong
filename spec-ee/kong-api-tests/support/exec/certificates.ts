import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Generate public and private certificates
 */
export const generatePublicPrivateCertificates = async () => {
  try {
    execSync(`openssl genrsa -out private.pem 2048`, { stdio: 'inherit' });
    execSync(`openssl rsa -in private.pem -outform PEM -pubout -out public.pem`, { stdio: 'inherit' });
    execSync(`openssl req -new -key private.pem -out certificate.csr -subj "/C=US/ST=State/L=Toronto/O=Kong/OU=Gateway/CN=Kong"`, { stdio: 'inherit' });
    execSync(`openssl x509 -req -days 3650 -in certificate.csr -signkey private.pem -out certificate.crt`, { stdio: 'inherit' });
  } catch (error) {
    console.error('Something went wrong while generating ssl certificates', error);
  }
};

export const removeCertficatesAndKeys = () => {
  const privateKey = path.resolve(process.cwd(), 'private.pem');
  const publicKey = path.resolve(process.cwd(), 'public.pem');
  const csrCert = path.resolve(process.cwd(), 'certificate.csr');
  const cert = path.resolve(process.cwd(), 'certificate.crt');

  const files = [privateKey, publicKey, csrCert, cert];

  files.forEach(file => {
    try{
      if (fs.existsSync(file)) {
        fs.unlinkSync(file);
        console.log(`\nSuccessfully removed target file: ${file.split('/').pop()}`);
      }
    } catch (error) {
      console.error('Something went wrong while removing certificate files', error);
    }
  })
}

/**
 * Reads the target file and returns its contents
 * @returns {string}
 */
export const getTargetFileContent = (filename: string) => {
  const file = path.resolve(process.cwd(), filename);

  if (fs.existsSync(file)) {
    console.log("exists")
    return fs.readFileSync(file, 'utf8');
  } else {
    console.error(`Couldn't read the given file at ${file}`);
  }
}
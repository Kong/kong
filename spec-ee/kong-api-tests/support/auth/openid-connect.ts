
import jwt from 'jsonwebtoken'
import crypto from 'crypto'
import { authDetails } from '@fixtures'

const generateDpopProof = async ({time: timestamp, nonce: nonce, token: token, url: url, jti: jti}) => {
    const header = {
        alg: 'RS256',
        typ: 'dpop+jwt',
        jwk: authDetails.dpop.public_jwk,
    }
    const payload = {
        htu: url,
        htm: 'POST',
        jti: jti,
        iat: timestamp,
    }
    if (nonce) {
        payload['nonce'] = nonce
    }
    if (token) {
        // access token -> s256 hash -> base64 encode -> remove padding -> url encode -> ath claim
        payload['ath'] = await crypto.createHash('sha256')
            .update(token)
            .digest('base64')
            .split('=')[0]
            .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
    }
    const webtoken = jwt.sign(payload, authDetails.dpop.private_pem, {header: header}) 
    return webtoken
}

export { generateDpopProof }
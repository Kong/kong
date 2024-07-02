
import jwt from 'jsonwebtoken'
import crypto from 'crypto'
import { authDetails } from '@fixtures'
import axios from 'axios'
import querystring from 'querystring'
import { execCustomCommand } from '@support'

/**
 * Generate a DPoP proof for a given request
 * These parameters, unless noted, are required for a valid proof 
 * and must be matched to the request that is being sent
 * 
 * The first dpop proof created does not contain a token or nonce. 
 * the nonce is created after the first request. The token is created after the second. 
 * As each is created they are added to the dpop proof and that proof is submitted to the idp.
 * @param {number} options.time - timestamp of the request
 * @param {string} options.nonce - nonce, returned with first request to be used in subsequent proofs
 * @param {string} options.token - access token used for second proof after first has been used to request token
 * @param {string} options.url - redirect url for the request
 * @param {string} options.jti - jti (optional, an identifier)
 * @returns {Promise<string>} - DPoP proof
 */
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

/**
 * Generate a JWT token for a given client
 * @param {string} clientid - client id
 * @param {string} audPath - audience path
 * @param {string} redirect_uri - redirect uri
 * @returns {Promise<string>} - JWT token
 */
const generateJWT = (clientid, audPath, redirect_uri) => {
    const jwtPayload = {
        iss: clientid,
        aud: audPath,
        response_type: 'code',
        client_id: clientid,
        redirect_uri: redirect_uri, 
    }
    const header = {
        alg: 'RS256',
        typ: 'JWT',
    }
    const jwtToken = jwt.sign(jwtPayload, authDetails.keycloak.client_pem_private, {header: header})
    return jwtToken
}

/**
 * Send request to login page
 * @param {string} actionUrl - url of the login page
 * @param {string} username - username
 * @param {string} password - password
 * @param {string} cookies - login cookies
 */
const submitLoginInfo = async (actionUrl, username, password, cookies) => {
    const resp = await axios({
        method: 'POST',
        url: actionUrl,
        data: querystring.stringify({
            username: username,
            password: password,
            credentialId: '',
        }),
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Host': 'localhost:8543',
            // imitate browser
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3',
            Cookie: cookies,
        },
        validateStatus: null,
        maxRedirects: 0,
    })
    return resp
}

/* 
* Get Keycloak logs
* @param {string} containerName - target docker kong container name
* @param {number} numberOfLinesToRead - the number of lines to read from logs
* @returns {string} - logs
* */
const getKeycloakLogs = async (containerName, numberOfLinesToRead = 25) => {
    const command = `docker logs --tail ${numberOfLinesToRead} ${containerName}`
    const logs = await execCustomCommand(command)
    return logs
}

export { generateDpopProof, generateJWT, submitLoginInfo, getKeycloakLogs }
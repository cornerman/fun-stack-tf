import {promisify} from 'util';
import * as Axios from 'axios';
import * as jsonwebtoken from 'jsonwebtoken';
const jwkToPem = require('jwk-to-pem');

export interface ClaimVerifyRequest {
  readonly queryStringParameters?: any;
  readonly headers?: any;
  readonly type?: string;
  readonly methodArn?: string | null;
  readonly routeArn?: string | null;
}

export interface ClaimVerifyResult {
  readonly principalId: string;
  readonly policyDocument: any;
  readonly context: any;
}

interface AWSPolicyStatement {
  Action: string;
  Effect: string;
  Resource: string;
}

interface AWSPolicy {
  Version: string;
  Statement: AWSPolicyStatement[];
}

interface TokenHeader {
  kid: string;
  alg: string;
}
interface PublicKey {
  alg: string;
  e: string;
  kid: string;
  kty: string;
  n: string;
  use: string;
}
interface PublicKeyMeta {
  instance: PublicKey;
  pem: string;
}

interface PublicKeys {
  keys: PublicKey[];
}

interface MapOfKidToPublicKey {
  [key: string]: PublicKeyMeta;
}

interface Claim {
  token_use: string;
  auth_time: number;
  iss: string;
  iat: number
  exp: number;
  client_id: string;
  jti: string;
  scope: string;
  sub: string
  username: string;
  version: number;
}

const cognitoPoolId = process.env.COGNITO_POOL_ID!;
const cognitoApiScopes = process.env.COGNITO_API_SCOPES!;
const allowUnauthenticated = process.env.ALLOW_UNAUTHENTICATED! === "true";
const awsRegion = process.env.AWS_REGION!;
const identitySource = process.env.IDENTITY_SOURCE!;

const cognitoIssuer = `https://cognito-idp.${awsRegion}.amazonaws.com/${cognitoPoolId}`;

let cacheKeys: MapOfKidToPublicKey | undefined;
const getPublicKeys = async (): Promise<MapOfKidToPublicKey> => {
  if (!cacheKeys) {
    const url = `${cognitoIssuer}/.well-known/jwks.json`;
    const publicKeys = await Axios.default.get<PublicKeys>(url);
    cacheKeys = publicKeys.data.keys.reduce((agg, current) => {
      const pem = jwkToPem(current);
      agg[current.kid] = {instance: current, pem};
      return agg;
    }, {} as MapOfKidToPublicKey);
    return cacheKeys;
  } else {
    return cacheKeys;
  }
};

const verifyPromised = promisify(jsonwebtoken.verify.bind(jsonwebtoken));

function generatePolicy(resource: string, effect: string): AWSPolicy {
  return {
    Version: '2012-10-17',
    Statement: [
      {
        Action: 'execute-api:Invoke',
        Effect: effect,
        Resource: resource
      }
    ],
  };
}

const handler = async (request: ClaimVerifyRequest): Promise<ClaimVerifyResult> => {
  const resourceArn = request.methodArn || request.routeArn;

  try {
    // console.log(`user claim verify invoked for ${JSON.stringify(request)}`);
    const token = (function () {
      if (identitySource === "HEADER") {
        const header = request.headers.authorization
        if (header == null || header == '') return null;
        const headerSections = header.split(' ');
        if (headerSections.length < 2 || headerSections[0] != "Bearer") {
          throw new Error('expected bearer token');
        }
        return headerSections[1];
      }
      else if (identitySource === "QUERYSTRING") {
        return request.queryStringParameters.token
      }
      else throw new Error("unknown IDENTITY_SOURCE: " + identitySource);
    })();

    if (token == null || token == '') {
      if (allowUnauthenticated) {
        console.log("Allow: anonymous");
        return {
          principalId: 'anon',
          policyDocument: generatePolicy(resourceArn, "Allow"),
          context: {}
        }
      } else {
        throw new Error('unauthenticated');
      }
    }

    const tokenSections = token.split('.');
    if (tokenSections.length < 2) {
      throw new Error('requested token is invalid');
    }
    const headerJSON = Buffer.from(tokenSections[0], 'base64').toString('utf8');
    const header = JSON.parse(headerJSON) as TokenHeader;
    const keys = await getPublicKeys();
    const key = keys[header.kid];
    if (key === undefined) {
      throw new Error('claim made for unknown kid');
    }
    const claim = await verifyPromised(token, key.pem) as Claim;
    const currentSeconds = Math.floor((new Date()).valueOf() / 1000);
    if (currentSeconds > claim.exp || currentSeconds < claim.auth_time) {
      throw new Error('claim is expired or invalid');
    }
    const cognitoApiScopesSplit = cognitoApiScopes.split(" ");
    const claimScopesSplit = claim.scope.split(" ");
    //TODO: allow admin scope, otherwise initiated access tokens dont work: https://github.com/aws/aws-sdk/issues/178
    const hasCorrectClaims = claimScopesSplit.some(s => s == "aws.cognito.signin.user.admin") || cognitoApiScopesSplit.every(scope => claimScopesSplit.some(s => s == scope));
    if (!hasCorrectClaims) {
      throw new Error(`claim misses scope, required: ${cognitoApiScopes}`);
    }
    if (claim.iss !== cognitoIssuer) {
      throw new Error('claim issuer is invalid');
    }
    if (claim.token_use !== 'access') {
      throw new Error('claim use is not access');
    }

    console.log(`Allow: claim confirmed for ${claim.username}`);
    return {
      principalId: 'user',
      policyDocument: generatePolicy(resourceArn, "Allow"),
      context: stringifyClaim(claim)
    };
  } catch (error) {
    console.error("Deny: Failed to verify token", error);
    return {
      principalId: null,
      policyDocument: generatePolicy(resourceArn, "Deny"),
      context: {}
    };
  }
};

// Every claim value has to be of type string. Otherwise api-gateway will
// silently drop the request and it will never reach the api-lambda. The
// jwt-authorizer of the api gateway http-api just stringifies all
// non-string claims. We do the same:
function stringifyClaim(claim: object) {
  const result = {};

  for (var key in claim) {
    if (claim.hasOwnProperty(key)) {
      const value = claim[key];
      if (typeof value === 'string' || value instanceof String) {
        result[key] = value;
      } else {
        result[key] = JSON.stringify(value);
      }
    }
  }

  return result;
}

export {handler};

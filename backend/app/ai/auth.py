import os, jwt
from jwt import PyJWKClient

REGION = os.environ.get("COGNITO_REGION", "us-east-1")
POOL_ID = os.environ["COGNITO_USER_POOL_ID"]
ISSUER = f"https://cognito-idp.{REGION}.amazonaws.com/{POOL_ID}"
_jwks = PyJWKClient(f"{ISSUER}/.well-known/jwks.json")

class AuthError(Exception):
    pass

class User:
    def __init__(self, sub): self.sub = sub

def verify_cognito_token(header: str) -> User:
    token = header.removeprefix("Bearer ").strip()
    if not token:
        raise AuthError("no token")
    try:
        key = _jwks.get_signing_key_from_jwt(token).key
        claims = jwt.decode(token, key, algorithms=["RS256"], issuer=ISSUER,
                            options={"verify_aud": False})
    except Exception as e:
        raise AuthError(str(e))
    return User(claims["sub"])

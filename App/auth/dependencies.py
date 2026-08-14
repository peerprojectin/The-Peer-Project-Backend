from fastapi import Request, HTTPException, status

from App.auth.jwt import JWT


COOKIE_NAME = "access_token"


def get_current_admin(
    request: Request
):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials."
    )

    token = request.cookies.get(COOKIE_NAME)

    if not token:
        raise credentials_exception

    payload = JWT.verify_access_token(token)

    if payload is None:
        raise credentials_exception

    username = payload.get("sub")
    role = payload.get("role")

    if username is None or role is None:
        raise credentials_exception

    if role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not authorized"
        )

    return payload
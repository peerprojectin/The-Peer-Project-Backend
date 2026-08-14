from fastapi import APIRouter, HTTPException, Depends, Response
from fastapi.security import OAuth2PasswordRequestForm

from App.auth.dependencies import get_current_admin
from App.schemas.AdminLogin import AdminLogin
from App.schemas.AdminCreate import AdminResponse
from App.services.auth_service import AuthService
from App.repository.AdminRepo import AdminRepo

from postgrest.exceptions import APIError


router = APIRouter(
    prefix="/admin",
    tags=["admin"]
)


# ============================================================
# ADMIN LOGIN
# ============================================================

@router.post("/login")
async def adminLoginRequest(
    response: Response,
    form_data: OAuth2PasswordRequestForm = Depends()
):
    try:

        credentials = AdminLogin(
            username=form_data.username,
            password=form_data.password
        )

        result = AuthService.login(credentials)

        response.set_cookie(
            key="access_token",
            value=result["access_token"],
            httponly=True,
            secure=False,       # Change to True when using HTTPS
            samesite="lax",
            path="/"
        )

        return {
            "success": True,
            "message": "Login successful"
        }

    except APIError:
        raise HTTPException(
            status_code=500,
            detail="Database error."
        )


# ============================================================
# ADMIN LOGOUT
# ============================================================

@router.post("/logout")
async def adminLogout(
    response: Response
):

    response.delete_cookie(
        key="access_token",
        path="/"
    )

    return {
        "success": True,
        "message": "Logged out successfully"
    }


# ============================================================
# GET ALL ADMINS
# ============================================================

@router.get("/")
async def getAllAdmins(
    current_admin=Depends(get_current_admin)
):

    result = AdminRepo.getAll()

    return {
        "success": True,
        "mentor": result
    }


# ============================================================
# GET ADMIN BY USERNAME
# ============================================================

@router.get("/{username}")
async def get_data_by_username(
    username: str,
    current_admin=Depends(get_current_admin)
):

    result = AdminRepo.getDataByUsername(username)

    if not result:
        raise HTTPException(
            status_code=404,
            detail="Invalid Credential"
        )

    return {
        "success": True,
        "Admin": result
    }


# ============================================================
# DELETE ADMIN
# ============================================================

@router.delete("/{username}")
async def delete_admin(
    username: str,
    current_admin=Depends(get_current_admin)
):

    result = AdminRepo.deleteData(username)

    return {
        "success": True,
        "admin": result.data
    }


# ============================================================
# CREATE ADMIN
# ============================================================

@router.post("/admin")
async def createAdmin(
    data: AdminResponse,
    current_admin=Depends(get_current_admin)
):

    return AuthService.createAdmin(data)
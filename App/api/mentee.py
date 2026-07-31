from fastapi import APIRouter, HTTPException, Depends
from postgrest.exceptions import APIError
from App.schemas.mentees import MenteesRegistration
from App.auth.dependencies import get_current_admin
from App.repository.MenteeRepo import MenteeRepo

from App.AI.embeddings.service import EmbeddingService
from App.AI.embeddings.repository import EmbeddingRepo

router = APIRouter(
    prefix="/mentee",
    tags=["Mentee"]
)

@router.post("/")
async def register_mentee(
    mentees: MenteesRegistration
): 
    try:
        result = MenteeRepo.createData(
            mentees.model_dump(mode="json")
        )

        mentee_data = result.data[0]
        
        embedding = EmbeddingService.mentee_embedding(
                    MenteesRegistration(**mentee_data)
        )
        
        EmbeddingRepo.createMenteeEmbedding(
                    mentee_data["discord_id"],
                    embedding
        )

        return {
            "success": True,
            "mentee": result.data
        }
    except APIError as e:
        if "discord_id" in str(e):
            raise HTTPException(
                status_code=409,
                detail="Discord ID already exists"
            )
        
        raise HTTPException(
            status_code=500,
            detail="Database error."
        )
    
@router.get("/count")
async def getTotal(current_admin = Depends(get_current_admin)):
    return MenteeRepo.getCount()


@router.get("/menteesAll")
async def get_mentee_all(current_admin = Depends(get_current_admin)):
    result = MenteeRepo.getAll()
    return {
        "success": True,
        "mentee": result
    }

@router.get("/{discord_id}")
async def get_mentee_id(discord_id: str, current_admin = Depends(get_current_admin)):
    result = MenteeRepo.getDataByID(discord_id)

    if not result:
        raise HTTPException(
            status_code=404,
            detail="Mentee Not Found"
        )
    return{
        "success": True,
        "mentee": result
    }


@router.put("/{discord_id}")
async def update_mentee_one_field(discord_id: str, data, field:str, current_admin = Depends(get_current_admin)):
    result = MenteeRepo.updateDataField(discord_id, data, field)

    EMBEDDING_FIELDS ={
            "full_name",
            "display_name",
            "email",
            "reddit_id",
            "discord_id",
            "helpIn",
            "additionalInfo",
            "track",
            "Availability",
        }
    
    if field in EMBEDDING_FIELDS:
        mentee = MenteeRepo.getDataByID(discord_id)[0]
    
            
        embedding = EmbeddingService.mentee_embedding(
                MenteesRegistration(**mentee)
        )
    
        EmbeddingRepo.updateMenteeEmbedding(
                discord_id,
                embedding
        )


    return{
        "success": True,
        "Mentee": result.data
    }

@router.patch("/{discord_id}/verify")
async def verify_mentee(
    discord_id: str,
    is_verified: bool,
    current_admin = Depends(get_current_admin)
):
    result = MenteeRepo.updateVerificationStatus(
        discord_id,
        is_verified
    )

    return {
        "success": True,
        "message": f"Verification status updated to {is_verified}",
        "mentee": result.data
    }

@router.delete("/{discord_id}/delete")
async def delete_mentee_id(discord_id: str, current_admin = Depends(get_current_admin)):

    EmbeddingRepo.deleteMenteeEmbedding(
            discord_id
        )

    result = MenteeRepo.deleteData(discord_id)
    return{
        "success": True,
        "Mentee": result.data
    }


from fastapi import APIRouter, Depends, HTTPException

from App.auth.dependencies import get_current_admin

from App.schemas.assignment import Assignment
from App.repository.AssignRepo import AssignRepo
from App.repository.MenteeRepo import MenteeRepo

from App.AI.embeddings.repository import EmbeddingRepository
from App.AI.embeddings.search import EmbeddingSearch
from App.AI.models.gemma import Gemma


router = APIRouter(
    prefix="/Assign",
    tags=["Assign"]
)


# ============================================================
# ASSIGNMENT CRUD
# ============================================================

@router.post("/")
async def assign_mentor(
    assigns: Assignment
):
    result = AssignRepo.createData(
        assigns.model_dump(mode="json")
    )

    return {
        "success": True,
        "assign": result.data
    }


@router.get("/")
async def get_assign_all(
    current_admin=Depends(get_current_admin)
):
    result = AssignRepo.getAll()

    return {
        "success": True,
        "assign": result
    }


@router.get("/{id}")
async def get_assign_id(
    id: int,
    current_admin=Depends(get_current_admin)
):
    result = AssignRepo.getDataByID(id)

    return {
        "success": True,
        "assign": result
    }


@router.put("/{id}/moreFields")
async def update_assign_more(
    id: int,
    data: dict,
    current_admin=Depends(get_current_admin)
):
    result = AssignRepo.updateData(
        id,
        data
    )

    return {
        "success": True,
        "assign": result.data
    }


@router.put("/{id}/singleField")
async def update_assign_one_field(
    id: int,
    data,
    field: str,
    current_admin=Depends(get_current_admin)
):
    result = AssignRepo.updateDataField(
        id,
        data,
        field
    )

    return {
        "success": True,
        "assign": result.data
    }


@router.delete("/{id}")
async def delete_assign_id(
    id: int,
    current_admin=Depends(get_current_admin)
):
    result = AssignRepo.deleteData(id)

    return {
        "success": True,
        "assign": result.data
    }


@router.get("/count")
async def getTotal(
    current_admin=Depends(get_current_admin)
):
    return AssignRepo.getCount()


# ============================================================
# AI MENTOR MATCHING
# ============================================================

@router.post("/match")
async def create_match(
    mentee_id: str,
    current_admin=Depends(get_current_admin)
):

    # --------------------------------------------------------
    # 1. Get mentee
    # --------------------------------------------------------

    mentee_data = MenteeRepo.getDataByID(
        mentee_id
    )

    if not mentee_data:
        raise HTTPException(
            status_code=404,
            detail="Mentee not found"
        )

    mentee = mentee_data[0]

    # --------------------------------------------------------
    # 2. Check mentee verification
    # --------------------------------------------------------

    if not mentee["isVerified"]:
        raise HTTPException(
            status_code=403,
            detail="Mentee is not verified"
        )

    # --------------------------------------------------------
    # 3. Get mentee embedding
    # --------------------------------------------------------

    mentee_embedding = (
        EmbeddingRepository
        .getMenteeEmbedding(
            mentee_id
        )
    )

    if not mentee_embedding:
        raise HTTPException(
            status_code=404,
            detail="Mentee embedding not found"
        )

    embedding = mentee_embedding["embedding"]

    # --------------------------------------------------------
    # 4. Search for similar mentors
    # --------------------------------------------------------

    candidates = EmbeddingSearch.searchMentors(
        embedding=embedding,
        top_k=10
    )

    if not candidates:
        raise HTTPException(
            status_code=404,
            detail="No suitable mentors found"
        )

    # --------------------------------------------------------
    # 5. Get mentor profiles
    # --------------------------------------------------------

    mentor_ids = [
        candidate["mentor_id"]
        for candidate in candidates
    ]

    mentor_profiles = EmbeddingSearch.getMentorProfiles(
        mentor_ids
    )

    if not mentor_profiles:
        raise HTTPException(
            status_code=404,
            detail="Mentor profiles not found"
        )

    # --------------------------------------------------------
    # 6. Add similarity scores
    # --------------------------------------------------------

    similarity_map = {
        candidate["mentor_id"]: candidate["similarity"]
        for candidate in candidates
    }

    mentors_for_gemma = []

    for mentor in mentor_profiles:

        mentor_id = mentor["discord_id"]

        mentors_for_gemma.append({
            "mentor_id": mentor_id,
            "similarity": similarity_map.get(
                mentor_id,
                0
            ),
            "profile": mentor
        })

    # --------------------------------------------------------
    # 7. Send candidates to Gemma
    # --------------------------------------------------------

    match = Gemma.match_mentor(
        mentee_profile=mentee,
        mentor_profiles=mentors_for_gemma
    )

    # --------------------------------------------------------
    # 8. Validate Gemma's mentor
    # --------------------------------------------------------

    valid_mentor_ids = {
        mentor["discord_id"]
        for mentor in mentor_profiles
    }

    if match.mentor_id not in valid_mentor_ids:

        raise HTTPException(
            status_code=500,
            detail="Gemma returned an invalid mentor"
        )

    # --------------------------------------------------------
    # 9. Validate Gemma's mentee
    # --------------------------------------------------------

    if match.mentee_id != mentee_id:

        raise HTTPException(
            status_code=500,
            detail="Gemma returned an invalid mentee"
        )

    # --------------------------------------------------------
    # 10. Return recommendation
    # --------------------------------------------------------

    return {
        "success": True,
        "match": match.model_dump()
    }
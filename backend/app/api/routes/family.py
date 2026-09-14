from fastapi import APIRouter
from sqlalchemy import select

from app.api.deps import CurrentUser, SessionDep
from app.db.models import Family, User
from app.schemas.user import FamilyOut, UserOut

router = APIRouter(prefix="/family", tags=["family"])


@router.get("/members", response_model=list[UserOut])
async def list_members(user: CurrentUser, session: SessionDep) -> list[UserOut]:
    members = await session.scalars(
        select(User).where(User.family_id == user.family_id).order_by(User.created_at)
    )
    return [UserOut.model_validate(member) for member in members]


@router.get("", response_model=FamilyOut)
async def get_family(user: CurrentUser, session: SessionDep) -> FamilyOut:
    """Сверх контракта iOS: отдаёт код приглашения для будущего экрана «Пригласить»."""
    family = await session.get(Family, user.family_id)
    return FamilyOut.model_validate(family)

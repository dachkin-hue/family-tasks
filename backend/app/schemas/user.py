from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr

from app.db.models import FamilyRole


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    email: EmailStr
    role: FamilyRole
    color_hex: str | None = None


class FamilyOut(BaseModel):
    """Сверх контракта iOS — понадобится на шаге «пригласить в семью»."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    invite_code: str

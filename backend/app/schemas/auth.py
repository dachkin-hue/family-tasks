from pydantic import BaseModel, EmailStr, Field

from app.schemas.user import UserOut


class RegisterIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    email: EmailStr
    password: str = Field(min_length=4, max_length=128)
    # Расширение сверх контракта iOS: если код передан — пользователь входит
    # в существующую семью, иначе создаётся новая. Клиент поле не отправляет.
    invite_code: str | None = Field(default=None, max_length=12)


class LoginIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class RefreshIn(BaseModel):
    refresh_token: str = Field(min_length=10)


class TokensOut(BaseModel):
    access_token: str
    refresh_token: str
    expires_in: int


class AuthOut(TokensOut):
    user: UserOut

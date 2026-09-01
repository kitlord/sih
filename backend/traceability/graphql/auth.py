import datetime

import jwt
from django.conf import settings


def create_token(user) -> str:
    payload = {
        "user_id": user.id,
        "role": user.role,
        "exp": datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=settings.JWT_EXP_HOURS),
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm="HS256")


def decode_token(token: str):
    try:
        return jwt.decode(token, settings.JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError:
        return None

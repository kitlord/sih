"""
Django settings for the Honey Chain backend.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")


def env(name, default=None):
    return os.environ.get(name, default)


def env_bool(name, default=False):
    val = os.environ.get(name)
    if val is None:
        return default
    return val.strip().lower() in ("1", "true", "yes", "on")


def env_list(name, default=""):
    val = os.environ.get(name, default)
    return [item.strip() for item in val.split(",") if item.strip()]


# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = env("DJANGO_SECRET_KEY", "django-insecure-dev-only")

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = env_bool("DJANGO_DEBUG", True)

ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")


# Application definition

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "corsheaders",
    "traceability",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "honeychain.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "honeychain.wsgi.application"


# Database
# Postgres is used directly (already running locally) -- no sqlite fallback,
# to keep dev parity simple for this MVP.
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": env("DB_NAME", "honeychain"),
        "USER": env("DB_USER", "honeychain"),
        "PASSWORD": env("DB_PASSWORD", ""),
        "HOST": env("DB_HOST", "127.0.0.1"),
        "PORT": env("DB_PORT", "5432"),
    }
}

AUTH_USER_MODEL = "traceability.User"


# Password validation

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]


# Internationalization

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True


# Static / media files
STATIC_URL = "static/"

MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"


# CORS -- the Flutter web dev server runs on a different origin/port than
# Django, and consumers/beekeepers/admins never need cookies-based auth
# (JWT is passed via an Authorization header instead), so allowing all
# origins is an acceptable, clearly-scoped simplification for this hackathon
# MVP rather than a real security boundary decision.
CORS_ALLOW_ALL_ORIGINS = DEBUG

# The client sends this on every request (see client/lib/graphql/client.dart)
# to suppress ngrok's browser interstitial, even against a non-ngrok backend.
# Without it in the allow-list, browsers reject it during CORS preflight and
# block every GraphQL call client-side -- which surfaces in the app as a
# generic "Could not reach the server" error even though the backend is up.
from corsheaders.defaults import default_headers  # noqa: E402

CORS_ALLOW_HEADERS = list(default_headers) + ["ngrok-skip-browser-warning"]

# --- Honey Chain application settings ---

# Auth
JWT_SECRET = env("JWT_SECRET", "dev-only-secret")
JWT_EXP_HOURS = int(env("JWT_EXP_HOURS", "24"))

# Blockchain layer. Local Hardhat node stands in for "an EVM-compatible
# testnet" for this MVP -- swapping to a public testnet later is just an
# env change (WEB3_RPC_URL / RELAYER_PRIVATE_KEY / a redeploy's
# CONTRACT_ARTIFACT_PATH), no code changes.
WEB3_RPC_URL = env("WEB3_RPC_URL", "http://127.0.0.1:8545")
RELAYER_PRIVATE_KEY = env("RELAYER_PRIVATE_KEY")
CONTRACT_ARTIFACT_PATH = str((BASE_DIR / env("CONTRACT_ARTIFACT_PATH", "../contracts/deployments/localhost.json")).resolve())

# Used to build absolute, externally-openable URLs.
PUBLIC_BASE_URL = env("PUBLIC_BASE_URL", "http://localhost:8080").rstrip("/")
BACKEND_BASE_URL = env("BACKEND_BASE_URL", "http://localhost:8000").rstrip("/")

# FSSAI license verification of an apiary, via API Setu (see
# services/digilocker.py for why this isn't a DigiLocker "Requester" OAuth
# flow). Mocked by default; DIGILOCKER_USE_MOCK=False switches to a real
# call, no code changes. The API key/client id below default to API
# Setu's own public sandbox demo credentials, so this works against the
# sandbox with zero setup -- override them only for a real API Setu
# account or the production host.
DIGILOCKER_USE_MOCK = env_bool("DIGILOCKER_USE_MOCK", True)
APISETU_BASE_URL = env("APISETU_BASE_URL", "https://sandbox.api-setu.in").rstrip("/")
APISETU_API_KEY = env("APISETU_API_KEY", "demokey123456ABCD789")
APISETU_CLIENT_ID = env("APISETU_CLIENT_ID", "in.gov.sandbox")
# "recer" (Registration Certificate) or "fslcs" (Food Stuff License) --
# see services/digilocker.py's module docstring for the distinction.
APISETU_FSSAI_ENDPOINT = env("APISETU_FSSAI_ENDPOINT", "recer")

# Django's own default logging config only wires up console output for its
# own "django"/"django.server" loggers -- an app logger like
# services/digilocker.py's ("traceability.services.digilocker") would
# otherwise propagate to a handler-less root logger and never print
# anything, INFO-level or not. This adds just enough to make that
# module's "hit the real API Setu, got HTTP <code>" line show up in the
# normal `manage.py runserver` console -- handy as live, on-screen
# evidence during a demo that a check went out over the network rather
# than through the mock.
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "loggers": {
        "traceability": {"handlers": ["console"], "level": "INFO", "propagate": False},
    },
}

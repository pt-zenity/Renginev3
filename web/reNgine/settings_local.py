"""
Local dev override for UI testing — uses SQLite instead of PostgreSQL.
Import everything from main settings then override DB.
"""
import os, sys
from pathlib import Path

# Inject required env vars before importing settings
os.environ.setdefault('POSTGRES_DB', 'rengine')
os.environ.setdefault('POSTGRES_USER', 'rengine')
os.environ.setdefault('POSTGRES_PASSWORD', 'devpassword')
os.environ.setdefault('POSTGRES_HOST', 'localhost')
os.environ.setdefault('POSTGRES_PORT', '5432')
os.environ.setdefault('RENGINE_HOME', '/home/user/rengine')
os.environ.setdefault('EMAIL_HOST', 'localhost')
os.environ.setdefault('EMAIL_PORT', '587')
os.environ.setdefault('EMAIL_HOST_USER', '')
os.environ.setdefault('EMAIL_HOST_PASSWORD', '')

# Load parent settings
from reNgine.settings import *  # noqa: F401, F403

# Override DB to SQLite for local dev
BASE_DIR_LOCAL = Path(__file__).resolve().parent.parent

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR_LOCAL / 'db_local.sqlite3',
    }
}

# Override cache to local memory (no Redis needed)
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
    }
}

# Disable celery / channels for local dev
CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels.layers.InMemoryChannelLayer',
    }
}

# Static files for local dev
STATIC_URL = '/staticfiles/'
STATICFILES_DIRS = [BASE_DIR_LOCAL / 'static']
STATIC_ROOT = BASE_DIR_LOCAL / 'staticfiles_collected'

MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR_LOCAL / 'media'

DEBUG = True
ALLOWED_HOSTS = ['*']

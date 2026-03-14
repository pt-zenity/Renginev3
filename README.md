# reNgine-ng 3.0.0

## Project Overview
- **Name**: reNgine-ng (Next Generation)
- **Version**: 3.0.0
- **Goal**: Automated web application reconnaissance suite for security professionals, penetration testers, and bug bounty hunters.
- **Platform**: Docker-based (requires Docker + Docker Compose)

## Architecture

reNgine-ng uses a multi-container Docker architecture:

| Service | Image | Role |
|---------|-------|------|
| `web` | Python 3.13 Alpine | Django/Daphne ASGI web server |
| `db` | PostgreSQL 17 (with PG12 migration support) | Database |
| `redis` | Redis 7.4 | Message broker & cache |
| `celery` | Debian Bookworm | Celery workers + all security tools |
| `celery-beat` | Debian Bookworm | Celery scheduler |
| `proxy` | Nginx 1.27 Alpine | HTTPS reverse proxy |
| `ollama` | Ollama 0.3.6 | Local LLM for AI-powered analysis |

## Quick Installation (Linux)

```bash
# 1. Clone or extract the project
cd /home/user/webapp

# 2. Copy environment config
cp .env-dist .env

# 3. Edit .env with your settings (optional)
nano .env

# 4. Generate SSL certificates
make certs

# 5. Pull and start all services
make up

# 6. Create superuser (optional, default credentials in .env)
make superuser_create
```

**Access the application**: `https://localhost` (after `make up`)

**Default credentials** (set in `.env`):
- Username: `rengine`
- Password: `Sm7IJG.IfHAFw9snSKv`

## Build from Source (for development)

```bash
# Build Docker images locally
make build

# Start all services
make up

# Or build and start in one step
make build_up
```

## Development Mode

```bash
make dev_up
```

This enables:
- Hot reload for Python files
- Remote debugging (port 5678 for web, 5679 for celery)
- Celery Flower dashboard on port 5555

## Data Architecture
- **Database**: PostgreSQL 17 (with auto-migration from PostgreSQL 12)
- **Storage**: Named Docker volumes
  - `rengine_postgres_data` - Database data
  - `rengine_scan_results` - Scan output files
  - `rengine_nuclei_templates` - Nuclei templates
  - `rengine_tool_config` - Tool configurations
  - `rengine_wordlist` - Wordlists
  - `rengine_gf_patterns` - GF patterns
  - `rengine_github_repos` - GitHub repos
  - `rengine_ollama_data` - Ollama LLM data

## Security Tools Included (in celery container)
- **Subdomain**: subfinder, amass, sublist3r, ctfr, oneforall
- **HTTP Probing**: httpx, httprobe
- **Crawlers**: katana, gospider, hakrawler, waybackurls
- **Fuzzing**: ffuf, dirsearch
- **Vulnerability**: nuclei, dalfox (XSS), naabu (port scan)
- **Screenshots**: EyeWitness
- **OSINT**: theHarvester, infoga, GooFuzz
- **Other**: gf, unfurl, tlsx, crlfuzz, s3scanner, CMSeeK

## Ports
- **443** - HTTPS (main application)
- **8082** - HTTP (redirects to HTTPS)
- **8000** - Web server (internal, dev only: `127.0.0.1:8000`)
- **5432** - PostgreSQL (dev only: `127.0.0.1:5432`)
- **6379** - Redis (dev only: `127.0.0.1:6379`)
- **11434** - Ollama (dev only: `127.0.0.1:11434`)

## Useful Commands

```bash
make up           # Start all services
make down         # Stop and remove containers
make stop         # Stop all services (keep containers)
make restart      # Restart all services
make logs         # Tail all container logs
make migrate      # Run Django migrations
make prune        # Remove everything (containers, images, volumes)
make help         # Show all available commands
```

## Fixes Applied (v3.0.0)

The following bugs were identified and fixed in this setup:

1. **Poetry syntax error** (`poetry run -C` → `poetry -C ... run`):
   - `docker/web/entrypoint.sh`
   - `docker/web/entrypoint-dev.sh`
   - `docker/celery/entrypoint.sh`
   - `docker/celery/entrypoint-dev.sh`
   - `docker/beat/entrypoint.sh`

2. **Celery base image** (`debian:13` → `debian:bookworm`):
   - `debian:13` (Trixie) is unstable; `bookworm` (stable) is used instead

3. **Shell permission error** (`/bin/false` → `/bin/bash`):
   - `docker/celery/Dockerfile`: user shell was `/bin/false`, preventing script execution

4. **Missing entrypoint chmod**:
   - `docker/web/Dockerfile`: Added `chmod +x /entrypoint.sh` and proper root COPY
   - `docker/celery/Dockerfile`: Added `chmod +x /entrypoint.sh`

5. **Email format** in `.env`:
   - `DJANGO_SUPERUSER_EMAIL=<rengine@example.com>` → `DJANGO_SUPERUSER_EMAIL=rengine@example.com`

6. **Missing secrets directory**:
   - Created `docker/secrets/certs/` directory required for SSL certificates

## Environment Variables (.env)

Key settings in `.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_PASSWORD` | `hE2a5@K&9nEY1fzgA6X` | DB password |
| `DJANGO_SUPERUSER_USERNAME` | `rengine` | Admin username |
| `DJANGO_SUPERUSER_PASSWORD` | `Sm7IJG.IfHAFw9snSKv` | Admin password |
| `DOMAIN_NAME` | `rengine-ng.example.com` | SSL domain |
| `MIN_CONCURRENCY` | `5` | Min parallel scans |
| `MAX_CONCURRENCY` | `30` | Max parallel scans |
| `GPU` | `0` | Enable GPU for Ollama |

## System Requirements
- **OS**: Linux (recommended) or macOS
- **Docker**: >= 20.10.0
- **Docker Compose**: >= 2.2.0
- **RAM**: >= 8GB recommended
- **Disk**: >= 20GB free space (for all tools and scan data)

## Deployment Status
- **Platform**: Docker Compose (self-hosted)
- **Tech Stack**: Django 5.2 + Celery 5.5 + PostgreSQL 17 + Redis 7.4 + Nginx
- **Last Updated**: 2026-03-14

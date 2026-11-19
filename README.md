# TPP // ThePeerProject Backend
<img width="4500" height="1500" alt="image" src="https://github.com/user-attachments/assets/5f312f0d-c57a-4a75-ad7f-6d01ff490f30" />

> free // student-run // non-profit in collaboration of r/CBSE, r/ICSE, and r/JEE

> https://peerproject.in

## Overview
PeerProject is a student-focused mentorship platform designed to connect current high schoolers with the high school grads who walked the same path as they did. 

The Backend provides secure authentication, mentor/mentee management, AI-assisted mentor-mentee assignment and API endpoints for frontend and discord bot integration. 

## Architecture
<img width="1556" height="928" alt="image" src="https://github.com/user-attachments/assets/0ea517a5-ade0-4563-8d5b-7bb2e8c11d47" />
The Architecture choosen is the hub-spoke for easy upgradability. 

## Features
- JWT Authentication
- PostgreSQL Database with Supabase
- AI-powered Mentor-Mentee Assignment
- GraphQL Integration(Will be available in V2)
- Embeddings using pgvector in supabase.
- Mentor/Mentee Registration
- Secure API Calls
- Rest API

## Tech Stack
Backend
- FastAPI
- Python
- Pydantic for validation

Database
- PostgreSQL
- Supabase

Authentication
- JWT
- bcrypt
- HttpOnly cookies for secure token storage (protected routes no longer expose tokens to client-side scripts)

AI/LLM Services
- HuggingFace
- NVIDIA Llama Nemotron Embed 1B V2
- Gemma for assignment
- Deepseek for profile analysis

Deployment
- Docker (multi-stage image, GPU-enabled via NVIDIA Container Toolkit)
- Docker Compose
- Kubernetes (Kustomize manifests in `k8s/`)
- GitHub Actions CI/CD, images published to GHCR

## Installation
```bash
git clone github.com/ShyZen15/The-Peer-Project-Backend
cd The-Peer-Project-Backend
python -m venv .venv
pip install -r requirements.txt
```

## File Structure
```
The-Peer-Project-Backend/
|
├── App/
    ├── AI/
    ├── api/
    ├── auth/
    ├── repository/
    ├── schemas/
    ├── services/
    ├── config.py
    ├── main.py
    └── test.py
├── .github/workflows/   (ci.yml, cd.yml)
├── k8s/                 (Kubernetes manifests)
├── .dockerignore
├── .gitignore
├── database.py
├── docker-compose.yml
├── Dockerfile
└── requirements.txt
```

## Environment Variables
Refer to .env.example under App/

## Running
Local development:
```bash
fastapi dev
```

### Running with Docker
Requirements on the host:
- Docker + Docker Compose
- An NVIDIA GPU with a recent driver (CUDA 13.0 builds of PyTorch)
- NVIDIA Container Toolkit (Linux) or Docker Desktop with WSL2 GPU support (Windows)

```bash
cp App/.env.example App/.env   # then fill in the values, including HF_TOKEN
docker compose up -d --build
docker compose logs -f api
```

The first start downloads the embedding model and Gemma into the `hf-cache`
volume, so it takes a while. Later restarts reuse the cache.

The API listens on `127.0.0.1:8000`. The admin auth cookie is `Secure`, so in
production put an HTTPS reverse proxy (Caddy, Nginx, or your host's load
balancer) in front of it.

## CI/CD
GitHub Actions, in `.github/workflows/`:

| Workflow | Runs on | What it does |
|---|---|---|
| `ci.yml` | every PR and push | ruff lint, byte-compile, validate k8s + compose files, test-build the Docker image |
| `cd.yml` | push to `v3` (or manual run) | runs CI, then builds and pushes the image to `ghcr.io/shyzen15/the-peer-project-backend` (tags `sha-<commit>`, `v3`, `latest`), then deploys it to Kubernetes pinned by digest, rolling back if the new pod doesn't become healthy |

To turn on the deploy step:
1. Repo **Settings → Environments**: create `production` and add secret `KUBE_CONFIG` (a kubeconfig that can deploy to the `peerproject` namespace). Optionally add required reviewers for a manual approval gate.
2. Repo **Settings → Variables**: set `K8S_DEPLOY_ENABLED` to `true`.

Until then CD still builds and publishes the image and skips the deploy.

## Kubernetes
Cluster requirements:
- A GPU node with the NVIDIA device plugin (or NVIDIA GPU Operator)
- An ingress controller (set `ingressClassName` in `k8s/ingress.yaml`)
- cert-manager with a `letsencrypt-prod` ClusterIssuer (HTTPS is required for the secure admin cookie)

First deploy:
```bash
kubectl create namespace peerproject
kubectl -n peerproject create secret generic peerproject-backend-env --from-env-file=App/.env
kubectl apply -k k8s/
kubectl -n peerproject rollout status deployment/peerproject-backend --timeout=20m
```

Edit the host in `k8s/ingress.yaml` to your real API domain before applying.
If the image pull fails with an auth error, make the GHCR package public or add an `imagePullSecret`.

## API Documentation
FastAPI uses Swagger UI in its docs for testing API endpoints
hence to access it go to https://localhost:8000/docs

## Database Design
<img width="982" height="988" alt="image" src="https://github.com/user-attachments/assets/eedea6ef-ddc2-42f8-b269-529245d0f890" />

## Roadmap

- [x] Mentor APIs
- [x] Mentee APIs
- [x] Admin Authentication
- [x] AI Embeddings
- [x] Semantic Search
- [x] Mentor Assignment Engine
- [ ] GraphQL API
- [ ] Discord Bot Integration
- [x] Docker Deployment
- [x] CI/CD Pipeline
- [x] Kubernetes Deployment

## Author
Developed by Shiven Sharma(ShyZen15) Co-Founder @ ThePeerProject

## Copyright
© 2026 peerproject.in. all rights reserved. 


# AGENTS.md — OpenShorts

Repo-specific guidance for AI agents working in this codebase.

---

## Quick Start

```bash
docker compose up --build
```

- Backend (FastAPI): http://localhost:8000
- Frontend (Vite/React): http://localhost:5175
- Renderer (Remotion): http://localhost:3100

> The README says `localhost:5175` but the dashboard Dockerfile exposes `5173`. The Vite dev server port depends on how you run it. In Docker Compose the frontend maps `5175:5173` by default; adjust `docker-compose.yml` if ports collide.

---

## Architecture

Three-service Docker Compose stack:

| Service | Source Dir | Tech | Internal Port | Role |
|---------|-----------|------|---------------|------|
| `backend` | repo root (`./`) | Python 3.11, FastAPI, Uvicorn | 8000 | Core API, video processing, job queue |
| `frontend` | `dashboard/` | React 18, Vite 4, Tailwind 3.4 | 5173 | Dashboard UI |
| `renderer` | `render-service/` | TypeScript, Express, Remotion 4 | 3100 | Video rendering microservice |

**There is no `backend/` directory.** The backend code lives at the repo root (`app.py`, `main.py`, etc.).

### Vite Proxy (dev only)

The frontend dev server proxies API calls:
- `/api`, `/videos`, `/thumbnails`, `/gallery`, `/video` → `http://backend:8000`
- `/render` → `http://renderer:3100`

In production, the backend also serves the built frontend static files.

---

## Key Files

| File | Purpose |
|------|---------|
| `app.py` | FastAPI app, async job queue, REST endpoints, static file serving |
| `main.py` | Core video pipeline: transcription, scene detection, clip extraction, vertical reframing |
| `editor.py` | Gemini integration for AI-generated FFmpeg video effects |
| `hooks.py` | Hook text overlay generation with font rendering |
| `subtitles.py` | SRT/ASS generation, FFmpeg subtitle burning |
| `translate.py` | ElevenLabs AI voice dubbing |
| `thumbnail.py` | YouTube thumbnail + title generation via Gemini |
| `saasshorts.py` | AI Shorts (UGC video) pipeline |
| `s3_uploader.py` | AWS S3 upload with caching |
| `dashboard/src/App.jsx` | Main React component, tab routing, state management |
| `dashboard/src/config.js` | API URL config (`getApiUrl`) |
| `render-service/src/server.ts` | Remotion renderer HTTP API |
| `remotion/src/` | Remotion video composition components |

---

## Development Commands

### Full stack (Docker)
```bash
docker compose up --build
```

### Frontend only
```bash
cd dashboard
npm install
npm run dev       # port 5173
npm run build
npm run lint      # strict: --max-warnings 0
```

### Backend only (local Python)
```bash
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8000
```

### Renderer only
```bash
cd render-service
npm install
npm run dev       # tsx watch src/server.ts
npm run build     # tsc
npm run start     # node dist/server.js
```

---

## Environment & Config

### Server-side (`.env`)
Only AWS S3 and concurrency settings. All API keys are client-side.

```bash
cp .env.example .env
```

| Var | Default | Purpose |
|-----|---------|---------|
| `MAX_CONCURRENT_JOBS` | 5 | Semaphore limit for async job queue |
| `AWS_ACCESS_KEY_ID` | — | S3 backup (optional) |
| `AWS_SECRET_ACCESS_KEY` | — | S3 backup (optional) |
| `AWS_REGION` | `eu-west-3` | S3 region |
| `AWS_S3_BUCKET` | — | Private clips bucket |
| `AWS_S3_PUBLIC_BUCKET` | — | Public gallery/avatars bucket |

### Client-side (encrypted in `localStorage`)
Entered via **Settings** tab in the UI. Never stored server-side.

| Key | Required for |
|-----|-------------|
| `GEMINI_API_KEY` | All AI features (clip detection, titles, thumbnails, effects) |
| `FAL_KEY` | AI Shorts (actor generation, talking head, lip-sync) |
| `ELEVENLABS_API_KEY` | Voice dubbing / voiceover |
| `UPLOAD_POST_API_KEY` | Social auto-publishing (optional) |

Encryption uses XOR + Base64 with `VITE_ENCRYPTION_KEY` (build-time env, defaults to a static salt).

---

## Testing

**No test suite exists.** There are no `pytest`, `jest`, or `vitest` configs and no test files.

Verification is manual:
1. Start the stack with Docker
2. Open `http://localhost:5175/#app`
3. Enter a Gemini API key in **Settings**
4. Submit a YouTube URL or upload in **Clip Generator**
5. Poll `/api/status/{job_id}` or watch the UI progress log

---

## Code Style & Linting

- **Python**: No formatter/linter config found. Follow PEP 8.
- **JSX**: ESLint flat config (`dashboard/eslint.config.js`). Strict rules:
  - `--max-warnings 0`
  - `no-unused-vars` errors (except capitalized vars, likely components)
  - React Hooks and Refresh plugins enabled
- **No Prettier config** found.
- **No type checking** on frontend (no TypeScript except in `render-service/` and `remotion/`).

---

## Docker Notes

- Backend image is multi-stage (`python:3.11-slim`).
- `yt-dlp` is **always upgraded to latest on build** (line 41 in `Dockerfile`) because YouTube bot detection changes frequently.
- YOLOv8 model (`yolov8n.pt`) is pre-downloaded at build time.
- Containers run as non-root `appuser`.
- The `render-service` Dockerfile is at `render-service/Dockerfile`, not repo root.

---

## API Conventions

- All endpoints under `/api/*` except static file routes (`/videos`, `/thumbnails`, `/gallery`, `/video/{id}`).
- Async job pattern: `POST /api/process` returns `{job_id}` → poll `GET /api/status/{job_id}`.
- Jobs auto-delete after 1 hour (`JOB_RETENTION_SECONDS = 3600`).
- File upload limit: 2 GB (`MAX_FILE_SIZE_MB = 2048`).

### Key Endpoints

| Method | Route | Purpose |
|--------|-------|---------|
| POST | `/api/process` | Submit video for clip generation |
| GET | `/api/status/{job_id}` | Poll job status + logs |
| POST | `/api/edit` | Apply AI video effects |
| POST | `/api/subtitle` | Generate/burn subtitles |
| POST | `/api/hook` | Add text hook overlays |
| POST | `/api/translate` | ElevenLabs voice dubbing |
| GET | `/api/translate/languages` | List supported dubbing languages |
| POST | `/api/social/post` | Publish to social platforms |
| POST | `/api/thumbnail/titles` | Generate YouTube titles |
| POST | `/api/thumbnail/generate` | Generate AI thumbnail |
| POST | `/api/saasshorts` | Generate AI Shorts (UGC) |

---

## Monorepo Boundaries

```
openshorts/
├── app.py, main.py, *.py          # Backend (Python, FastAPI)
├── dashboard/                     # Frontend (React, Vite)
│   ├── src/App.jsx                # Main app shell
│   ├── src/components/            # UI components
│   └── src/config.js              # API URL helper
├── render-service/                # Renderer (TypeScript, Express, Remotion)
│   └── src/server.ts
├── remotion/                      # Remotion video compositions
│   └── src/
├── output/                        # Generated clips (Docker volume)
├── uploads/                       # Uploaded files (Docker volume)
└── requirements.txt               # Python deps only
```

Do not treat this as a standard `backend/` + `frontend/` repo. The backend code is at root.

---

## Common Gotchas

1. **Port conflicts**: If `8000`, `5175`, or `3100` are taken, edit `docker-compose.yml` host ports (e.g., `8001:8000`). The README default is `5175:5173` but some clones use `5176:5173`.
2. **Missing API key = silent failures**: Most features require `GEMINI_API_KEY`. The UI shows "API Key Missing" badge but backend calls will fail without it.
3. **No hot reload for backend in Docker?** The backend `Dockerfile` does not use a watch mode; `docker compose up --build` rebuilds on start. For live editing, mount the root as a volume (already done in `docker-compose.yml`) and restart the container, or run `uvicorn` locally.
4. **Frontend hash routing**: The dashboard uses `window.location.hash === '#app'` to toggle between landing page and app. Direct links to `/app` may 404; use `/#app`.
5. **FFmpeg is required**: The backend relies heavily on FFmpeg for all video operations. It is installed in the Docker image; local dev requires system FFmpeg.
6. **GPU not required but strongly recommended**: YOLOv8 and MediaPipe run on CPU fine, but Whisper transcription and video encoding are much faster with CUDA.

---

## Existing Instruction Files

- `CLAUDE.md` — Claude Code guidance (similar to this file, less Docker-focused)

No `.cursorrules`, `.cursor/rules/`, `.github/copilot-instructions.md`, or `opencode.json` found.

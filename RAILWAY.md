# Deploy OpenShorts on Railway

Single-service MVP: FastAPI serves the API, static clips (`/videos`, `/thumbnails`), and the production Vite build from `dashboard/dist`. Use branch **`deploy/railway`** (or merge it to `main` and deploy that).

## Prerequisites

- [Railway](https://railway.app) account
- GitHub repo connected (e.g. [Progery222/OpenShorts](https://github.com/Progery222/OpenShorts))
- Expect a **large** Docker image (PyTorch, FFmpeg, ML stack). Prefer a plan with **at least 4–8 GB RAM** for stable video jobs.

## 1. Create the service

1. **New Project** → **Deploy from GitHub** → select the repository.
2. Choose branch **`deploy/railway`** (or `main` after merge).
3. Railway detects the root [Dockerfile](Dockerfile). [railway.toml](railway.toml) sets the Dockerfile builder, `/health` healthcheck, and a **300s** healthcheck timeout (first boot can be slow).

## 2. Public URL

1. Open the service → **Settings** → **Networking** → generate a **public domain**.
2. The app listens on **`PORT`** (set by Railway). [docker-entrypoint.sh](docker-entrypoint.sh) runs Uvicorn on `$PORT`.

## 3. Environment variables

Set variables in the Railway service (**Variables** tab). **Do not commit** `.env` or `cookies.txt`.

| Variable | Purpose |
|----------|---------|
| `GEMINI_API_KEY` | Optional server fallback; UI still sends `X-Gemini-Key` for most AI calls |
| `OPENAI_API_KEY` | Fallback for clip analysis if Gemini fails ([main.py](main.py)) |
| `OPENAI_CLIP_MODEL` | e.g. `gpt-4o-mini` (default if unset) |
| `MAX_CONCURRENT_JOBS` | Start with `1` or `2` on small instances |
| `AWS_*` | Optional S3 backup ([.env.example](.env.example)) |
| `YOUTUBE_COOKIES` | Optional Netscape cookies string for yt-dlp in cloud |
| `YOUTUBE_DISABLE_COOKIES` | `1` / `true` to skip cookies for public YouTube URLs |
| `RENDER_SERVICE_URL` | Default `http://renderer:3100` — **no renderer in MVP**; server-side Remotion proxy returns 502 until phase 2 (S3 + second service). In-browser Remotion in the UI still works for many flows |

Client-side API keys (Gemini, etc.) are stored in the browser in the dashboard; they are sent as headers to the same origin.

## 4. Volume (required for persisted clips)

Without a volume, generated files under `output/` are lost when the container restarts.

1. Create a **Volume** in Railway.
2. Mount it at **`/app/output`** (matches [app.py](app.py) `OUTPUT_DIR` for the default layout).

Optional: second volume at **`/app/uploads`** if you need uploads to survive restarts; otherwise uploads are ephemeral (often acceptable).

## 5. Smoke checks after deploy

Replace `https://YOUR_SERVICE.up.railway.app` with your URL:

- `GET /health` → `{"status":"ok"}`
- `GET /docs` → Swagger UI
- `GET /openapi.json` → OpenAPI schema
- `GET /` → HTML shell; open `/#app` for the app shell
- Run a small **Clip Generator** job with a Gemini key in Settings

## 6. Limitations (MVP)

- **In-memory jobs**: restarting the container clears job status in RAM; files may remain under `/app/output` but old `job_id` polling may not match without code changes.
- **YouTube**: datacenter IPs may be rate-limited; use fresh cookies, `YOUTUBE_DISABLE_COOKIES`, or **upload** the file instead.
- **Server Remotion** (`/api/render`): not wired for two Railway services without shared storage (e.g. S3). Plan phase 2 if you need that path.
- **Local Docker Compose**: if you bind-mount the repo over `/app`, `dashboard/dist` may be missing on the host until you run `cd dashboard && npm run build`; the API still runs, but the baked SPA path is empty inside the container.

## 7. Phase 2 (optional)

- Second Railway service from [render-service/Dockerfile](render-service/Dockerfile) with repo root as Docker context.
- Shared object storage for clip files and `RENDER_SERVICE_URL` pointing to the renderer (private networking or public URL).

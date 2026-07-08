# The Shared GenAI App

This is the **one application** we deploy everywhere in Session 4 — first to
Hugging Face Spaces, then to Azure Container Apps. Same code, same image, two very
different clouds. That's the whole point: a container is portable.

```
app/
├── main.py            # FastAPI + Google Gemini (see endpoints below)
├── requirements.txt   # pinned dependencies
├── Dockerfile         # builds the portable image (honors $PORT)
├── .dockerignore      # keeps secrets/junk out of the image
├── .gitignore         # keeps .env out of git (never commit keys!)
└── .env.example       # env var template
```

## Endpoints

| Method | Path             | Purpose                                  |
|--------|------------------|------------------------------------------|
| GET    | `/`              | Welcome + endpoint map                   |
| GET    | `/health`        | Health check (used by cloud probes)      |
| POST   | `/api/generate`  | Generate an AI response from a prompt    |
| GET    | `/api/history`   | List recent generations                  |
| DELETE | `/api/history`   | Clear history                            |
| GET    | `/docs`          | Swagger UI                               |

## Where the key comes from

The app reads **`GEMINI_API_KEY` or `GOOGLE_API_KEY`**. Your
`../../module3_agents/.env` already has `GOOGLE_API_KEY`, so you don't need to create
or rename anything — just point the app at that file.

> This is the Gemini **model API** (a plain API key from Google AI Studio). It is the
> app's *brain*, and is completely separate from *where the app is hosted*. We host on
> Azure and Hugging Face — no Google Cloud involved.

## Run it locally (no Docker)

```bash
pip install -r requirements.txt
# Load keys from the shared module3 env file, then run:
uvicorn main:app --reload
```

Open http://localhost:8000/docs and try `POST /api/generate` with
`{"prompt": "Explain serverless in one sentence"}`.

## Run it locally (Docker) — the exact image the clouds run

```bash
docker build -t genai-app:1.0 .

# Inject secrets from the shared env file (relative to this app/ folder):
docker run -d -p 8000:8000 --env-file ../../../module3_agents/.env genai-app:1.0

curl http://localhost:8000/health
# -> {"status":"healthy","api_key_configured":true, ...}
```

Once this works locally, the next two folders take the **same image** to the cloud:

1. [`../01-huggingface-spaces/`](../01-huggingface-spaces/) — the fast, public prototype.
2. [`../02-azure-container-apps/`](../02-azure-container-apps/) — the scalable production deploy.

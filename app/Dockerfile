# Shared image for the GenAI app - deployed unchanged to both HF Docker Spaces
# and Azure Container Apps.
#
# Build:  docker build -t genai-app:1.0 .
# Run:    docker run -d -p 8000:8000 --env-file ../../../module3_agents/.env genai-app:1.0
#
# Note on architecture: if you build on an Apple Silicon (M-series) Mac and push to a
# cloud that only accepts amd64, build with:
#   docker buildx build --platform linux/amd64 -t genai-app:1.0 .
# (Azure `az acr build` builds in the cloud as amd64, so this only matters for local pushes.)

FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Documentation only - the real port comes from the PORT env var at runtime.
EXPOSE 8000

# `sh -c` lets us expand ${PORT} at container start. Platforms that inject a PORT
# (Azure Container Apps, HF Docker Spaces) are honored; locally it defaults to 8000.
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]

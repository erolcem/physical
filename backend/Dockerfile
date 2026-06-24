# Physical backend image.
# Build from the REPO ROOT so the shared rank engine is included:
#   docker build -f backend/Dockerfile -t physical-backend .
# (On Railway/Render: set the Dockerfile path to backend/Dockerfile, root context.)
FROM python:3.12-slim

WORKDIR /app

# The backend imports the shared engine from <repo>/lib/engine — preserve that
# relative layout so app/engine.py's path resolution (parents[2]/lib/...) works.
COPY lib/engine/physical_rank_engine.py /app/lib/engine/physical_rank_engine.py

COPY backend/requirements.txt /app/backend/requirements.txt
RUN pip install --no-cache-dir -r /app/backend/requirements.txt

COPY backend/app /app/backend/app
COPY backend/scripts /app/backend/scripts

WORKDIR /app/backend
ENV PYTHONUNBUFFERED=1

# $PORT is provided by most hosts (Railway/Render); default to 8000 locally.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]

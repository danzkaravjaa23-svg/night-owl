# psql is supplied by the official PostgreSQL image; no Python DB driver or
# copied application data is needed by this catalog-only readiness service.
FROM postgres:17.11-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY readiness.py /app/readiness.py
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
ENTRYPOINT ["python3", "/app/readiness.py"]

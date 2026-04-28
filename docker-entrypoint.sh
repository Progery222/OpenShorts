#!/bin/sh
chown -R appuser:appuser /app/output /app/uploads
exec gosu appuser uvicorn app:app --host 0.0.0.0 --port "${PORT:-8000}"

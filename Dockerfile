FROM python:3.12-slim

WORKDIR /app

# Prevent Python from writing .pyc and buffer stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8000

# Copy node source files and storage
COPY node.py storage.py contracts.py council_portal.py ./
COPY node_*_chain.json ./

EXPOSE 8000

# Start CSII-Pay Blockchain Node
CMD ["python3", "node.py"]

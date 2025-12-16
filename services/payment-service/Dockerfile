FROM python:3.11-slim

WORKDIR /app

# Create a minimal payment service
RUN echo 'from fastapi import FastAPI\n\
import uvicorn\n\
\n\
app = FastAPI()\n\
\n\
@app.get("/health")\n\
def health():\n\
    return {"status": "healthy"}\n\
\n\
@app.get("/metrics")\n\
def metrics():\n\
    return {"payments_processed": 0}\n\
\n\
if __name__ == "__main__":\n\
    uvicorn.run(app, host="0.0.0.0", port=8084)' > main.py

RUN pip install --no-cache-dir fastapi uvicorn[standard]

EXPOSE 8084

CMD ["python", "main.py"]

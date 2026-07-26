# Imagen del backend del canal Asiscole.
# El docker-compose de la raiz monta ./backend en /app y ejecuta desde ahi
# runserver, "celery -A config worker" y "celery -A config beat".
FROM python:3.12-slim

# Salida sin buffer para que los logs JSON lleguen enteros a docker logs.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    TZ=America/Lima

WORKDIR /app

# libpq y tzdata: psycopg[binary] trae su propia libpq, pero tzdata hace falta
# para que America/Lima exista dentro del contenedor.
RUN apt-get update \
    && apt-get install -y --no-install-recommends tzdata \
    && rm -rf /var/lib/apt/lists/*

# Se copia primero requirements.txt para aprovechar la cache de capas.
COPY requirements.txt /app/requirements.txt
RUN pip install --upgrade pip && pip install -r /app/requirements.txt

# El codigo se copia para que la imagen sea autosuficiente; en desarrollo el
# bind mount de docker-compose lo sobreescribe con el arbol local.
COPY . /app

EXPOSE 8000

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]

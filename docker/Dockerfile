FROM python:3.11-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /orpheus
COPY vendor/orpheusdl-framework/ /orpheus/
COPY vendor/orpheusdl-tidal/ /orpheus/modules/tidal/

COPY docker/requirements.lock /tmp/requirements.lock
RUN pip install --no-cache-dir -r /tmp/requirements.lock \
 && rm /tmp/requirements.lock

RUN useradd -u 1000 -m orpheus \
 && mkdir -p /orpheus/config /orpheus/music \
 && chown -R orpheus:orpheus /orpheus \
 && rmdir /orpheus/extensions /orpheus/temp 2>/dev/null || true \
 && ln -s /tmp/extensions /orpheus/extensions \
 && ln -s /tmp/temp /orpheus/temp

USER orpheus
WORKDIR /orpheus

CMD ["sh", "-c", "mkdir -p /tmp/extensions /tmp/temp && sleep infinity"]

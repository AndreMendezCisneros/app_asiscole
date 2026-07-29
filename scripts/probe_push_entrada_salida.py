"""Dispara entrada+salida por ingesta HTTP y registra métricas (sin PII)."""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOG = ROOT / "debug-cbce09.log"
ENV = ROOT / ".env"
API = "https://jeanpiaget.asiscole.com/canal-api/v0.1/ingesta/eventos"


def _append(hypothesis_id: str, message: str, data: dict) -> None:
    payload = {
        "sessionId": "cbce09",
        "hypothesisId": hypothesis_id,
        "location": "scripts/probe_push_entrada_salida.py",
        "message": message,
        "data": data,
        "timestamp": int(time.time() * 1000),
        "runId": "push-eo-s",
    }
    with LOG.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(payload, ensure_ascii=False) + "\n")


def _ingest_key() -> str:
    for line in ENV.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("INGEST_API_KEY="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("INGEST_API_KEY ausente en .env")


def _post(tipo: str, id_estudiante: int, id_registro: int, key: str) -> dict:
    body = {
        "tenant_id": "jean_piaget",
        "tipo": tipo,
        "id_estudiante": id_estudiante,
        "id_registro": id_registro,
        "payload": {
            "id_estudiante": id_estudiante,
            "nombre_completo": "Estudiante",
            "grado": "5",
            "seccion": "A",
            "nivel_educativo": "Primaria",
            "fecha": "2026-07-27",
            "hora_llegada": "14:00" if tipo == "entrada" else None,
            "hora_salida": "14:05" if tipo == "salida" else None,
            "estado": "A tiempo",
            "tipo_salida": "Normal",
        },
    }
    # limpiar nulls
    body["payload"] = {k: v for k, v in body["payload"].items() if v is not None}
    raw = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        API,
        data=raw,
        headers={
            "Content-Type": "application/json",
            "X-Asiscole-Ingest-Key": key,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return {
                "http": resp.status,
                "body": json.loads(resp.read().decode("utf-8")),
            }
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:200]
        return {"http": exc.code, "body": {"error": detail}}


def main() -> None:
    key = _ingest_key()
    # id_estudiante por env opcional; si no, el operador lo pasa
    sid = int(os.environ.get("PROBE_ID_ESTUDIANTE", "0"))
    if sid <= 0:
        _append("H3", "falta_id_estudiante", {"hint": "PROBE_ID_ESTUDIANTE"})
        raise SystemExit("Define PROBE_ID_ESTUDIANTE=<id interno>")

    stamp = int(time.time())
    for tipo, offset in (("entrada", 1), ("salida", 2)):
        rid = stamp * 10 + offset
        result = _post(tipo, sid, rid, key)
        body = result.get("body") or {}
        _append(
            "H1_H3_H4",
            f"ingesta_{tipo}",
            {
                "http": result.get("http"),
                "creados": body.get("creados"),
                "apoderados_notificados": body.get("apoderados_notificados"),
                "origen_ok": isinstance(body.get("origen_evento"), str),
                "tiene_error": "error" in body or "codigo" in body,
            },
        )
        time.sleep(2)
    print("probe_ok")


if __name__ == "__main__":
    main()

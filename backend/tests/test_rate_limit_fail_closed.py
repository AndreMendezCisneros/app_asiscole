"""Rate-limit de login debe fallar cerrado si la cache no responde."""

from __future__ import annotations

import pytest

from apps.common.errors import TooManyRequests
from apps.cuentas import rate_limit


@pytest.mark.django_db
def test_verificar_login_fail_closed_si_cache_rota(monkeypatch):
    """Simula Redis degradado sin cambiar el backend global de tests (locmem)."""
    monkeypatch.setattr(rate_limit, "_cache_es_locmem", lambda: False)
    monkeypatch.setattr(rate_limit.cache, "set", lambda *a, **k: None)
    monkeypatch.setattr(rate_limit.cache, "get", lambda *a, **k: None)
    monkeypatch.setattr(rate_limit.cache, "delete", lambda *a, **k: None)

    with pytest.raises(TooManyRequests):
        rate_limit.verificar_login("credencial-hash-de-prueba", "127.0.0.1")

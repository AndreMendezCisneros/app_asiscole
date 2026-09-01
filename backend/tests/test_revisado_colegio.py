from apps.mensajeria.revisado_colegio import (
    id_incidencia_desde_mensaje,
    ids_incidencia_por_tenant,
    propagar_confirmaciones_existentes,
)


def test_id_incidencia_desde_origen_evento():
    assert (
        id_incidencia_desde_mensaje(
            tipo="incidencia",
            origen_evento="incidencia:9",
        )
        == 9
    )


def test_id_incidencia_ignora_entrada():
    assert (
        id_incidencia_desde_mensaje(
            tipo="entrada",
            origen_evento="entrada:1",
        )
        is None
    )


def test_id_incidencia_desde_metadata():
    assert (
        id_incidencia_desde_mensaje(
            tipo="incidencia",
            origen_evento="",
            metadata={"id_registro": 12},
        )
        == 12
    )


def test_agrupa_por_tenant_sin_duplicados():
    agrupados = ids_incidencia_por_tenant(
        [
            {
                "tenant_id": "asis_academy",
                "tipo": "incidencia",
                "origen_evento": "incidencia:8",
            },
            {
                "tenant_id": "asis_academy",
                "tipo": "incidencia",
                "origen_evento": "incidencia:8",
            },
            {
                "tenant_id": "asis_academy",
                "tipo": "entrada",
                "origen_evento": "entrada:1",
            },
            {
                "tenant_id": "jean_piaget",
                "tipo": "incidencia",
                "origen_evento": "incidencia:55",
            },
        ]
    )
    assert agrupados == {
        "asis_academy": [8],
        "jean_piaget": [55],
    }


def test_agrupa_confirmaciones_existentes(monkeypatch):
    ejecutado: list[tuple[str, list[int]]] = []

    def fake_ejecutar(sql, por_tenant, log_ok, log_fail):
        ejecutado.append((log_ok, list(por_tenant.items())))
        return {tenant: len(ids) for tenant, ids in por_tenant.items()}

    monkeypatch.setattr(
        "apps.mensajeria.revisado_colegio._ejecutar_por_tenant",
        fake_ejecutar,
    )
    resumen = propagar_confirmaciones_existentes(
        [
            {"tenant_id": "asis_academy", "id_incidencia_colegio": 9},
            {"tenant_id": "asis_academy", "id_incidencia_colegio": 9},
            {"tenant_id": "jean_piaget", "id_incidencia_colegio": 79},
        ]
    )
    assert resumen == {"asis_academy": 1, "jean_piaget": 1}
    assert ejecutado[0][0] == "confirmada_colegio_ok"

"""Pruebas del resolvedor del directorio (ADR-05, SRS 7.8).

Lo que se protege aqui es la diferencia entre "este telefono no existe" y "no he
podido comprobarlo". Confundirlas seria decirle a un apoderado que su hijo no
esta matriculado solo porque la BD de su colegio tardo dos segundos de mas.
"""

from __future__ import annotations

from datetime import timedelta

import pytest
from django.db import OperationalError
from django.utils import timezone

from apps.common.errors import UpstreamSchoolDbUnavailable
from apps.common.phone import normalizar_e164
from apps.directorio import cache as cache_directorio
from apps.directorio import circuit_breaker, services
from apps.directorio.models import VINCULO_INACTIVO, Directorio
from apps.directorio.repositorio import candidatos_digitos
from tests.conftest import DOCUMENTO, TELEFONO, TENANT, crear_vinculo, cuerpo_login

URL_LOGIN = "/v0.1/auth/login"


# ---------------------------------------------------------------------------
# Normalizacion de telefonos
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    ("crudo", "esperado"),
    [
        ("987654321", "+51987654321"),
        ("+51 987 654 322", "+51987654322"),
        ("51987654323", "+51987654323"),
    ],
)
def test_normalizacion_de_los_formatos_sucios_reales(crudo, esperado):
    """`telefono_contacto` llega en estos tres formatos y los tres son el mismo dato."""
    assert normalizar_e164(crudo) == esperado


def test_candidatos_de_digitos_cubren_las_tres_formas():
    """La consulta al colegio compara contra todas las escrituras plausibles."""
    candidatos = candidatos_digitos("+51987654321")

    assert "51987654321" in candidatos
    assert "987654321" in candidatos
    assert "0987654321" in candidatos


# ---------------------------------------------------------------------------
# Orden de resolucion
# ---------------------------------------------------------------------------

@pytest.mark.django_db
def test_un_hit_de_cache_no_toca_las_bd_de_colegio(colegios, monkeypatch):
    """Paso 1: si Redis responde, no se consulta ni la central ni los colegios."""
    llamadas = []
    monkeypatch.setattr(
        "apps.directorio.repositorio.consultar_colegio",
        lambda tenant, telefono: llamadas.append(tenant) or [],
    )
    cache_directorio.escribir_cache(TELEFONO, [crear_vinculo()])

    vinculos = services.resolver_vinculos(TELEFONO)

    assert [v.codigo_barras for v in vinculos] == [DOCUMENTO]
    assert llamadas == []
    assert not Directorio.objects.exists()


@pytest.mark.django_db
def test_un_hit_de_la_bd_central_cachea_y_no_toca_los_colegios(
    colegios, vinculo_en_directorio, monkeypatch
):
    """Paso 2: la proyeccion central evita el abanico y deja la cache caliente."""
    llamadas = []
    monkeypatch.setattr(
        "apps.directorio.repositorio.consultar_colegio",
        lambda tenant, telefono: llamadas.append(tenant) or [],
    )

    vinculos = services.resolver_vinculos(TELEFONO)

    assert len(vinculos) == 1
    assert llamadas == []
    assert cache_directorio.leer_cache(TELEFONO) is not None


@pytest.mark.django_db
def test_un_miss_resuelve_en_los_colegios_y_lo_persiste(colegios, monkeypatch):
    """Pasos 3 y 4: se consulta a los colegios, se guarda y se cachea."""
    def falso(tenant, telefono):
        return [crear_vinculo()] if tenant == TENANT else []

    monkeypatch.setattr("apps.directorio.repositorio.consultar_colegio", falso)

    vinculos = services.resolver_vinculos(TELEFONO)

    assert len(vinculos) == 1
    fila = Directorio.objects.get()
    assert fila.tenant_id == TENANT
    assert fila.codigo_barras == DOCUMENTO
    assert fila.origen == "resuelto_automatico"
    assert cache_directorio.leer_cache(TELEFONO) is not None


@pytest.mark.django_db
def test_sin_resultados_y_con_todos_los_colegios_sanos_devuelve_vacio(colegios, monkeypatch):
    """Paso 5a: todos respondieron y no hay vinculo. Eso es un 404, no un 503."""
    monkeypatch.setattr(
        "apps.directorio.repositorio.consultar_colegio", lambda tenant, telefono: []
    )

    assert services.resolver_vinculos(TELEFONO) == []


@pytest.mark.django_db
def test_sin_resultados_y_con_los_colegios_caidos_lanza_503(colegios, monkeypatch):
    """Paso 5b: si no se pudo verificar, no se puede afirmar que no exista."""
    def revienta(tenant, telefono):
        raise OperationalError("colegio caido")

    monkeypatch.setattr("apps.directorio.repositorio.consultar_colegio", revienta)

    with pytest.raises(UpstreamSchoolDbUnavailable):
        services.resolver_vinculos(TELEFONO)


@pytest.mark.django_db
def test_un_colegio_caido_no_impide_hallar_el_vinculo_en_otro(colegios, monkeypatch):
    """Una caida parcial no bloquea a quien si se pudo resolver."""
    def mixto(tenant, telefono):
        if tenant == TENANT:
            return [crear_vinculo()]
        raise OperationalError("colegio caido")

    monkeypatch.setattr("apps.directorio.repositorio.consultar_colegio", mixto)

    vinculos = services.resolver_vinculos(TELEFONO)

    assert len(vinculos) == 1


@pytest.mark.django_db
def test_el_login_traduce_el_fallo_de_los_colegios_en_503(api, colegios, monkeypatch):
    """El contrato: 503 UPSTREAM_SCHOOL_DB_UNAVAILABLE llega hasta el cliente."""
    def revienta(tenant, telefono):
        raise OperationalError("colegio caido")

    monkeypatch.setattr("apps.directorio.repositorio.consultar_colegio", revienta)

    respuesta = api.post(URL_LOGIN, cuerpo_login(), format="json")

    assert respuesta.status_code == 503
    assert respuesta.json()["code"] == "UPSTREAM_SCHOOL_DB_UNAVAILABLE"


@pytest.mark.django_db
def test_sin_colegios_configurados_no_se_inventa_un_503(db, monkeypatch, settings):
    """Sin colegios declarados no hay nada que verificar ni nada que fallar."""
    settings.SCHOOL_TENANTS = {}

    assert services.resolver_vinculos(TELEFONO) == []


# ---------------------------------------------------------------------------
# Cache e invalidacion
# ---------------------------------------------------------------------------

def test_invalidar_borra_el_telefono_viejo_y_el_nuevo(cache_en_memoria):
    """ADR-05: al cambiar un contacto quedan dos claves sucias, no una."""
    viejo, nuevo = "+51987654321", "+51987654999"
    cache_directorio.escribir_cache(viejo, [crear_vinculo(telefono=viejo)])
    cache_directorio.escribir_cache(nuevo, [crear_vinculo(telefono=nuevo)])

    cache_directorio.invalidar(nuevo, viejo)

    assert cache_directorio.leer_cache(viejo) is None
    assert cache_directorio.leer_cache(nuevo) is None


def test_no_se_cachea_un_resultado_vacio(cache_en_memoria):
    """Un telefono desconocido no puede quedar congelado 24 horas."""
    cache_directorio.escribir_cache(TELEFONO, [])

    assert cache_directorio.leer_cache(TELEFONO) is None


# ---------------------------------------------------------------------------
# Circuit breaker
# ---------------------------------------------------------------------------

def test_el_circuito_se_abre_al_alcanzar_el_umbral(cache_en_memoria, settings):
    """Tras `CIRCUIT_BREAKER_FAILURES` fallos el colegio se salta."""
    settings.CIRCUIT_BREAKER_FAILURES = 2
    circuit_breaker.reiniciar(TENANT)

    assert circuit_breaker.permite_intentar(TENANT) is True
    circuit_breaker.registrar_fallo(TENANT)
    assert circuit_breaker.estado(TENANT) == circuit_breaker.ESTADO_CERRADO

    circuit_breaker.registrar_fallo(TENANT)
    assert circuit_breaker.estado(TENANT) == circuit_breaker.ESTADO_ABIERTO
    assert circuit_breaker.permite_intentar(TENANT) is False


def test_un_exito_cierra_el_circuito(cache_en_memoria, settings):
    """El colegio vuelve y el circuito se cierra en el acto."""
    settings.CIRCUIT_BREAKER_FAILURES = 1
    circuit_breaker.reiniciar(TENANT)
    circuit_breaker.registrar_fallo(TENANT)

    circuit_breaker.registrar_exito(TENANT)

    assert circuit_breaker.estado(TENANT) == circuit_breaker.ESTADO_CERRADO
    assert circuit_breaker.permite_intentar(TENANT) is True


def test_el_semiabierto_deja_pasar_una_sola_sonda(cache_en_memoria, settings):
    """Pasado el enfriamiento se prueba una vez, no una tormenta de conexiones."""
    settings.CIRCUIT_BREAKER_FAILURES = 1
    settings.CIRCUIT_BREAKER_COOLDOWN_SECONDS = 300
    circuit_breaker.reiniciar(TENANT)
    circuit_breaker.registrar_fallo(TENANT)

    # Se simula el fin del enfriamiento borrando solo la marca de apertura.
    cache_en_memoria.delete(circuit_breaker._clave_apertura(TENANT))

    assert circuit_breaker.estado(TENANT) == circuit_breaker.ESTADO_SEMIABIERTO
    assert circuit_breaker.permite_intentar(TENANT) is True
    assert circuit_breaker.permite_intentar(TENANT) is False


@pytest.mark.django_db
def test_un_colegio_con_el_circuito_abierto_cuenta_como_no_verificado(
    colegios, settings, monkeypatch
):
    """Saltarse un colegio no autoriza a decir que el telefono no existe."""
    settings.CIRCUIT_BREAKER_FAILURES = 1
    monkeypatch.setattr(
        "apps.directorio.repositorio.consultar_colegio", lambda tenant, telefono: []
    )
    for tenant_id in colegios:
        circuit_breaker.registrar_fallo(tenant_id)

    with pytest.raises(UpstreamSchoolDbUnavailable):
        services.resolver_vinculos(TELEFONO)


# ---------------------------------------------------------------------------
# Tareas de mantenimiento
# ---------------------------------------------------------------------------

@pytest.mark.django_db
def test_la_reconciliacion_da_de_baja_lo_que_ya_no_existe(colegios, monkeypatch, settings):
    """El job nocturno corrige derivas e invalida la cache de lo afectado."""
    settings.SCHOOL_TENANTS = {TENANT: "Jean Piaget"}
    from apps.directorio import tasks

    Directorio.objects.create(
        telefono="+51900000001",
        tenant_id=TENANT,
        id_estudiante=999,
        codigo_barras="viejo",
        nombre_estudiante="Ya No Esta",
        estado_vinculo="activo",
        # Anterior al `inicio` de la reconciliación (evita empate de timestamps).
        sincronizado_en=timezone.now() - timedelta(hours=1),
    )
    cache_directorio.escribir_cache("+51900000001", [crear_vinculo(telefono="+51900000001")])

    monkeypatch.setattr(
        "apps.directorio.repositorio.iterar_directorio",
        lambda tenant: iter([crear_vinculo()]),
    )

    resumen = tasks.reconciliar_directorio()

    assert resumen["colegios"] == 1
    assert resumen["upserts"] == 1
    assert resumen["bajas"] == 1
    assert Directorio.objects.get(id_estudiante=999).estado_vinculo == VINCULO_INACTIVO
    assert Directorio.objects.get(codigo_barras=DOCUMENTO).estado_vinculo == "activo"
    assert cache_directorio.leer_cache("+51900000001") is None


@pytest.mark.django_db
def test_el_precalentado_carga_la_cache(vinculo_en_directorio):
    """Antes de la jornada la cache queda lista para el pico de logins."""
    from apps.directorio import tasks

    resumen = tasks.precalentar_directorio()

    assert resumen == {"telefonos": 1, "vinculos": 1}
    assert cache_directorio.leer_cache(TELEFONO) is not None


@pytest.mark.django_db
def test_los_vinculos_inactivos_no_habilitan_login(api, vinculo_en_directorio):
    """Un vinculo dado de baja no sirve para entrar."""
    Directorio.objects.update(estado_vinculo=VINCULO_INACTIVO)

    respuesta = api.post(URL_LOGIN, cuerpo_login(), format="json")

    assert respuesta.status_code == 404

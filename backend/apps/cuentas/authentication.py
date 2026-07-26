"""Clases de autenticacion de DRF para los dos tokens del canal.

Cada vista declara explicitamente cual acepta:

* `DataTokenAuthentication` para los endpoints de negocio.
* `SessionTokenAuthentication` para `/auth/refresh-data`, `/auth/renew-session`,
  `/auth/logout` y la aprobacion o rechazo de una transferencia.

Ninguna de las dos hereda de la autenticacion de Django: el canal no usa
`django.contrib.auth`. Ambas dejan en la peticion `request.apoderado` y
`request.sesion`, que es lo que consumen los servicios.

Un token con firma valida pero cuya sesion ya no existe o fue revocada da
`SESSION_EXPIRED` (410), no 401: el cliente distingue "credencial mala" de
"tienes que volver a iniciar sesion".
"""

from __future__ import annotations

import logging

from django.utils import timezone
from rest_framework.authentication import BaseAuthentication

from apps.common.errors import AccountSuspended, SessionExpired, Unauthenticated
from apps.cuentas import tokens
from apps.cuentas.models import (
    CUENTA_ELIMINADA,
    CUENTA_SUSPENDIDA,
    SESION_ACTIVA,
    SESION_EXPIRADA,
    SesionActiva,
)

logger = logging.getLogger("asiscole.cuentas")


class _AutenticacionPorToken(BaseAuthentication):
    """Base comun de las dos clases: cambia solo el tipo de token esperado."""

    #: Valor esperado del claim `typ`.
    tipo_esperado: str = ""

    def authenticate(self, request):
        """Valida el token y devuelve `(apoderado, claims)`.

        Returns:
            `None` si no viene encabezado `Authorization`, para que DRF deje
            actuar al permiso (que denegara por defecto).
        """
        encabezado = request.headers.get("Authorization")
        if not encabezado:
            return None

        crudo = tokens.token_del_encabezado(encabezado)
        claims = tokens.decodificar(crudo, self.tipo_esperado)

        sesion = self._sesion_viva(tokens.identificador_de_sesion(claims))
        apoderado = sesion.apoderado
        self._verificar_cuenta(apoderado)

        request.apoderado = apoderado
        request.sesion = sesion
        request.claims = claims
        return (apoderado, claims)

    def authenticate_header(self, request) -> str:
        """Cabecera `WWW-Authenticate` para que DRF responda 401 y no 403."""
        return "Bearer"

    @staticmethod
    def _sesion_viva(jti: str) -> SesionActiva:
        """Busca la sesion activa que respalda al token.

        Raises:
            SessionExpired: La sesion no existe, fue revocada o ya vencio.
        """
        if not jti:
            raise Unauthenticated()

        try:
            sesion = SesionActiva.objects.select_related("apoderado").get(jti=jti)
        except (SesionActiva.DoesNotExist, ValueError, TypeError) as exc:
            # `jti` no valido como UUID entra por ValueError.
            raise SessionExpired() from exc

        if sesion.estado != SESION_ACTIVA:
            raise SessionExpired()

        if sesion.expira_en <= timezone.now():
            # Se deja constancia del vencimiento para que la sesion no siga
            # ocupando el indice unico parcial.
            SesionActiva.objects.filter(pk=sesion.pk, estado=SESION_ACTIVA).update(
                estado=SESION_EXPIRADA
            )
            raise SessionExpired()

        return sesion

    @staticmethod
    def _verificar_cuenta(apoderado) -> None:
        """Comprueba el estado de la cuenta.

        Raises:
            AccountSuspended: La cuenta esta suspendida (RF-J01).
            Unauthenticated: La cuenta fue eliminada (RF-I06); no se confirma su
                existencia previa.
        """
        if apoderado.estado == CUENTA_SUSPENDIDA:
            # El motivo no viaja en el error: lo entrega `/perfil`, que es donde
            # el contrato lo declara (`Perfil.motivo_suspension`).
            raise AccountSuspended()
        if apoderado.estado == CUENTA_ELIMINADA:
            raise Unauthenticated()


class DataTokenAuthentication(_AutenticacionPorToken):
    """Autenticacion con `data_token`: la de los endpoints de negocio."""

    tipo_esperado = tokens.TIPO_DATOS


class SessionTokenAuthentication(_AutenticacionPorToken):
    """Autenticacion con `session_token`: solo para `/auth/*`."""

    tipo_esperado = tokens.TIPO_SESION

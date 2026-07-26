"""Extensiones de drf-spectacular para los dos esquemas de seguridad del canal.

Sin esto, el esquema generado no sabria describir `DataTokenAuthentication` ni
`SessionTokenAuthentication`, y el documento resultante dejaria de coincidir con
`docs/openapi.yaml`, que es el contrato de verdad.

Los nombres (`dataToken`, `sessionToken`) son exactamente los de
`components.securitySchemes` del contrato.
"""

from __future__ import annotations

from drf_spectacular.extensions import OpenApiAuthenticationExtension


class DataTokenScheme(OpenApiAuthenticationExtension):
    """Describe el `data_token` como `bearer` JWT."""

    target_class = "apps.cuentas.authentication.DataTokenAuthentication"
    name = "dataToken"

    def get_security_definition(self, auto_schema) -> dict:
        """Devuelve la definicion del esquema de seguridad."""
        return {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
            "description": "Token de datos, de vida corta. Es el que usan los endpoints de negocio.",
        }


class SessionTokenScheme(OpenApiAuthenticationExtension):
    """Describe el `session_token` como `bearer` JWT."""

    target_class = "apps.cuentas.authentication.SessionTokenAuthentication"
    name = "sessionToken"

    def get_security_definition(self, auto_schema) -> dict:
        """Devuelve la definicion del esquema de seguridad."""
        return {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
            "description": "Token de sesion, de 10 dias. Solo se usa en los endpoints de `/auth`.",
        }

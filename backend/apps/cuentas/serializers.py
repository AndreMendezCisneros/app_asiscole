"""Serializers de entrada y salida de `/auth/*`.

Los nombres de campo son exactamente los de `docs/openapi.yaml`: el contrato va
primero y ningun cliente consume algo que no este ahi.

Los serializers de entrada solo comprueban forma (presencia y tipo). La
validacion de negocio —que el telefono sea un numero real, que el documento
corresponda al estudiante— vive en los servicios, porque de ella depende que
respuesta del catalogo se devuelve.
"""

from __future__ import annotations

from rest_framework import serializers


class LoginSerializer(serializers.Serializer):
    """Cuerpo de `POST /auth/login`."""

    telefono = serializers.CharField(max_length=32)
    documento_estudiante = serializers.CharField(max_length=50)
    device_id = serializers.CharField(max_length=128)
    modelo = serializers.CharField(max_length=128, required=False, allow_blank=True)
    sistema_operativo = serializers.CharField(max_length=64, required=False, allow_blank=True)
    push_token = serializers.CharField(max_length=512, required=False, allow_blank=True)
    plataforma = serializers.ChoiceField(
        choices=["android", "ios"], required=False, allow_blank=True
    )
    alias = serializers.CharField(max_length=128, required=False, allow_blank=True)
    acepta_terminos = serializers.BooleanField()
    terminos_version = serializers.CharField(max_length=32)


class AdminLoginSerializer(serializers.Serializer):
    """Cuerpo de `POST /auth/admin/login`."""

    usuario = serializers.CharField(max_length=50)
    password = serializers.CharField(max_length=256, trim_whitespace=False)
    device_id = serializers.CharField(max_length=128)
    tenant_id = serializers.CharField(max_length=64)


class SolicitudTransferenciaSerializer(serializers.Serializer):
    """Cuerpo de `POST /auth/session-transfer/request`."""

    telefono = serializers.CharField(max_length=32)
    documento_estudiante = serializers.CharField(max_length=50)
    device_id = serializers.CharField(max_length=128)


class PerfilSerializer(serializers.Serializer):
    """Esquema `Perfil` del contrato."""

    alias = serializers.CharField(allow_null=True)
    telefono = serializers.CharField(help_text="Enmascarado, por ejemplo +51*****321")
    estado = serializers.CharField()
    motivo_suspension = serializers.CharField(allow_null=True)
    estudiante_activo_id = serializers.IntegerField(allow_null=True)
    terminos_version = serializers.CharField(allow_null=True)
    terminos_aceptados_en = serializers.DateTimeField(allow_null=True)


class SesionCreadaSerializer(serializers.Serializer):
    """Esquema `SesionCreada` del contrato."""

    session_token = serializers.CharField()
    session_expira_en = serializers.DateTimeField()
    data_token = serializers.CharField()
    data_expira_en = serializers.DateTimeField()
    perfil = PerfilSerializer()


class DataTokenSerializer(serializers.Serializer):
    """Esquema `DataToken` del contrato."""

    data_token = serializers.CharField()
    data_expira_en = serializers.DateTimeField()


class SolicitudTransferenciaRespuestaSerializer(serializers.Serializer):
    """Esquema `SolicitudTransferencia` del contrato.

    El `id` viaja como cadena porque el contrato lo declara `string`. La PK de
    `asis_transferencia_sesion` es un BIGSERIAL, asi que se serializa su valor
    en texto. `token_consulta` solo se conoce al crear la solicitud.
    """

    id = serializers.SerializerMethodField()
    estado = serializers.CharField()
    expira_en = serializers.DateTimeField()
    token_consulta = serializers.CharField(allow_null=True, required=False)

    def get_id(self, obj) -> str:
        """Devuelve el identificador de la solicitud como cadena."""
        return str(obj.pk)

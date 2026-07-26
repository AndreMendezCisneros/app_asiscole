"""Vistas de `/auth/*`.

Son deliberadamente delgadas: validan la forma con un serializer, delegan en
`apps.cuentas.services` y serializan la respuesta. Toda decision de negocio y
todo error del catalogo salen del servicio.

Cada vista declara que token acepta. Esa eleccion es parte de la seguridad del
canal: `/auth/renew-session` solo admite `session_token`, y un `data_token`
—aunque sea valido y de la misma sesion— se rechaza.
"""

from __future__ import annotations

from drf_spectacular.utils import OpenApiResponse, extend_schema
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.permissions import PermitirSinToken
from apps.cuentas import services, tokens
from apps.cuentas.authentication import SessionTokenAuthentication
from apps.cuentas.permissions import EsApoderadoConSessionToken
from apps.cuentas.serializers import (
    AdminLoginSerializer,
    DataTokenSerializer,
    LoginSerializer,
    SesionCreadaSerializer,
    SolicitudTransferenciaRespuestaSerializer,
    SolicitudTransferenciaSerializer,
)


def _ip_de(request: Request) -> str | None:
    """Devuelve la IP de origen, respetando el proxy inverso.

    La IP es un dato personal: se usa para contar intentos y se guarda hasheada
    en las claves de la cache; nunca se escribe en un log.
    """
    reenviada = request.headers.get("X-Forwarded-For", "")
    if reenviada:
        return reenviada.split(",")[0].strip()
    return request.META.get("REMOTE_ADDR")


def _token_de_sesion(request: Request) -> str:
    """Extrae el `session_token` en crudo del encabezado Authorization."""
    return tokens.token_del_encabezado(request.headers.get("Authorization"))


def _datos_validados(serializer_cls, request: Request) -> dict:
    """Valida el cuerpo de la peticion.

    El `raise_exception` acaba en `ValidationError` del catalogo gracias al
    manejador de excepciones: nunca se devuelve el detalle del serializer, que
    podria contener el telefono o el documento rechazados.
    """
    serializer = serializer_cls(data=request.data)
    serializer.is_valid(raise_exception=True)
    return serializer.validated_data


#: Respuestas de error del catalogo, reutilizadas en la documentacion.
_SIN_CUERPO = OpenApiResponse(description="Operación realizada")


class LoginView(APIView):
    """`POST /v0.1/auth/login` — RF-A01 a RF-A05."""

    authentication_classes: list = []
    permission_classes = [PermitirSinToken]

    @extend_schema(
        tags=["auth"],
        request=LoginSerializer,
        responses={200: SesionCreadaSerializer},
        auth=[],
    )
    def post(self, request: Request) -> Response:
        """Valida la credencial, crea la sesion y emite los dos tokens."""
        datos = _datos_validados(LoginSerializer, request)
        sesion = services.login(
            telefono=datos["telefono"],
            documento=datos["documento_estudiante"],
            device_id=datos["device_id"],
            modelo=datos.get("modelo") or None,
            sistema_operativo=datos.get("sistema_operativo") or None,
            push_token=datos.get("push_token") or None,
            plataforma=datos.get("plataforma") or None,
            alias=datos.get("alias") or None,
            ip=_ip_de(request),
        )
        return Response(SesionCreadaSerializer(sesion).data)


class AdminLoginView(APIView):
    """`POST /v0.1/auth/admin/login` — RF-B01."""

    authentication_classes: list = []
    permission_classes = [PermitirSinToken]

    def post(self, request: Request) -> Response:
        """Valida usuario y contrasena contra la tabla `usuarios` del colegio."""
        datos = _datos_validados(AdminLoginSerializer, request)
        sesion = services.login_administrador(
            usuario=datos["usuario"],
            password=datos["password"],
            device_id=datos["device_id"],
            tenant_id=datos["tenant_id"],
            ip=_ip_de(request),
        )
        return Response(SesionCreadaSerializer(sesion).data)


class RefreshDataView(APIView):
    """`POST /v0.1/auth/refresh-data` — token de datos nuevo sin volver a entrar."""

    authentication_classes = [SessionTokenAuthentication]
    permission_classes = [EsApoderadoConSessionToken]

    def post(self, request: Request) -> Response:
        """Emite un `data_token` nuevo a partir del `session_token`."""
        emitido = services.refresh_data(_token_de_sesion(request))
        return Response(DataTokenSerializer(emitido).data)


class RenewSessionView(APIView):
    """`POST /v0.1/auth/renew-session` — RF-A07."""

    authentication_classes = [SessionTokenAuthentication]
    permission_classes = [EsApoderadoConSessionToken]

    def post(self, request: Request) -> Response:
        """Rota el token de sesion si esta dentro de la ventana de renovacion."""
        sesion = services.renovar_sesion(_token_de_sesion(request))
        return Response(SesionCreadaSerializer(sesion).data)


class LogoutView(APIView):
    """`POST /v0.1/auth/logout` — CU-07."""

    authentication_classes = [SessionTokenAuthentication]
    permission_classes = [EsApoderadoConSessionToken]

    def post(self, request: Request) -> Response:
        """Invalida la sesion y desactiva el push del dispositivo."""
        services.logout(request.sesion)
        return Response(status=204)


class SolicitarTransferenciaView(APIView):
    """`POST /v0.1/auth/session-transfer/request` — RF-A09."""

    authentication_classes: list = []
    permission_classes = [PermitirSinToken]

    def post(self, request: Request) -> Response:
        """Crea la solicitud de traspaso y avisa al dispositivo activo."""
        datos = _datos_validados(SolicitudTransferenciaSerializer, request)
        transferencia = services.solicitar_transferencia(
            telefono=datos["telefono"],
            documento=datos["documento_estudiante"],
            device_id=datos["device_id"],
            ip=_ip_de(request),
        )
        return Response(
            SolicitudTransferenciaRespuestaSerializer(transferencia).data, status=202
        )


class AprobarTransferenciaView(APIView):
    """`POST /v0.1/auth/session-transfer/{id}/approve` — RF-A09."""

    authentication_classes = [SessionTokenAuthentication]
    permission_classes = [EsApoderadoConSessionToken]

    def post(self, request: Request, id: int) -> Response:
        """Cierra la sesion actual y habilita al dispositivo solicitante."""
        services.aprobar_transferencia(id, request.sesion)
        return Response(status=204)


class RechazarTransferenciaView(APIView):
    """`POST /v0.1/auth/session-transfer/{id}/reject` — RF-A09."""

    authentication_classes = [SessionTokenAuthentication]
    permission_classes = [EsApoderadoConSessionToken]

    def post(self, request: Request, id: int) -> Response:
        """Rechaza el traspaso; la sesion actual sigue intacta."""
        services.rechazar_transferencia(id, request.sesion)
        return Response(status=204)


class ConsultarTransferenciaView(APIView):
    """`GET /v0.1/auth/session-transfer/{id}` — estado de la solicitud."""

    authentication_classes: list = []
    permission_classes = [PermitirSinToken]

    def get(self, request: Request, id: int) -> Response:
        """Devuelve el estado para que el dispositivo nuevo sepa si ya puede entrar."""
        transferencia = services.consultar_transferencia(id)
        return Response(SolicitudTransferenciaRespuestaSerializer(transferencia).data)

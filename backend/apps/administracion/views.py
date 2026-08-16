"""Vistas de administración y feature flags."""

from __future__ import annotations

from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import serializers
from rest_framework.permissions import BasePermission
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.administracion import services
from apps.common.permissions import PermitirSinToken
from apps.common.red import ip_de
from apps.cuentas import rate_limit
from apps.cuentas.authentication import DataTokenAuthentication
from apps.cuentas.permissions import EsAdministrador


class ConDataToken(BasePermission):
    """Cualquier sesión viva con data_token (apoderado o admin)."""

    def has_permission(self, request, view) -> bool:
        from apps.cuentas import tokens

        return (
            getattr(request, "apoderado", None) is not None
            and getattr(request, "sesion", None) is not None
            and (getattr(request, "claims", None) or {}).get("typ") == tokens.TIPO_DATOS
        )


class SuspenderSerializer(serializers.Serializer):
    motivo = serializers.CharField(min_length=5)
    notificar_push = serializers.BooleanField(default=True, required=False)


class AvisoSerializer(serializers.Serializer):
    texto = serializers.CharField(min_length=1)
    nivel = serializers.ChoiceField(
        choices=["Primaria", "Secundaria"], required=False, allow_null=True
    )
    grado = serializers.CharField(required=False, allow_null=True, allow_blank=True)
    seccion = serializers.CharField(required=False, allow_null=True, allow_blank=True)


class FeatureFlagsView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [ConDataToken]

    @extend_schema(tags=["sistema"])
    def get(self, request: Request) -> Response:
        return Response(services.listar_flags())


class VersionAppView(APIView):
    """`GET /sistema/version-app`: politica de versiones (Fase 7).

    Sin autenticacion: la app la consulta antes de tener sesion, y una version
    con un fallo grave debe poder cortarse aunque el login este roto.
    """

    authentication_classes: list = []
    permission_classes = [PermitirSinToken]

    #: Consultas por IP y hora. Generoso: la app pregunta una vez por arranque.
    MAX_POR_IP = 60
    VENTANA_SEGUNDOS = 3600

    @extend_schema(
        tags=["sistema"],
        parameters=[
            OpenApiParameter("plataforma", str, required=True),
            OpenApiParameter(
                "X-App-Version",
                int,
                OpenApiParameter.HEADER,
                required=False,
                description="versionCode instalado.",
            ),
        ],
    )
    def get(self, request: Request) -> Response:
        rate_limit.verificar_publico_por_ip(
            "version_app",
            ip_de(request),
            maximo=self.MAX_POR_IP,
            ventana=self.VENTANA_SEGUNDOS,
        )
        return Response(
            services.politica_version_app(
                request.query_params.get("plataforma", ""),
                _version_instalada(request),
            )
        )


def _version_instalada(request: Request) -> int | None:
    """Lee `X-App-Version`. Una cabecera ilegible se trata como ausente."""
    crudo = request.headers.get("X-App-Version")
    if not crudo:
        return None
    try:
        version = int(str(crudo).strip())
    except (TypeError, ValueError):
        return None
    return version if version > 0 else None


class ApoderadosAdminView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsAdministrador]

    @extend_schema(
        tags=["admin"],
        parameters=[
            OpenApiParameter("buscar", str, required=False),
            OpenApiParameter("estado", str, required=False),
            OpenApiParameter("cursor", str, required=False),
        ],
    )
    def get(self, request: Request) -> Response:
        tenant_id = services.tenant_del_admin(request.apoderado)
        return Response(
            services.listar_apoderados(
                tenant_id=tenant_id,
                buscar=request.query_params.get("buscar"),
                estado=request.query_params.get("estado"),
                cursor=request.query_params.get("cursor"),
            )
        )


class SuspenderView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsAdministrador]

    @extend_schema(tags=["admin"], request=SuspenderSerializer, responses={204: None})
    def post(self, request: Request, id: int) -> Response:
        ser = SuspenderSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        tenant_id = services.tenant_del_admin(request.apoderado)
        services.suspender_cuenta(
            id,
            motivo=ser.validated_data["motivo"],
            actor=f"admin:{request.apoderado.pk}",
            tenant_id=tenant_id,
            notificar_push=ser.validated_data.get("notificar_push", True),
        )
        return Response(status=204)


class ReactivarView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsAdministrador]

    @extend_schema(tags=["admin"], responses={204: None})
    def post(self, request: Request, id: int) -> Response:
        tenant_id = services.tenant_del_admin(request.apoderado)
        services.reactivar_cuenta(
            id, actor=f"admin:{request.apoderado.pk}", tenant_id=tenant_id
        )
        return Response(status=204)


class CerrarSesionView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsAdministrador]

    @extend_schema(tags=["admin"], responses={204: None})
    def post(self, request: Request, id: int) -> Response:
        tenant_id = services.tenant_del_admin(request.apoderado)
        services.cerrar_sesion_cuenta(
            id, actor=f"admin:{request.apoderado.pk}", tenant_id=tenant_id
        )
        return Response(status=204)


class AvisosView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsAdministrador]

    @extend_schema(tags=["admin"], request=AvisoSerializer)
    def post(self, request: Request) -> Response:
        ser = AvisoSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        tenant_id = services.tenant_del_admin(request.apoderado)
        datos = services.enviar_aviso(
            tenant_id=tenant_id, **ser.validated_data
        )
        return Response(datos, status=202)

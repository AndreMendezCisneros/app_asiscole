"""Vistas de administración y feature flags."""

from __future__ import annotations

from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import serializers
from rest_framework.permissions import BasePermission
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.administracion import services
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
        return Response(
            services.listar_apoderados(
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
        services.suspender_cuenta(
            id,
            motivo=ser.validated_data["motivo"],
            actor=f"admin:{request.apoderado.pk}",
            notificar_push=ser.validated_data.get("notificar_push", True),
        )
        return Response(status=204)


class ReactivarView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsAdministrador]

    @extend_schema(tags=["admin"], responses={204: None})
    def post(self, request: Request, id: int) -> Response:
        services.reactivar_cuenta(id, actor=f"admin:{request.apoderado.pk}")
        return Response(status=204)


class CerrarSesionView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsAdministrador]

    @extend_schema(tags=["admin"], responses={204: None})
    def post(self, request: Request, id: int) -> Response:
        services.cerrar_sesion_cuenta(id, actor=f"admin:{request.apoderado.pk}")
        return Response(status=204)


class AvisosView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsAdministrador]

    @extend_schema(tags=["admin"], request=AvisoSerializer)
    def post(self, request: Request) -> Response:
        ser = AvisoSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        datos = services.enviar_aviso(**ser.validated_data)
        return Response(datos, status=202)

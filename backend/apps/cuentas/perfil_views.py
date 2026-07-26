"""Vistas de perfil del apoderado."""

from __future__ import annotations

from drf_spectacular.utils import extend_schema
from rest_framework import serializers
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.cuentas import perfil_services
from apps.cuentas.authentication import DataTokenAuthentication
from apps.cuentas.permissions import EsApoderadoConDataToken
from apps.cuentas.serializers import PerfilSerializer


class ActualizarPerfilSerializer(serializers.Serializer):
    alias = serializers.CharField(required=False, allow_blank=True, allow_null=True)
    estudiante_activo_id = serializers.IntegerField(required=False, allow_null=True)


class VincularSerializer(serializers.Serializer):
    documento_estudiante = serializers.CharField(max_length=50)


class PushTokenSerializer(serializers.Serializer):
    token = serializers.CharField()
    plataforma = serializers.ChoiceField(choices=["android", "ios"])


class EliminarCuentaSerializer(serializers.Serializer):
    documento_estudiante = serializers.CharField(max_length=50)


class PerfilView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsApoderadoConDataToken]

    @extend_schema(tags=["perfil"], responses={200: PerfilSerializer})
    def get(self, request: Request) -> Response:
        return Response(perfil_services.obtener_perfil(request.apoderado))

    @extend_schema(tags=["perfil"], request=ActualizarPerfilSerializer, responses={200: PerfilSerializer})
    def patch(self, request: Request) -> Response:
        ser = ActualizarPerfilSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        return Response(perfil_services.actualizar_perfil(request.apoderado, **ser.validated_data))


class EstudiantesView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsApoderadoConDataToken]

    @extend_schema(tags=["perfil"])
    def get(self, request: Request) -> Response:
        return Response(perfil_services.listar_estudiantes(request.apoderado))


class VincularEstudianteView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsApoderadoConDataToken]

    @extend_schema(tags=["perfil"], request=VincularSerializer)
    def post(self, request: Request) -> Response:
        ser = VincularSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        datos = perfil_services.vincular_estudiante(
            request.apoderado, ser.validated_data["documento_estudiante"]
        )
        return Response(datos, status=201)


class PushTokenView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsApoderadoConDataToken]

    @extend_schema(tags=["perfil"], request=PushTokenSerializer, responses={204: None})
    def put(self, request: Request) -> Response:
        ser = PushTokenSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        perfil_services.registrar_push_token(
            request.apoderado,
            request.sesion,
            token=ser.validated_data["token"],
            plataforma=ser.validated_data["plataforma"],
        )
        return Response(status=204)


class EliminarCuentaView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsApoderadoConDataToken]

    @extend_schema(tags=["perfil"], request=EliminarCuentaSerializer, responses={204: None})
    def post(self, request: Request) -> Response:
        ser = EliminarCuentaSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        perfil_services.eliminar_cuenta(
            request.apoderado, ser.validated_data["documento_estudiante"]
        )
        return Response(status=204)

"""Vista HTTP de ingesta de eventos desde Asiscole."""

from __future__ import annotations

from drf_spectacular.utils import extend_schema
from rest_framework import serializers
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.ingesta.authentication import IngestApiKeyAuthentication
from apps.ingesta.http_services import recibir_evento
from apps.ingesta.permissions import EsIngestAutenticado


class EventoIngestaSerializer(serializers.Serializer):
    tenant_id = serializers.CharField(max_length=100)
    tipo = serializers.ChoiceField(choices=["entrada", "salida", "incidencia", "aviso"])
    id_estudiante = serializers.IntegerField(min_value=1)
    id_registro = serializers.IntegerField(min_value=1)
    payload = serializers.JSONField()

    def validate_payload(self, value):
        if not isinstance(value, dict):
            raise serializers.ValidationError("payload debe ser un objeto JSON.")
        return value



class EventoIngestaView(APIView):
    authentication_classes = [IngestApiKeyAuthentication]
    permission_classes = [EsIngestAutenticado]

    @extend_schema(
        tags=["ingesta"],
        request=EventoIngestaSerializer,
        responses={202: dict},
    )
    def post(self, request: Request) -> Response:
        ser = EventoIngestaSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        datos = recibir_evento(**ser.validated_data)
        return Response(datos, status=202)

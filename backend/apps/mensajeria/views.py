"""Vistas de `/mensajes`."""

from __future__ import annotations

from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.cuentas.authentication import DataTokenAuthentication
from apps.cuentas.permissions import EsApoderadoConDataToken
from apps.mensajeria import services
from apps.mensajeria.serializers import BandejaSerializer, MarcarLeidosSerializer


class MensajesView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsApoderadoConDataToken]

    @extend_schema(
        tags=["mensajes"],
        parameters=[
            OpenApiParameter("since", str, required=False),
            OpenApiParameter("cursor", str, required=False),
            OpenApiParameter("limit", int, required=False),
            OpenApiParameter("tipo", str, required=False),
        ],
        responses={200: BandejaSerializer},
    )
    def get(self, request: Request) -> Response:
        datos = services.listar_mensajes(
            request.apoderado,
            since=request.query_params.get("since"),
            cursor=request.query_params.get("cursor"),
            limit=int(request.query_params.get("limit") or 50),
            tipo=request.query_params.get("tipo"),
        )
        return Response(BandejaSerializer(datos).data)


class MensajesLeidosView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsApoderadoConDataToken]

    @extend_schema(tags=["mensajes"], request=MarcarLeidosSerializer, responses={204: None})
    def post(self, request: Request) -> Response:
        serializer = MarcarLeidosSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.marcar_leidos(
            request.apoderado,
            [str(i) for i in serializer.validated_data["ids"]],
        )
        return Response(status=204)

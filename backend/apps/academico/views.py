"""Vistas de asistencias e incidencias."""

from __future__ import annotations

from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.academico import services
from apps.common.errors import ValidationError
from apps.cuentas.authentication import DataTokenAuthentication
from apps.cuentas.permissions import EsApoderadoConDataToken


def _estudiante_id(request: Request) -> int:
    crudo = request.query_params.get("estudiante_id")
    if crudo is None or not str(crudo).isdigit():
        raise ValidationError("Debes indicar el estudiante_id.")
    return int(crudo)


class AsistenciasView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsApoderadoConDataToken]

    @extend_schema(
        tags=["asistencias"],
        parameters=[
            OpenApiParameter("estudiante_id", int, required=True),
            OpenApiParameter("anio", int, required=True),
            OpenApiParameter("mes", int, required=True),
        ],
    )
    def get(self, request: Request) -> Response:
        try:
            anio = int(request.query_params["anio"])
            mes = int(request.query_params["mes"])
        except (KeyError, ValueError, TypeError) as exc:
            raise ValidationError("Debes indicar anio y mes válidos.") from exc
        return Response(
            services.agenda_mensual(
                request.apoderado,
                estudiante_id=_estudiante_id(request),
                anio=anio,
                mes=mes,
            )
        )


class IncidenciasView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsApoderadoConDataToken]

    @extend_schema(tags=["incidencias"])
    def get(self, request: Request) -> Response:
        return Response(
            services.listar_incidencias(
                request.apoderado,
                estudiante_id=_estudiante_id(request),
                desde=request.query_params.get("desde"),
                hasta=request.query_params.get("hasta"),
            )
        )


class IncidenciaDetalleView(APIView):
    authentication_classes = [DataTokenAuthentication]
    permission_classes = [EsApoderadoConDataToken]

    @extend_schema(tags=["incidencias"])
    def get(self, request: Request, id: int) -> Response:
        return Response(
            services.detalle_incidencia(
                request.apoderado,
                incidencia_id=id,
                estudiante_id=_estudiante_id(request),
            )
        )

"""Serializers de mensajería."""

from __future__ import annotations

from rest_framework import serializers

from apps.mensajeria.models import CODIGOS_TIPO_MENSAJE


class MensajeSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    tipo = serializers.ChoiceField(choices=CODIGOS_TIPO_MENSAJE)
    texto = serializers.CharField()
    colegio = serializers.CharField()
    estudiante_id = serializers.IntegerField(allow_null=True)
    estudiante_nombre = serializers.CharField(allow_null=True, required=False)
    emitido_en = serializers.DateTimeField()
    entregado = serializers.BooleanField()
    leido = serializers.BooleanField()
    metadata = serializers.DictField(required=False)


class BandejaSerializer(serializers.Serializer):
    items = MensajeSerializer(many=True)
    next_cursor = serializers.CharField(allow_null=True)
    no_leidos_por_canal = serializers.DictField(child=serializers.IntegerField())


class MarcarLeidosSerializer(serializers.Serializer):
    ids = serializers.ListField(
        child=serializers.UUIDField(),
        allow_empty=False,
        max_length=200,
    )

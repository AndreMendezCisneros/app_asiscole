---
name: asiscole-plantilla-mensaje
description: Añade o modifica un tipo de mensaje y su plantilla en el backend de Asiscole sin necesidad de publicar una versión nueva de la app. Se usa al crear avisos, tipos de evento o cambiar el texto que recibe el apoderado.
disable-model-invocation: true
---

# Plantilla de mensaje nueva

Todo el texto que ve el apoderado lo produce el backend. Añadir un tipo de mensaje nunca
debe obligar a tocar la app.

## Pasos

```
- [ ] 1. Añadir el tipo al enum de asis_mensaje
- [ ] 2. Crear la estrategia de plantilla
- [ ] 3. Registrarla en el registry
- [ ] 4. Conectar el disparador (outbox o acción de administrador)
- [ ] 5. Test del texto renderizado
```

## Estrategia

Cada tipo es una clase con la misma interfaz, en `apps/mensajeria/plantillas/`:

```python
class PlantillaEntrada(PlantillaBase):
    tipo = "entrada"

    def render(self, ctx: ContextoEvento) -> str:
        hora = ctx.hora.strftime("%H:%M")
        return f"{ctx.estudiante_nombre} ingresó al colegio a las {hora}."
```

`ContextoEvento` trae ya resueltos el estudiante, el colegio y los datos del evento. La
plantilla no consulta la base de datos.

## Registro

```python
REGISTRO_PLANTILLAS = {
    "entrada": PlantillaEntrada,
    "salida": PlantillaSalida,
    "incidencia": PlantillaIncidencia,
    "aviso": PlantillaAviso,
    "personalizado": PlantillaPersonalizada,
}
```

Un tipo sin plantilla registrada hace fallar la tarea de forma explícita en lugar de
enviar un mensaje vacío.

## Estilo del texto

Español de Perú, tuteo evitado, sin emojis. Fecha y hora en la zona del colegio. Una o dos
frases: el mensaje se lee en una notificación push.

## Test

```python
def test_plantilla_entrada_incluye_hora():
    texto = PlantillaEntrada().render(ctx_entrada(hora=time(7, 45)))
    assert "07:45" in texto
```

---
name: asiscole-endpoint
description: Añade un endpoint nuevo a la API del canal Asiscole siguiendo el contrato OpenAPI, el catálogo de errores y las pruebas de autorización. Se usa al crear o modificar rutas en backend/apps.
disable-model-invocation: true
---

# Endpoint nuevo en el backend de Asiscole

## Orden de trabajo

El contrato va primero. Nunca se implementa una vista que no esté descrita en
`docs/openapi.yaml`.

```
- [ ] 1. Declarar la ruta y los esquemas en docs/openapi.yaml
- [ ] 2. Serializer de entrada y de salida
- [ ] 3. Servicio con la lógica; repositorio si toca la BD de un colegio
- [ ] 4. Vista delgada + permiso
- [ ] 5. Errores del catálogo
- [ ] 6. Tests: caso feliz + autorización negativa
```

## 1. Contrato

Ruta bajo `/v0.1/`. Documentar todos los códigos de error que la vista puede emitir.

## 2 a 4. Implementación

La vista solo valida, delega y serializa:

```python
class MisEstudiantesView(APIView):
    permission_classes = [EsApoderadoConDataToken]

    def get(self, request):
        estudiantes = perfil_service.listar_estudiantes(request.apoderado)
        return Response(EstudianteSerializer(estudiantes, many=True).data)
```

El permiso `EsApoderadoConDataToken` exige un `data_token` válido cuyo `sid` apunte a una
sesión activa. Para rutas de administración se usa `EsAdministrador`.

## 5. Errores

Se lanzan excepciones del catálogo, nunca `Response(status=...)` con texto libre:

```python
from apps.common.errors import StudentLinkNotFound, RoleNotAllowed
```

## 6. Tests obligatorios

Además del caso feliz, todo endpoint que reciba un identificador de estudiante necesita
un test que intente acceder al estudiante de otro apoderado y espere 403:

```python
def test_no_puede_ver_estudiante_ajeno(client, apoderado_a, estudiante_de_b):
    r = client.get(f"/v0.1/asistencias/{estudiante_de_b.id}", **auth(apoderado_a))
    assert r.status_code == 403
    assert r.json()["code"] == "ROLE_NOT_ALLOWED"
```

## Recordatorios

- Nunca loguear teléfono ni `codigo_barras` (ver la regla de datos de menores).
- El acceso a un estudiante se valida contra el directorio, no contra el input.

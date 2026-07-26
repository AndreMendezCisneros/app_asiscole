---
name: asiscole-feature-flutter
description: Crea una feature nueva en la app Flutter de Asiscole con BLoC, repositorio y caché offline según las convenciones del proyecto. Se usa al añadir pantallas o flujos a frontend/mobile.
disable-model-invocation: true
---

# Feature nueva en la app Flutter

## Estructura

```
lib/features/<feature>/
├── data/
│   ├── <feature>_api.dart          llamadas HTTP
│   ├── <feature>_local_source.dart caché local (solo si aplica)
│   └── <feature>_repository.dart   une remoto y local
├── domain/<modelo>.dart
└── presentation/
    ├── <feature>_cubit.dart
    ├── <feature>_state.dart
    └── <feature>_page.dart
```

## Decidir la política offline

Solo mensajes se lee sin conexión. Para el resto, el repositorio propaga el fallo de red
y la pantalla muestra estado vacío o de error.

```dart
// Mensajes: cae a caché
Future<List<Mensaje>> obtener() async {
  try {
    final remotos = await _api.listar(since: await _local.ultimaFecha());
    await _local.guardar(remotos);
    return _local.todos();
  } on SinConexion {
    return _local.todos();
  }
}

// Asistencias: no inventa datos
Future<List<Asistencia>> delMes(int anio, int mes) => _api.listarMes(anio, mes);
```

## Estado

Estados sellados con `sealed class`, sin banderas booleanas sueltas:

```dart
sealed class AsistenciaState {}
class AsistenciaCargando extends AsistenciaState {}
class AsistenciaLista extends AsistenciaState { final List<Asistencia> dias; ... }
class AsistenciaSinConexion extends AsistenciaState {}
class AsistenciaError extends AsistenciaState { final String codigo; ... }
```

El `codigo` proviene del catálogo de errores de la API, para que la UI reaccione al código
y no al texto.

## Registro

El repositorio se registra en el inyector de dependencias y la ruta en el router. El cubit
recibe el repositorio por constructor, nunca lo instancia.

## Contexto de estudiante activo

Cualquier feature que muestre datos académicos filtra por el estudiante activo global.
No se guarda una copia local del identificador dentro de la feature.

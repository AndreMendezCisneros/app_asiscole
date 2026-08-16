import 'package:asiscole_app/features/mensajes/data/mensajes_repository.dart';
import 'package:asiscole_app/features/mensajes/domain/mensaje.dart';
import 'package:asiscole_app/features/mensajes/presentation/mensajes_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MensajesRepositoryMock extends Mock implements MensajesRepository {}

Mensaje _mensaje(String id, {bool leido = false}) => Mensaje(
      id: id,
      tipo: 'entrada',
      texto: 'Mensaje $id',
      emitidoEn: DateTime.utc(2026, 7, 27, 12, 30),
      leido: leido,
    );

void main() {
  late MensajesRepositoryMock repo;

  setUp(() => repo = MensajesRepositoryMock());

  group('MensajesCubit — carga', () {
    blocTest<MensajesCubit, MensajesState>(
      'con red muestra lo que devuelve la sincronización',
      setUp: () {
        when(repo.soloCache).thenAnswer((_) async => []);
        when(repo.sincronizar).thenAnswer((_) async => [_mensaje('a')]);
      },
      build: () => MensajesCubit(repo),
      act: (cubit) => cubit.cargar(),
      verify: (cubit) {
        final estado = cubit.state as MensajesListos;
        expect(estado.offline, isFalse);
        expect(estado.items.single.id, 'a');
      },
    );

    blocTest<MensajesCubit, MensajesState>(
      'si la sincronización falla, cae a la caché y marca offline',
      setUp: () {
        when(repo.soloCache).thenAnswer((_) async => [_mensaje('cacheado')]);
        when(repo.sincronizar).thenThrow(Exception('sin red'));
      },
      build: () => MensajesCubit(repo),
      act: (cubit) => cubit.cargar(),
      verify: (cubit) {
        final estado = cubit.state as MensajesListos;
        expect(estado.offline, isTrue);
        expect(estado.items.single.id, 'cacheado');
      },
    );

    blocTest<MensajesCubit, MensajesState>(
      'sin red y sin caché informa el error',
      setUp: () {
        when(repo.soloCache).thenThrow(Exception('base local caída'));
        when(repo.sincronizar).thenThrow(Exception('sin red'));
      },
      build: () => MensajesCubit(repo),
      act: (cubit) => cubit.cargar(),
      verify: (cubit) => expect(cubit.state, isA<MensajesError>()),
    );

    blocTest<MensajesCubit, MensajesState>(
      'pinta la caché antes de esperar a la red',
      setUp: () {
        when(repo.soloCache).thenAnswer((_) async => [_mensaje('cacheado')]);
        when(repo.sincronizar).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return [_mensaje('cacheado'), _mensaje('nuevo')];
        });
      },
      build: () => MensajesCubit(repo),
      act: (cubit) => cubit.cargar(),
      expect: () => [
        isA<MensajesListos>()
            .having((e) => e.items.length, 'solo la caché', 1),
        isA<MensajesListos>()
            .having((e) => e.items.length, 'caché + servidor', 2),
      ],
    );
  });

  group('MensajesCubit — marcar leído', () {
    blocTest<MensajesCubit, MensajesState>(
      'con la red caída el mensaje igual se ve leído',
      setUp: () {
        when(repo.soloCache).thenAnswer((_) async => []);
        when(repo.sincronizar).thenAnswer((_) async => [_mensaje('a')]);
        // El repositorio encola el acuse; aquí se simula el peor caso: revienta.
        when(() => repo.marcarLeidos(['a'])).thenThrow(Exception('sin red'));
      },
      build: () => MensajesCubit(repo),
      act: (cubit) async {
        await cubit.cargar();
        await cubit.abrir(_mensaje('a'));
      },
      verify: (cubit) {
        final estado = cubit.state as MensajesListos;
        expect(estado.items.single.leido, isTrue);
        verify(() => repo.marcarLeidos(['a'])).called(1);
      },
    );

    blocTest<MensajesCubit, MensajesState>(
      'un mensaje ya leído no vuelve a llamar al API',
      setUp: () {
        when(repo.soloCache).thenAnswer((_) async => []);
        when(repo.sincronizar)
            .thenAnswer((_) async => [_mensaje('a', leido: true)]);
      },
      build: () => MensajesCubit(repo),
      act: (cubit) async {
        await cubit.cargar();
        await cubit.abrir(_mensaje('a', leido: true));
      },
      verify: (_) => verifyNever(() => repo.marcarLeidos(any())),
    );
  });
}

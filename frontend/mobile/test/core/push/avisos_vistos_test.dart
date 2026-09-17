import 'package:asiscole_app/core/push/avisos_vistos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('el primer aviso se muestra y el repetido no', () async {
    expect(await AvisosVistos.yaMostrado('msg-1'), isFalse);
    expect(await AvisosVistos.yaMostrado('msg-1'), isTrue);
  });

  test('avisos distintos no se pisan', () async {
    expect(await AvisosVistos.yaMostrado('msg-1'), isFalse);
    expect(await AvisosVistos.yaMostrado('msg-2'), isFalse);
    expect(await AvisosVistos.yaMostrado('msg-1'), isTrue);
  });

  test('sin message_id nunca se considera repetido', () async {
    expect(await AvisosVistos.yaMostrado(''), isFalse);
    expect(await AvisosVistos.yaMostrado(''), isFalse);
  });

  test('un aviso más viejo que la ventana se olvida', () async {
    final viejo = DateTime.now()
        .subtract(AvisosVistos.ventana + const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'push_vistos_v1': <String>['msg-viejo|$viejo'],
    });

    expect(await AvisosVistos.yaMostrado('msg-viejo'), isFalse);
  });

  test('el id de la bandeja es estable para el mismo mensaje', () {
    final primero = AvisosVistos.idNotificacion('msg-1', respaldo: 11);
    final segundo = AvisosVistos.idNotificacion('msg-1', respaldo: 22);

    expect(primero, segundo);
    expect(primero, greaterThanOrEqualTo(0));
  });

  test('sin message_id cae al respaldo y sigue siendo positivo', () {
    expect(AvisosVistos.idNotificacion('', respaldo: -7), greaterThanOrEqualTo(0));
  });
}

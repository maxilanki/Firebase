import 'dart:async';

import 'package:appfirebase/users_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('creates, edits, and deletes a user', (tester) async {
    final repository = _FakeUsersRepository();
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      MaterialApp(home: UsersPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Aún no hay usuarios. Agrega el primero.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Agregar usuario'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre'), 'Ada');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo'),
      'ada@example.com',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('ada@example.com'), findsOneWidget);

    await tester.tap(find.byTooltip('Editar usuario'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre'),
      'Ada Lovelace',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Ada Lovelace'), findsOneWidget);

    await tester.tap(find.byTooltip('Eliminar usuario'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Aún no hay usuarios. Agrega el primero.'),
      findsOneWidget,
    );
  });
}

class _FakeUsersRepository implements UsersRepository {
  final List<UserProfile> _users = [];
  final StreamController<List<UserProfile>> _changes =
      StreamController<List<UserProfile>>.broadcast(sync: true);

  @override
  Stream<List<UserProfile>> watchUsers() async* {
    yield List.unmodifiable(_users);
    yield* _changes.stream;
  }

  @override
  Future<void> saveUser({
    String? id,
    required String name,
    required String email,
    required String phone,
  }) async {
    if (id == null) {
      _users.add(
        UserProfile(id: 'new-user', name: name, email: email, phone: phone),
      );
    } else {
      final index = _users.indexWhere((user) => user.id == id);
      _users[index] = UserProfile(
        id: id,
        name: name,
        email: email,
        phone: phone,
      );
    }
    _changes.add(List.unmodifiable(_users));
  }

  @override
  Future<void> deleteUser(String id) async {
    _users.removeWhere((user) => user.id == id);
    _changes.add(List.unmodifiable(_users));
  }

  Future<void> dispose() => _changes.close();
}

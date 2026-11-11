import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
}

abstract interface class UsersRepository {
  Stream<List<UserProfile>> watchUsers();

  Future<void> saveUser({
    String? id,
    required String name,
    required String email,
    required String phone,
  });

  Future<void> deleteUser(String id);
}

class FirestoreUsersRepository implements UsersRepository {
  FirestoreUsersRepository({FirebaseFirestore? firestore})
    : _users = (firestore ?? FirebaseFirestore.instance).collection('users');

  final CollectionReference<Map<String, dynamic>> _users;

  @override
  Stream<List<UserProfile>> watchUsers() {
    return _users.snapshots().map((snapshot) {
      final users =
          snapshot.docs.map((document) {
            final data = document.data();
            return UserProfile(
              id: document.id,
              name: data['name'] as String? ?? '',
              email: data['email'] as String? ?? '',
              phone: data['phone'] as String? ?? '',
            );
          }).toList()..sort(
            (first, second) =>
                first.name.toLowerCase().compareTo(second.name.toLowerCase()),
          );
      return users;
    });
  }

  @override
  Future<void> saveUser({
    String? id,
    required String name,
    required String email,
    required String phone,
  }) async {
    final data = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
    };

    if (id == null) {
      data['createdAt'] = FieldValue.serverTimestamp();
      await _users.add(data);
    } else {
      await _users.doc(id).update(data);
    }
  }

  @override
  Future<void> deleteUser(String id) => _users.doc(id).delete();
}

class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required this.repository});

  final UsersRepository repository;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  late Stream<List<UserProfile>> _usersStream;

  @override
  void initState() {
    super.initState();
    _usersStream = widget.repository.watchUsers();
  }

  void _reloadUsers() {
    setState(() {
      _usersStream = widget.repository.watchUsers();
    });
  }

  Future<void> _openUserForm([UserProfile? user]) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _UserFormDialog(
        user: user,
        onSave: (name, email, phone) => widget.repository.saveUser(
          id: user?.id,
          name: name,
          email: email,
          phone: phone,
        ),
      ),
    );
  }

  Future<void> _deleteUser(UserProfile user) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Quieres eliminar a ${user.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;

    try {
      await widget.repository.deleteUser(user.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar el usuario: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      body: StreamBuilder<List<UserProfile>>(
        stream: _usersStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _MessageState(
              message: 'No se pudieron cargar los usuarios.\n${snapshot.error}',
              action: TextButton(
                onPressed: _reloadUsers,
                child: const Text('Reintentar'),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data ?? const <UserProfile>[];
          if (users.isEmpty) {
            return const _MessageState(
              message: 'Aún no hay usuarios. Agrega el primero.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(user.name.isEmpty ? '?' : user.name[0]),
                  ),
                  title: Text(user.name),
                  subtitle: Text(
                    user.phone.isEmpty
                        ? user.email
                        : '${user.email}\n${user.phone}',
                  ),
                  isThreeLine: user.phone.isNotEmpty,
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Editar usuario',
                        onPressed: () => _openUserForm(user),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Eliminar usuario',
                        onPressed: () => _deleteUser(user),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openUserForm,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Agregar usuario'),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            ?action,
          ],
        ),
      ),
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({required this.user, required this.onSave});

  final UserProfile? user;
  final Future<void> Function(String name, String email, String phone) onSave;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user?.name ?? '');
    _emailController = TextEditingController(text: widget.user?.email ?? '');
    _phoneController = TextEditingController(text: widget.user?.phone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        _nameController.text,
        _emailController.text,
        _phoneController.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar el usuario: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.user != null;
    return AlertDialog(
      title: Text(isEditing ? 'Editar usuario' : 'Nuevo usuario'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre'),
                textCapitalization: TextCapitalization.words,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe el nombre'
                    : null,
              ),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Correo'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty || !email.contains('@')) {
                    return 'Escribe un correo válido';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Teléfono (opcional)',
                ),
                keyboardType: TextInputType.phone,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

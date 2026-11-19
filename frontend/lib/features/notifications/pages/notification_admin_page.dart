import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/authentication_state.dart';
import '../providers/notification_repository.dart';

class NotificationAdminPage extends ConsumerStatefulWidget {
  const NotificationAdminPage({super.key});

  @override
  ConsumerState<NotificationAdminPage> createState() =>
      _NotificationAdminPageState();
}

class _NotificationAdminPageState extends ConsumerState<NotificationAdminPage> {
  List<Map<String, dynamic>> _items = [], _recipients = [];
  int? _recipient;
  bool _busy = false;
  String? _error;
  NotificationRepository get _repository =>
      ref.read(notificationRepositoryProvider);
  bool get _admin =>
      ref.read(authenticationStateProvider).valueOrNull?.role == 'ADMIN';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_admin) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repository.adminNotifications(userId: _recipient),
        _repository.recipients(),
      ]);
      if (mounted) {
        setState(() {
          _items = results[0];
          _recipients = results[1];
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) {
    final body = error is DioException ? error.response?.data : null;
    return body is Map
        ? body['message']?.toString() ?? 'Action impossible.'
        : 'Impossible de joindre le serveur.';
  }

  Future<void> _save({Map<String, dynamic>? entry}) async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _NotificationEditor(recipients: _recipients, entry: entry),
    );
    if (data == null || !mounted) return;
    try {
      await _repository.saveNotification(
        data,
        id: entry?['notification']['id'] as int?,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<void> _delete(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la notification ?'),
        content: Text(
          'Elle sera supprimée de la boîte de ${entry['recipientName']}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteNotification(entry['notification']['id'] as int);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin =
        ref.watch(authenticationStateProvider).valueOrNull?.role == 'ADMIN';
    if (!admin) {
      return const Scaffold(
        body: Center(child: Text('Accès réservé aux administrateurs.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration des notifications'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy || _recipients.isEmpty ? null : () => _save(),
        icon: const Icon(Icons.add),
        label: const Text('Créer une notification'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          DropdownButtonFormField<int>(
            initialValue: _recipient,
            decoration: const InputDecoration(labelText: 'Destinataire'),
            items: [
              const DropdownMenuItem<int>(
                value: null,
                child: Text('Tous les utilisateurs'),
              ),
              ..._recipients.map(
                (user) => DropdownMenuItem<int>(
                  value: user['id'] as int,
                  child: Text('${user['name']} (${user['role']})'),
                ),
              ),
            ],
            onChanged: _busy
                ? null
                : (id) {
                    _recipient = id;
                    _load();
                  },
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!_busy && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucune notification.'),
            ),
          for (final entry in _items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry['notification']['title'] as String,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Pour ${entry['recipientName']} · ${entry['notification']['read'] == true ? 'Lue' : 'Non lue'}',
                    ),
                    const SizedBox(height: 8),
                    Text(entry['notification']['message'] as String),
                    Wrap(
                      children: [
                        TextButton.icon(
                          onPressed: _busy ? null : () => _save(entry: entry),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Modifier'),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : () => _delete(entry),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Supprimer'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationEditor extends StatefulWidget {
  const _NotificationEditor({required this.recipients, this.entry});
  final List<Map<String, dynamic>> recipients;
  final Map<String, dynamic>? entry;
  @override
  State<_NotificationEditor> createState() => _NotificationEditorState();
}

class _NotificationEditorState extends State<_NotificationEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _message, _reference;
  late String _type;
  late bool _read;
  int? _recipient;
  @override
  void initState() {
    super.initState();
    final item = widget.entry?['notification'] as Map?;
    _title = TextEditingController(text: item?['title'] as String? ?? '');
    _message = TextEditingController(text: item?['message'] as String? ?? '');
    _reference = TextEditingController(
      text: item?['referenceId']?.toString() ?? '',
    );
    _type = item?['type'] as String? ?? 'GENERAL';
    _read = item?['read'] == true;
    _recipient = widget.entry?['userId'] as int?;
  }

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.entry == null
          ? 'Créer une notification'
          : 'Modifier la notification',
    ),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.entry == null)
              DropdownButtonFormField<int>(
                initialValue: _recipient,
                decoration: const InputDecoration(labelText: 'Destinataire'),
                isExpanded: true,
                items: widget.recipients
                    .map(
                      (u) => DropdownMenuItem<int>(
                        value: u['id'] as int,
                        child: Text('${u['name']} (${u['role']})'),
                      ),
                    )
                    .toList(),
                onChanged: (id) => _recipient = id,
                validator: (id) =>
                    id == null ? 'Choisissez un destinataire.' : null,
              ),
            TextFormField(
              controller: _title,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Titre'),
              validator: (s) =>
                  s == null || s.trim().isEmpty ? 'Titre obligatoire.' : null,
            ),
            TextFormField(
              controller: _message,
              maxLength: 2000,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Message'),
              validator: (s) =>
                  s == null || s.trim().isEmpty ? 'Message obligatoire.' : null,
            ),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(
                  value: 'GENERAL',
                  child: Text('Général / documents / santé'),
                ),
                DropdownMenuItem(
                  value: 'APPOINTMENT',
                  child: Text('Rendez-vous'),
                ),
                DropdownMenuItem(
                  value: 'MEDICATION',
                  child: Text('Médicament'),
                ),
              ],
              onChanged: (value) => setState(() => _type = value!),
            ),
            if (_type != 'GENERAL')
              TextFormField(
                controller: _reference,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Identifiant de l’élément lié',
                ),
                validator: (s) {
                  if ((s == null || s.isEmpty) &&
                      widget.entry != null &&
                      widget.entry!['notification']['referenceId'] == null &&
                      _type == widget.entry!['notification']['type']) {
                    return null;
                  }
                  return (int.tryParse(s ?? '') ?? 0) > 0
                      ? null
                      : 'Identifiant positif obligatoire.';
                },
              ),
            if (widget.entry != null)
              SwitchListTile(
                title: const Text('Marquée comme lue'),
                value: _read,
                onChanged: (value) => setState(() => _read = value),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, <String, dynamic>{
            'title': _title.text.trim(),
            'message': _message.text.trim(),
            'type': _type,
            if (_type != 'GENERAL' && _reference.text.isNotEmpty)
              'referenceId': int.parse(_reference.text),
            if (widget.entry == null) 'userId': _recipient,
            if (widget.entry != null) 'read': _read,
          });
        },
        child: const Text('Enregistrer'),
      ),
    ],
  );
}

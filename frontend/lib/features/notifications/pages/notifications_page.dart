import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/care_workspace.dart';
import '../../documents/pages/documents_page.dart';
import '../providers/notification_repository.dart';
import '../widgets/activity_cards.dart';
import '../widgets/reminder_form.dart';
import '../widgets/care_contacts.dart';
import 'notification_admin_page.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});
  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _notifications = [], _reminders = [];
  Map<String, dynamic> _overview = {};
  bool _loading = true,
      _loadingRequest = false,
      _reloadQueued = false,
      _busy = false,
      _archived = false;
  bool? _readFilter;
  String? _typeFilter, _statusFilter, _error;
  int _tab = 0;
  Timer? _timer, _debounce;

  NotificationRepository get _repository =>
      ref.read(notificationRepositoryProvider);
  get _filters =>
      (_search.text, _readFilter, _typeFilter, _statusFilter, _archived);
  bool get _filtered =>
      _search.text.trim().isNotEmpty ||
      _typeFilter != null ||
      _readFilter != null ||
      _statusFilter != null;
  int _count(String key) => (_overview[key] as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadingRequest) {
      _reloadQueued = true;
      return;
    }
    _loadingRequest = true;
    final repository = _repository;
    final filters = _filters;
    try {
      final result = await Future.wait<dynamic>([
        repository.notifications(
          read: _readFilter,
          query: _search.text,
          type: _typeFilter,
          archived: _archived,
        ),
        repository.reminders(
          query: _search.text,
          type: _typeFilter,
          status: _statusFilter,
        ),
        repository.overview(),
      ]);
      if (!mounted) return;
      if (filters != _filters) {
        _reloadQueued = true;
        return;
      }
      setState(() {
        _notifications = result[0] as List<Map<String, dynamic>>;
        _reminders = result[1] as List<Map<String, dynamic>>;
        _overview = result[2] as Map<String, dynamic>;
        _error = null;
      });
    } catch (error) {
      if (mounted && filters == _filters) {
        setState(() => _error = _errorMessage(error));
      }
    } finally {
      _loadingRequest = false;
      if (mounted) setState(() => _loading = false);
      if (mounted && (_reloadQueued || filters != _filters)) {
        _reloadQueued = false;
        unawaited(_load());
      }
    }
  }

  String _errorMessage(Object error) =>
      error is DioException && error.response?.data is Map
      ? error.response?.data['message']?.toString() ?? 'Action impossible.'
      : 'Impossible de joindre le serveur.';

  Future<void> _perform(
    Future<void> Function() action, {
    String? message,
    VoidCallback? undo,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      if (mounted && message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            action: undo == null
                ? null
                : SnackBarAction(label: 'Annuler', onPressed: undo),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 300), () => _load());
  }

  void _resetFilters() {
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _readFilter = null;
      _typeFilter = null;
      _statusFilter = null;
    });
    _load();
  }

  Future<void> _openReminderForm({Map<String, dynamic>? initial}) async {
    final repository = _repository;
    Map<String, dynamic>? patient;
    if (initial == null &&
        (_overview['role'] == 'DOCTOR' || _overview['role'] == 'ADMIN')) {
      try {
        patient = await pickPatient(
          context,
          repository,
          canAdd: _overview['role'] == 'DOCTOR',
          allUsers: _overview['role'] == 'ADMIN',
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impossible de charger les patients.'),
            ),
          );
        }
        return;
      }
      if (patient == null || !mounted) return;
    }
    final patientName =
        patient?['name'] ??
        (initial != null && initial['recipientId'] != _overview['viewerId']
            ? initial['recipientName']
            : null);
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => Theme(
        data: careTheme(context),
        child: ReminderForm(
          repository: repository,
          initial: initial,
          patientName: patientName as String?,
        ),
      ),
    );
    if (data == null || !mounted) return;
    await _perform(
      () => repository.saveReminder({
        ...data,
        if (patient != null) 'patientId': patient['id'],
      }, id: initial?['id'] as int?),
      message: initial == null
          ? 'Votre rappel est programmé.'
          : 'Rappel mis à jour.',
    );
  }

  void _archive(Map<String, dynamic> item) {
    final repository = _repository;
    final archived = item['archived'] == true;
    final id = item['id'] as int;
    _perform(
      () => repository.archive(id, archived: !archived),
      message: archived ? 'Notification restaurée.' : 'Notification archivée.',
      undo: () {
        if (mounted) _perform(() => repository.archive(id, archived: archived));
      },
    );
  }

  Future<void> _reminderAction(Map<String, dynamic> item, String action) async {
    final repository = _repository;
    final id = item['id'] as int;
    if (action == 'retry') {
      await _perform(
        () => repository.retry(id),
        message: 'Envoi remis en attente.',
      );
      return;
    }
    if (action == 'alert') {
      final now = DateTime.now();
      final day = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now,
        lastDate: DateTime(now.year + 10),
      );
      if (day == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time == null || !mounted) return;
      await _perform(
        () => repository.setAlert(
          id,
          DateTime(day.year, day.month, day.day, time.hour, time.minute),
        ),
        message: 'Heure de l’alerte enregistrée.',
      );
      return;
    }
    if (action == 'edit') {
      await _openReminderForm(initial: item);
      return;
    }
    if (action.startsWith('snooze')) {
      await _perform(
        () => repository.snooze(id, int.parse(action.substring(6))),
        message: 'Nouvelle échéance enregistrée.',
      );
      return;
    }
    final deleting = action == 'delete';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(deleting ? 'Supprimer ce rappel ?' : 'Annuler ce rappel ?'),
        content: Text(
          '« ${item['title']} »\n${deleting ? 'Ce rappel sera supprimé de votre liste.' : 'Aucune notification ne sera envoyée pour ce rappel.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conserver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(deleting ? 'Supprimer' : 'Annuler le rappel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(
      () => deleting
          ? repository.deleteReminder(id)
          : repository.cancelReminder(id),
      message: deleting ? 'Rappel supprimé.' : 'Rappel annulé.',
    );
  }

  Future<void> _deliveries() async {
    try {
      final rows = await _repository.deliveries();
      if (!mounted) return;
      final retryId = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Suivi des envois'),
          children: [
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucun envoi.'),
              ),
            for (final row in rows)
              ListTile(
                leading: Icon(
                  row['failedReminderId'] == null
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                ),
                title: Text(row['title'] as String),
                subtitle: Text(
                  "${row['recipientName']} · ${careDate(row['at'])}",
                ),
                trailing: row['failedReminderId'] == null
                    ? null
                    : TextButton(
                        onPressed: () =>
                            Navigator.pop(ctx, row['failedReminderId']),
                        child: const Text('Relancer'),
                      ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
      if (retryId != null && mounted) {
        await _perform(
          () => _repository.retry(retryId),
          message: 'Envoi remis en attente.',
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suivi des envois indisponible.')),
        );
      }
    }
  }

  Future<void> _history() async {
    try {
      final rows = await _repository.history();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Historique des rappels'),
          children: [
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucune intervention.'),
              ),
            for (final row in rows)
              ListTile(
                title: Text("${row['action']} · rappel #${row['reminderId']}"),
                subtitle: Text(
                  "${row['actorName']} · ${careDate(row['changedAt'])}",
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Historique indisponible.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => CareWorkspace(
    index: 0,
    onRefresh: _load,
    onNavigate: (index) {
      if (index == 1) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DocumentsPage()),
        );
      }
    },
    child: RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CareHero(
                  eyebrow: 'Votre centre de suivi',
                  title: 'Un esprit plus tranquille.',
                  description:
                      'Vos informations importantes, au bon moment. Retrouvez vos notifications et organisez les rappels qui comptent pour vous.',
                  icon: Icons.spa_outlined,
                  action: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD4E9DA),
                      foregroundColor: CareColors.ink,
                    ),
                    onPressed: _busy ? null : () => _openReminderForm(),
                    icon: const Icon(Icons.add_rounded, size: 19),
                    label: const Text('Programmer un rappel'),
                  ),
                ),
                if (_overview['role'] == 'DOCTOR')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AddPatientButton(repository: _repository),
                  ),
                if (_overview['role'] == 'USER')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.medical_services_outlined),
                      label: const Text('Mes médecins'),
                      onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => DoctorDialog(repository: _repository),
                      ),
                    ),
                  ),
                if (_overview['role'] == 'ADMIN')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: const Text('Gérer toutes les notifications'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationAdminPage(),
                        ),
                      ),
                    ),
                  ),
                if (_overview['role'] == 'ADMIN')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _deliveries,
                      icon: const Icon(Icons.outbox_outlined),
                      label: const Text('Suivi des envois'),
                    ),
                  ),
                if (_overview['role'] == 'ADMIN')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.history),
                      label: const Text('Historique des interventions'),
                      onPressed: _history,
                    ),
                  ),
                const SizedBox(height: 20),
                CareStats(
                  compactIndices: const [0, 1],
                  children: [
                    CareStat(
                      value: _loading ? '—' : '${_count('unread')}',
                      label: 'Non lues',
                      icon: Icons.mark_email_unread_outlined,
                    ),
                    CareStat(
                      value: _loading ? '—' : '${_count('pendingReminders')}',
                      label: 'Rappels à venir',
                      icon: Icons.schedule_rounded,
                      color: CareColors.violet,
                    ),
                    CareStat(
                      value: _loading ? '—' : '${_count('sentReminders')}',
                      label: 'Rappels envoyés',
                      icon: Icons.done_all_rounded,
                      color: CareColors.amber,
                    ),
                    CareStat(
                      value: _loading ? '—' : '${_count('archived')}',
                      label: 'Archives',
                      icon: Icons.inventory_2_outlined,
                      color: CareColors.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null) ...[
                  CareError(message: _error!, onRetry: _load),
                  const SizedBox(height: 16),
                ],
                LayoutBuilder(
                  builder: (context, constraints) {
                    final main = _mainContent();
                    if (constraints.maxWidth < 1000) return main;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: main),
                        const SizedBox(width: 24),
                        SizedBox(width: 260, child: _insights()),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _mainContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<int>(
        style: SegmentedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 17),
        ),
        segments: const [
          ButtonSegment(
            value: 0,
            label: Text('Notifications'),
            icon: Icon(Icons.notifications_outlined),
          ),
          ButtonSegment(
            value: 1,
            label: Text('Rappels'),
            icon: Icon(Icons.alarm_rounded),
          ),
        ],
        selected: {_tab},
        onSelectionChanged: (value) => setState(() => _tab = value.first),
      ),
      const SizedBox(height: 20),
      TextField(
        key: const ValueKey('notification-search'),
        controller: _search,
        onChanged: _searchChanged,
        decoration: InputDecoration(
          hintText: _tab == 0
              ? 'Rechercher dans vos notifications…'
              : 'Rechercher un rappel…',
          prefixIcon: const Icon(Icons.search_rounded, color: CareColors.muted),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer la recherche',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _search.clear();
                    _load();
                  },
                ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String>(
            key: const ValueKey('notification-type-filter'),
            value: _typeFilter ?? 'ALL',
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'ALL', child: Text('Tous les types')),
              DropdownMenuItem(value: 'GENERAL', child: Text('Général')),
              DropdownMenuItem(
                value: 'APPOINTMENT',
                child: Text('Rendez-vous'),
              ),
              DropdownMenuItem(value: 'MEDICATION', child: Text('Médicament')),
            ],
            onChanged: (value) {
              setState(() => _typeFilter = value == 'ALL' ? null : value);
              _load();
            },
          ),
          if (_tab == 1)
            DropdownButton<String>(
              key: const ValueKey('reminder-status-filter'),
              value: _statusFilter ?? 'ALL',
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('Tous les statuts')),
                DropdownMenuItem(value: 'PENDING', child: Text('En attente')),
                DropdownMenuItem(value: 'SENT', child: Text('Envoyé')),
                DropdownMenuItem(value: 'CANCELLED', child: Text('Annulé')),
              ],
              onChanged: (value) {
                setState(() => _statusFilter = value == 'ALL' ? null : value);
                _load();
              },
            ),
          if (_filtered)
            TextButton(
              onPressed: _resetFilters,
              child: const Text('Réinitialiser'),
            ),
        ],
      ),
      if (_tab == 0) ...[
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('Toutes'),
              selected: _readFilter == null,
              onSelected: (_) {
                setState(() => _readFilter = null);
                _load();
              },
            ),
            ChoiceChip(
              label: const Text('Non lues'),
              selected: _readFilter == false,
              onSelected: (_) {
                setState(
                  () => _readFilter = _readFilter == false ? null : false,
                );
                _load();
              },
            ),
            ChoiceChip(
              label: const Text('Lues'),
              selected: _readFilter == true,
              onSelected: (_) {
                setState(() => _readFilter = _readFilter == true ? null : true);
                _load();
              },
            ),
            FilterChip(
              key: const ValueKey('notification-archive-filter'),
              avatar: const Icon(Icons.archive_outlined, size: 15),
              label: const Text('Archives'),
              selected: _archived,
              onSelected: (value) {
                setState(() => _archived = value);
                _load();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_notifications.length} notification(s)',
                style: const TextStyle(color: CareColors.muted, fontSize: 12),
              ),
            ),
            if (!_archived)
              TextButton.icon(
                onPressed: _busy || _count('unread') == 0
                    ? null
                    : () => _perform(
                        _repository.markAllRead,
                        message: 'Notifications marquées comme lues.',
                      ),
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: const Text(
                  'Tout marquer comme lu',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ] else ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '${_reminders.length} rappel(s)',
            style: const TextStyle(color: CareColors.muted, fontSize: 12),
          ),
        ),
      ],
      const SizedBox(height: 8),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(50),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_tab == 0 && _notifications.isEmpty)
        CareEmpty(
          title: _archived
              ? 'Vos archives sont vides'
              : _filtered
              ? 'Aucun résultat'
              : 'Vous êtes à jour',
          message: _filtered
              ? 'Aucune notification ne correspond aux filtres.'
              : 'Vos nouvelles informations apparaîtront ici.',
          icon: _archived
              ? Icons.inventory_2_outlined
              : Icons.notifications_paused_outlined,
        )
      else if (_tab == 1 && _reminders.isEmpty)
        CareEmpty(
          title: _filtered ? 'Aucun résultat' : 'Un quotidien bien organisé',
          message: _filtered
              ? 'Aucun rappel ne correspond aux filtres.'
              : 'Programmez un rappel personnel, un rendez-vous ou une prise de médicament.',
          icon: Icons.alarm_add_rounded,
        )
      else
        ..._groupedCards(),
    ],
  );

  List<Widget> _groupedCards() {
    final result = <Widget>[];
    String? lastDay;
    for (final item in _tab == 0 ? _notifications : _reminders) {
      final day = careDay(item[_tab == 0 ? 'createdAt' : 'scheduledFor']);
      if (day != lastDay) {
        result.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 14, 0, 12),
            child: Text(
              day.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: CareColors.muted,
              ),
            ),
          ),
        );
        lastDay = day;
      }
      result.add(
        _tab == 0
            ? NotificationCard(
                item: item,
                busy: _busy,
                onArchive: () => _archive(item),
                onRead: () => _perform(
                  () => item['read'] == true
                      ? _repository.markUnread(item['id'] as int)
                      : _repository.markRead(item['id'] as int),
                ),
              )
            : ReminderCard(
                admin: _overview['role'] == 'ADMIN',
                recipient:
                    _overview['role'] == 'ADMIN' ||
                    item['recipientId'] == null ||
                    item['recipientId'] == _overview['viewerId'],
                manage:
                    _overview['role'] == 'ADMIN' ||
                    (item['authorId'] == null
                        ? item['recipientId'] == null ||
                              item['recipientId'] == _overview['viewerId']
                        : item['authorId'] == _overview['viewerId']),
                item: item,
                busy: _busy,
                onAction: (action) => _reminderAction(item, action),
              ),
      );
    }
    return result;
  }

  Widget _insights() {
    final next = _overview['nextReminder'] as Map<String, dynamic>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CareBadge('Votre prochain rappel', icon: Icons.schedule),
              const SizedBox(height: 20),
              Icon(
                next == null
                    ? Icons.check_circle_outline_rounded
                    : activityIcon(next['type']),
                color: CareColors.primary,
                size: 32,
              ),
              const SizedBox(height: 14),
              Text(
                next == null
                    ? 'Le temps de souffler.'
                    : next['title'] as String,
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                next == null
                    ? 'Aucun rappel en attente. Vous pouvez en programmer un à tout moment.'
                    : '${careDate(next['scheduledFor'])}\n${careRelative(next['scheduledFor'])}',
                style: const TextStyle(
                  color: CareColors.muted,
                  height: 1.7,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openReminderForm(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Nouveau rappel'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const CarePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tips_and_updates_outlined, color: CareColors.amber),
              SizedBox(height: 14),
              Text(
                'Votre suivi, à votre rythme.',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'Archivez les informations déjà traitées. Un imprévu ? Décalez un rappel depuis sa carte.',
                style: TextStyle(
                  color: CareColors.muted,
                  height: 1.7,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

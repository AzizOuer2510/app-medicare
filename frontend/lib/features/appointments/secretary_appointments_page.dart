import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';

class SecretaryAppointmentsPage extends ConsumerStatefulWidget {
  const SecretaryAppointmentsPage({super.key, this.isAdmin = false});

  final bool isAdmin;

  @override
  ConsumerState<SecretaryAppointmentsPage> createState() =>
      _SecretaryAppointmentsPageState();
}

class _SecretaryAppointmentsPageState
    extends ConsumerState<SecretaryAppointmentsPage> {
  static const statuses = ['PLANNED', 'CONFIRMED', 'COMPLETED', 'CANCELLED'];

  List<dynamic> appointments = [];
  List<dynamic> patients = [];
  List<Map<String, dynamic>> doctors = [];
  String filter = 'ALL';
  bool loading = false;

  Dio get _api => ref.read(apiClientProvider).dio;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        _api.get('/secretary/appointments',
            queryParameters: filter == 'ALL' ? null : {'status': filter}),
        _api.get('/secretary/patients'),
        _api.get('/secretary/doctors'),
      ]);
      if (!mounted) return;
      setState(() {
        appointments = results[0].data as List<dynamic>;
        patients = results[1].data as List<dynamic>;
        doctors = (results[2].data as List<dynamic>)
            .map((doctor) => Map<String, dynamic>.from(doctor as Map))
            .toList();
      });
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> openForm([Map<String, dynamic>? existing]) async {
    if (patients.isEmpty) {
      _snack('Aucun patient enregistré');
      return;
    }
    if (doctors.isEmpty) {
      _snack('Aucun médecin ne vous est affecté');
      return;
    }
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AppointmentDialog(
        patients: patients,
        existing: existing,
        statuses: statuses,
        doctors: doctors,
      ),
    );
    if (payload == null) return;
    try {
      if (existing == null) {
        await _api.post('/secretary/appointments', data: payload);
      } else {
        await _api.put('/secretary/appointments/${existing['id']}',
            data: payload);
      }
      await load();
      _snack(existing == null ? 'Rendez-vous attribué' : 'Rendez-vous mis à jour');
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> remove(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le rendez-vous ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.delete('/secretary/appointments/$id');
      await load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> sendReminders() async {
    try {
      final response = await _api.post('/secretary/reminders/run');
      await load();
      _snack('${response.data['sent']} rappel(s) envoyé(s) (email + SMS)');
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> manageAssignments() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AssignmentsDialog(api: _api),
    );
    await load();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(Object e) {
    final data = e is DioException ? e.response?.data : null;
    final message = data is Map ? data['message']?.toString() : null;
    _snack(message ?? 'Erreur : $e');
  }

  String _format(dynamic raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '');
    if (d == null) return '-';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace secrétaire'),
        actions: [
          if (widget.isAdmin)
            IconButton(
                onPressed: manageAssignments,
                icon: const Icon(Icons.manage_accounts_outlined),
                tooltip: 'Affecter secrétaires / médecins'),
          IconButton(
              onPressed: sendReminders,
              icon: const Icon(Icons.notifications_active_outlined),
              tooltip: 'Envoyer les rappels (email + SMS)'),
          IconButton(
              onPressed: load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualiser'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Attribuer un rendez-vous'),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: ['ALL', ...statuses]
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(s),
                          selected: filter == s,
                          onSelected: (_) {
                            setState(() => filter = s);
                            load();
                          },
                        ),
                      ))
                  .toList(),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: appointments.isEmpty
                ? const Center(child: Text('Aucun rendez-vous'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: appointments.length,
                    itemBuilder: (_, i) {
                      final a = Map<String, dynamic>.from(appointments[i]);
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          title: Text('${a['patientName']} — ${a['doctorName']}'),
                          subtitle: Text(
                              '${_format(a['dateTime'])} • ${a['status']}'
                              '${a['reminderSentAt'] != null ? ' • Rappel envoyé' : ''}'
                              '${a['reason'] != null ? '\n${a['reason']}' : ''}'),
                          isThreeLine: a['reason'] != null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => openForm(a)),
                              IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => remove(a['id'] as int)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentDialog extends StatefulWidget {
  const _AppointmentDialog({
    required this.patients,
    required this.statuses,
    required this.doctors,
    this.existing,
  });

  final List<dynamic> patients;
  final List<String> statuses;
  final List<Map<String, dynamic>> doctors;
  final Map<String, dynamic>? existing;

  @override
  State<_AppointmentDialog> createState() => _AppointmentDialogState();
}

class _AppointmentDialogState extends State<_AppointmentDialog> {
  final _formKey = GlobalKey<FormState>();
  int? doctorId;
  late final TextEditingController reason;
  late int? patientId;
  late String status;
  late DateTime dateTime;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final ids = widget.doctors.map((d) => d['id'] as int).toList();
    final existingDoctor = e?['doctorId'] as int?;
    doctorId = (existingDoctor != null && ids.contains(existingDoctor))
        ? existingDoctor
        : (ids.isNotEmpty ? ids.first : null);
    reason = TextEditingController(text: e?['reason'] ?? '');
    patientId = e?['patientId'] as int?;
    status = e?['status'] ?? 'PLANNED';
    dateTime = DateTime.tryParse(e?['dateTime']?.toString() ?? '') ??
        DateTime.now().add(const Duration(days: 1));
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: dateTime.isBefore(now) ? now : dateTime,
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(dateTime));
    if (!mounted || time == null) return;
    setState(() => dateTime =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Attribuer un rendez-vous'
          : 'Modifier le rendez-vous'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: patientId,
                decoration: const InputDecoration(labelText: 'Patient'),
                items: widget.patients
                    .map((p) => DropdownMenuItem<int>(
                          value: p['id'] as int,
                          child: Text('${p['fullName']} (${p['email']})'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => patientId = v),
                validator: (v) => v == null ? 'Choisir un patient' : null,
              ),
              DropdownButtonFormField<int>(
                initialValue: doctorId,
                decoration: const InputDecoration(labelText: 'Médecin'),
                items: widget.doctors
                    .map((d) => DropdownMenuItem<int>(
                        value: d['id'] as int,
                        child: Text('${d['fullName']}')))
                    .toList(),
                onChanged: (v) => setState(() => doctorId = v),
                validator: (v) => v == null ? 'Choisir un médecin' : null,
              ),
              TextFormField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Motif'),
              ),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: widget.statuses
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => status = v ?? status),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: pickDate,
                icon: const Icon(Icons.event),
                label: Text(
                    '${dateTime.day}/${dateTime.month}/${dateTime.year} ${TimeOfDay.fromDateTime(dateTime).format(context)}'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, {
              'patientId': patientId,
              'dateTime': dateTime.toIso8601String(),
              'doctorId': doctorId,
              'reason': reason.text.trim(),
              'status': status,
            });
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

/// Admin only: link a secretary account (by email) to a doctor.
class _AssignmentsDialog extends StatefulWidget {
  const _AssignmentsDialog({required this.api});

  final Dio api;

  @override
  State<_AssignmentsDialog> createState() => _AssignmentsDialogState();
}

class _AssignmentsDialogState extends State<_AssignmentsDialog> {
  final email = TextEditingController();
  List<dynamic> assignments = [];
  List<dynamic> doctors = [];
  int? doctorId;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final results = await Future.wait([
        widget.api.get('/secretary/admin/assignments'),
        widget.api.get('/secretary/doctors'),
      ]);
      if (!mounted) return;
      setState(() {
        assignments = results[0].data as List<dynamic>;
        doctors = results[1].data as List<dynamic>;
        error = null;
      });
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> add() async {
    if (email.text.trim().isEmpty || doctorId == null) return;
    try {
      await widget.api.post('/secretary/admin/assignments',
          data: {'secretaryEmail': email.text.trim(), 'doctorId': doctorId});
      email.clear();
      await load();
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> remove(int id) async {
    try {
      await widget.api.delete('/secretary/admin/assignments/$id');
      await load();
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object e) {
    final data = e is DioException ? e.response?.data : null;
    if (!mounted) return;
    setState(() => error =
        (data is Map ? data['message']?.toString() : null) ?? 'Erreur : $e');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Affectations secrétaires'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration:
                    const InputDecoration(labelText: 'Email de la secrétaire'),
              ),
              DropdownButtonFormField<int>(
                initialValue: doctorId,
                decoration: const InputDecoration(labelText: 'Médecin'),
                items: doctors
                    .map((d) => DropdownMenuItem<int>(
                        value: d['id'] as int,
                        child: Text('${d['fullName']}')))
                    .toList(),
                onChanged: (v) => setState(() => doctorId = v),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: add,
                icon: const Icon(Icons.link),
                label: const Text('Affecter'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              const Divider(height: 24),
              if (assignments.isEmpty) const Text('Aucune affectation'),
              ...assignments.map((a) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${a['secretary']?['email']}'),
                    subtitle: Text('→ ${a['doctor']?['fullName']}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.link_off),
                      onPressed: () => remove(a['id'] as int),
                    ),
                  )),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer')),
      ],
    );
  }
}

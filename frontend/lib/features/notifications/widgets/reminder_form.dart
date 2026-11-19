import 'package:flutter/material.dart';
import '../../../core/widgets/care_workspace.dart';
import '../providers/notification_repository.dart';

class ReminderForm extends StatefulWidget {
  const ReminderForm({
    super.key,
    required this.repository,
    this.initial,
    this.patientName,
  });

  final String? patientName;
  final NotificationRepository repository;
  final Map<String, dynamic>? initial;

  @override
  State<ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<ReminderForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _message;
  late String _type;
  int? _referenceId;
  late DateTime _scheduledFor;
  List<Map<String, dynamic>> _references = [];
  bool _loadingReferences = false;
  String? _referenceError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?['title'] as String? ?? '');
    _message = TextEditingController(
      text: initial?['message'] as String? ?? '',
    );
    _type = initial?['type'] as String? ?? 'GENERAL';
    _referenceId = initial?['referenceId'] as int?;
    _scheduledFor = initial == null
        ? DateTime.now().add(const Duration(minutes: 5))
        : DateTime.parse(
            (initial['instructionAt'] ?? initial['scheduledFor']) as String,
          ).toLocal();
    if (widget.patientName == null) _loadReferences();
  }

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _loadReferences() async {
    final requestedType = _type;
    setState(() {
      _loadingReferences = true;
      _referenceError = null;
      _references = [];
    });
    try {
      final result = await widget.repository.references(requestedType);
      if (!mounted || requestedType != _type) return;
      setState(() {
        _references = result;
        if (!result.any((item) => item['id'] == _referenceId)) {
          _referenceId = null;
        }
      });
    } catch (_) {
      if (mounted && requestedType == _type) {
        setState(
          () => _referenceError = 'Impossible de charger les elements lies.',
        );
      }
    } finally {
      if (mounted && requestedType == _type) {
        setState(() => _loadingReferences = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _scheduledFor.isBefore(now) ? now : _scheduledFor;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(
      () => _scheduledFor = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate() || _loadingReferences) return;
    if (!_scheduledFor.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez une date dans le futur.')),
      );
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'title': _title.text.trim(),
      'message': _message.text.trim(),
      'type': _type,
      if (_referenceId != null) 'referenceId': _referenceId,
      'scheduledFor': _scheduledFor.toUtc().toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'Programmer un rappel' : 'Modifier le rappel',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.patientName != null
                    ? 'Destinataire · ${widget.patientName}'
                    : 'Une notification apparaîtra dans votre espace à l’échéance choisie.',
                style: TextStyle(
                  color: CareColors.muted,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                key: const ValueKey('reminder-title'),
                controller: _title,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Nom du rappel',
                  prefixIcon: Icon(Icons.alarm_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Titre requis'
                    : null,
              ),
              TextFormField(
                key: const ValueKey('reminder-message'),
                controller: _message,
                maxLength: 2000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Message'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Message requis'
                    : null,
              ),
              if (widget.patientName == null)
                DropdownButtonFormField<String>(
                  key: const ValueKey('reminder-type'),
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'GENERAL',
                      child: Text('Personnel'),
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
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _type = value;
                      _referenceId = null;
                    });
                    _loadReferences();
                  },
                ),
              if (_loadingReferences) const LinearProgressIndicator(),
              if (_referenceError != null) Text(_referenceError!),
              if (widget.patientName == null &&
                  _type != 'GENERAL' &&
                  !_loadingReferences)
                DropdownButtonFormField<int>(
                  key: ValueKey('$_type-$_referenceId'),
                  initialValue: _referenceId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Element lie'),
                  items: _references
                      .map(
                        (item) => DropdownMenuItem<int>(
                          value: item['id'] as int,
                          child: Text(
                            _type == 'APPOINTMENT'
                                ? '${item['doctorName']} - ${item['dateTime']}'
                                : item['name'] as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _referenceId = value),
                  validator: (value) =>
                      value == null ? 'Selectionnez un element existant' : null,
                ),
              if (_type != 'GENERAL' &&
                  !_loadingReferences &&
                  _references.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Aucun element disponible. Vous pouvez creer un rappel general.',
                  ),
                ),
              const SizedBox(height: 18),
              const Text(
                'Quand souhaitez-vous être rappelé ?',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Dans 1 h'),
                    onPressed: () => setState(
                      () => _scheduledFor = DateTime.now().add(
                        const Duration(hours: 1),
                      ),
                    ),
                  ),
                  ActionChip(
                    label: const Text('Demain à 9 h'),
                    onPressed: () {
                      final now = DateTime.now();
                      setState(
                        () => _scheduledFor = DateTime(
                          now.year,
                          now.month,
                          now.day + 1,
                          9,
                        ),
                      );
                    },
                  ),
                  ActionChip(
                    label: const Text('Dans 1 semaine'),
                    onPressed: () {
                      final now = DateTime.now();
                      setState(
                        () => _scheduledFor = DateTime(
                          now.year,
                          now.month,
                          now.day + 7,
                          now.hour,
                          now.minute,
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.schedule),
                label: Text(
                  'Date : ${_scheduledFor.toString().substring(0, 16)}',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _loadingReferences ? null : _submit,
        child: const Text('Enregistrer'),
      ),
    ],
  );
}

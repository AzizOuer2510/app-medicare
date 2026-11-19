import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../providers/notification_repository.dart';

Future<Map<String, dynamic>?> pickPatient(
  BuildContext context,
  NotificationRepository repo, {
  bool canAdd = false,
  bool allUsers = false,
}) async {
  final contacts = await repo.contacts();
  if (!context.mounted) return null;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(allUsers ? 'Choisir le destinataire' : 'Choisir le patient'),
      children: [
        if (canAdd)
          TextButton.icon(
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Ajouter un patient'),
            onPressed: () async {
              final added = await _showAddPatient(ctx, repo);
              if (added != null && ctx.mounted) Navigator.pop(ctx, added);
            },
          ),
        if (contacts.isEmpty)
          Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              allUsers
                  ? 'Aucun utilisateur disponible.'
                  : 'Aucun patient disponible.',
            ),
          ),
        for (final person in contacts)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, person),
            child: Text(person['name'] as String),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}

Future<Map<String, dynamic>?> _showAddPatient(
  BuildContext context,
  NotificationRepository repository,
) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _AddPatientDialog(repository: repository),
  );
}

class AddPatientButton extends StatelessWidget {
  const AddPatientButton({super.key, required this.repository});
  final NotificationRepository repository;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.person_add_outlined),
    label: const Text('Ajouter un patient'),
    onPressed: () async {
      final person = await _showAddPatient(context, repository);
      if (person != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${person['name']} figure dans vos patients."),
          ),
        );
      }
    },
  );
}

class _AddPatientDialog extends StatefulWidget {
  const _AddPatientDialog({required this.repository});
  final NotificationRepository repository;
  @override
  State<_AddPatientDialog> createState() => _AddPatientDialogState();
}

class _AddPatientDialogState extends State<_AddPatientDialog> {
  final email = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.text.trim())) {
      setState(() => error = 'Saisissez l’adresse e-mail du compte patient.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final patient = await widget.repository.addPatient(email.text);
      if (mounted) Navigator.pop(context, patient);
    } catch (e) {
      final body = e is DioException ? e.response?.data : null;
      if (mounted) {
        setState(() {
          busy = false;
          error = body is Map && body['message'] is String
              ? body['message'] as String
              : 'Ajout impossible. Réessayez.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ajouter un patient'),
    scrollable: true,
    content: TextField(
      autofocus: true,
      controller: email,
      enabled: !busy,
      keyboardType: TextInputType.emailAddress,
      onSubmitted: (_) => submit(),
      decoration: InputDecoration(
        labelText: 'E-mail du compte patient',
        errorText: error,
        errorMaxLines: 4,
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: const Text('Ajouter'),
      ),
    ],
  );
}

class DoctorDialog extends StatefulWidget {
  const DoctorDialog({super.key, required this.repository});
  final NotificationRepository repository;
  @override
  State<DoctorDialog> createState() => _DoctorDialogState();
}

class _DoctorDialogState extends State<DoctorDialog> {
  final email = TextEditingController();
  List<Map<String, dynamic>> doctors = [];
  String? error;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final people = await widget.repository.contacts();
      if (mounted) {
        setState(() {
          doctors = people;
          error = null;
          busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Chargement impossible.';
          busy = false;
        });
      }
    }
  }

  Future<void> save(String? value, {int? doctorId}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.setDoctor(value, doctorId: doctorId);
      if (mounted) {
        email.clear();
        await load();
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          error = e.response?.data is Map
              ? e.response!.data['message']?.toString()
              : 'Connexion impossible.';
          busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Enregistrement impossible.';
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Mes médecins'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (busy) const LinearProgressIndicator(),
        for (final doctor in doctors)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(doctor['name'] as String),
            trailing: TextButton(
              onPressed: busy || doctor['removable'] == false
                  ? null
                  : () => save(null, doctorId: doctor['id'] as int),
              child: Text(doctor['removable'] == false ? 'Suivi M2/M3' : 'Retirer'),
            ),
          ),
        const Text(
          'Ce médecin pourra vous adresser des rappels et des comptes rendus. Vous choisissez les documents à partager.',
        ),
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Adresse e-mail du médecin',
          ),
        ),
        if (doctors.isNotEmpty)
          const Text(
            'Retirer un médecin ferme son accès aux documents que vous avez partagés avec lui.',
          ),
        if (error != null) Text(error!),
      ],
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context, true),
        child: const Text('Fermer'),
      ),

      FilledButton(
        onPressed: busy ? null : () => save(email.text.trim()),
        child: const Text('Rattacher'),
      ),
    ],
  );
}

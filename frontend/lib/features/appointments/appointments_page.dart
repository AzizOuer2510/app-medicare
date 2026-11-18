import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../auth/authentication_state.dart';
import 'secretary_appointments_page.dart';

class AppointmentsPage extends ConsumerStatefulWidget {
  const AppointmentsPage({super.key});

  @override
  ConsumerState<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends ConsumerState<AppointmentsPage> {
  static const appointmentTypes = [
    'Consultation générale',
    'Cardiologie',
    'Dermatologie',
    'Ophtalmologie',
    'ORL',
    'Gastro-entérologie',
    'Neurologie',
    'Orthopédie',
    'Dentisterie',
    'Autre',
  ];

  final _formKey = GlobalKey<FormState>();
  final doctor = TextEditingController();
  final reason = TextEditingController();
  final searchController = TextEditingController();
  final _appointmentsScrollController = ScrollController();

  List<dynamic> items = [];
  Map<String, dynamic> serverStats = {};
  DateTime selectedDateTime = DateTime.now().add(const Duration(days: 1));
  String selectedStatus = 'PLANNED';
  String selectedAppointmentType = 'Consultation générale';
  String selectedFilter = 'ALL';
  bool agendaMode = true;
  bool isAddingExamples = false;
  DateTime selectedAgendaDay = DateTime.now();
  int? editingId;
  int? selectedDoctorId;
  List<dynamic> registeredDoctors = [];
  bool canOpenSecretariat = false;
  bool isAdmin = false;

  @override
  void dispose() {
    doctor.dispose();
    reason.dispose();
    searchController.dispose();
    _appointmentsScrollController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      final api = ref.read(apiClientProvider).dio;
      final results = await Future.wait([
        api.get('/appointments'),
        api.get('/appointments/statistics'),
      ]);
      if (!mounted) return;
      setState(() {
        items = results[0].data as List<dynamic>;
        serverStats = Map<String, dynamic>.from(results[1].data as Map);
      });
    } catch (e) {
      if (!mounted || messenger == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Impossible de charger les rendez-vous : $e')),
      );
    }
  }

  Future<void> loadDirectory() async {
    final api = ref.read(apiClientProvider).dio;
    try {
      final response = await api.get('/appointments/doctors');
      if (mounted) {
        setState(() => registeredDoctors = response.data as List<dynamic>);
      }
    } catch (_) {}
    try {
      final response = await api.get('/secretary/me');
      final data = Map<String, dynamic>.from(response.data as Map);
      if (mounted) {
        setState(() {
          isAdmin = data['admin'] == true;
          canOpenSecretariat = isAdmin || data['secretary'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> save() async {
    if (!_formKey.currentState!.validate()) return;

    final isEditing = editingId != null;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final payload = {
      'dateTime': selectedDateTime.toIso8601String(),
      'doctorId': selectedDoctorId,
      'doctorName': doctor.text.trim(),
      'reason': reason.text.trim(),
      'appointmentType': selectedAppointmentType,
      'status': selectedStatus,
    };

    try {
      if (isEditing) {
        await ref
            .read(apiClientProvider)
            .dio
            .put('/appointments/$editingId', data: payload);
      } else {
        await ref
            .read(apiClientProvider)
            .dio
            .post('/appointments', data: payload);
      }

      if (!mounted) return;
      resetForm();
      await load();
      if (messenger == null || !mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Rendez-vous mis à jour'
                : 'Rendez-vous ajouté avec succès',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted || messenger == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Erreur lors de l’enregistrement : $e')),
      );
    }
  }

  Future<void> addSampleAppointments() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter des exemples ?'),
        content:
            const Text('Dix rendez-vous futurs seront ajoutés à votre compte.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    const examples = [
      ('Dr Exemple - Cardiologie', 'Contrôle de routine', 'Cardiologie'),
      (
        'Dr Exemple - Dermatologie',
        'Consultation dermatologique',
        'Dermatologie'
      ),
      ('Dr Exemple - Ophtalmologie', 'Examen de la vue', 'Ophtalmologie'),
      ('Dr Exemple - Pédiatrie', 'Consultation de suivi', 'Autre'),
      (
        'Dr Exemple - Médecine générale',
        'Bilan de santé',
        'Consultation générale'
      ),
      ('Dr Exemple - ORL', 'Consultation ORL', 'ORL'),
      ('Dr Exemple - Dentisterie', 'Contrôle dentaire', 'Dentisterie'),
      ('Dr Exemple - Neurologie', 'Consultation de suivi', 'Neurologie'),
      ('Dr Exemple - Endocrinologie', 'Suivi médical', 'Autre'),
      ('Dr Exemple - Gynécologie', 'Consultation annuelle', 'Autre'),
    ];

    setState(() => isAddingExamples = true);
    var createdCount = 0;
    try {
      final api = ref.read(apiClientProvider).dio;
      final response = await api.get('/appointments');
      final existingDoctors = (response.data as List<dynamic>)
          .map((appointment) =>
              (appointment['doctorName'] ?? '').toString().toLowerCase())
          .toSet();

      for (var index = 0; index < examples.length; index++) {
        final doctorName = examples[index].$1;
        if (existingDoctors.contains(doctorName.toLowerCase())) continue;

        final date = DateTime.now().add(Duration(days: index + 1));
        final appointmentDate =
            DateTime(date.year, date.month, date.day, 9 + index % 6);
        await api.post('/appointments', data: {
          'dateTime': appointmentDate.toIso8601String(),
          'doctorName': doctorName,
          'reason': examples[index].$2,
          'appointmentType': examples[index].$3,
          'status': index.isEven ? 'CONFIRMED' : 'PLANNED',
        });
        createdCount++;
        existingDoctors.add(doctorName.toLowerCase());
      }

      await load();
      if (!mounted) return;
      setState(() {
        agendaMode = false;
        selectedFilter = 'ALL';
        searchController.clear();
      });
      final message = createdCount == 0
          ? 'Les rendez-vous d’exemple sont déjà présents.'
          : '$createdCount rendez-vous d’exemple ajoutés.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        await ref.read(authenticationStateProvider.notifier).logout();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expirée ou refusée. Reconnectez-vous.'),
          ),
        );
        return;
      }

      final responseData = error.response?.data;
      final apiMessage =
          responseData is Map ? responseData['message']?.toString() : null;
      final failure = apiMessage?.isNotEmpty == true
          ? apiMessage!
          : 'Erreur API ${status ?? 'inconnue'}';
      final message = createdCount == 0
          ? 'Ajout impossible : $failure.'
          : '$createdCount exemples ajoutés avant l’erreur : $failure.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur inattendue : $error')),
      );
    } finally {
      if (mounted) setState(() => isAddingExamples = false);
    }
  }

  Future<void> remove(int id) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le rendez-vous ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(apiClientProvider).dio.delete('/appointments/$id');
      if (!mounted) return;
      await load();
      if (messenger == null || !mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Rendez-vous supprimé')),
      );
    } catch (e) {
      if (!mounted || messenger == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Impossible de supprimer : $e')),
      );
    }
  }

  Future<void> showRisk(int id) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .get('/appointments/$id/no-show-risk');
      final data = Map<String, dynamic>.from(response.data as Map);
      if (!mounted) return;
      final factors = (data['factors'] as List<dynamic>? ?? [])
          .map((f) => '• $f')
          .join('\n');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
              'Risque d\'absence : ${_riskLabel(data['level']?.toString())}'),
          content: Text(
            'Score : ${data['score']} / 100\n\n${factors.isEmpty ? 'Aucun facteur particulier.' : factors}',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted || messenger == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Impossible d\'estimer le risque : $e')),
      );
    }
  }

  String _riskLabel(String? level) {
    switch (level) {
      case 'HIGH':
        return 'élevé';
      case 'MEDIUM':
        return 'modéré';
      default:
        return 'faible';
    }
  }

  List<String> _suggestedSpecialties(String rawReason) {
    final text = rawReason.toLowerCase();
    const rules = <String, List<String>>{
      'Cardiologie': ['cœur', 'coeur', 'cardio', 'palpit', 'tension'],
      'Dermatologie': ['peau', 'bouton', 'eczéma', 'eczema', 'acné', 'acne'],
      'Ophtalmologie': ['œil', 'oeil', 'yeux', 'vision', 'vue'],
      'ORL': ['oreille', 'gorge', 'sinus', 'audition'],
      'Gastro-entérologie': ['digestion', 'estomac', 'ventre', 'reflux'],
      'Neurologie': ['migraine', 'maux de tête', 'vertige', 'neurolog'],
      'Orthopédie': ['dos', 'genou', 'épaule', 'epaule', 'articulation'],
      'Dentisterie': ['dent', 'gencive'],
    };

    return rules.entries
        .where((entry) => entry.value.any(text.contains))
        .map((entry) => entry.key)
        .take(3)
        .toList();
  }

  void suggestSpecialty() {
    final rawReason = reason.text.trim();
    if (rawReason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Saisissez d’abord le motif du rendez-vous')),
      );
      return;
    }

    final suggestions = _suggestedSpecialties(rawReason);
    if (suggestions.isNotEmpty &&
        appointmentTypes.contains(suggestions.first)) {
      setState(() => selectedAppointmentType = suggestions.first);
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Suggestion de spécialité'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (suggestions.isEmpty)
              const Text('Aucune spécialité reconnue pour ce motif.')
            else ...[
              Text('Type sélectionné : ${suggestions.first}'),
              const SizedBox(height: 8),
              ...suggestions.map(
                (specialty) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $specialty'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Suggestion administrative par mots-clés; ce n’est ni un diagnostic ni un avis médical.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDateTime,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (!mounted || date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDateTime),
    );
    if (!mounted || time == null) return;

    setState(() {
      selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void suggestNextAvailableSlot() {
    if (doctor.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saisissez d’abord le nom du médecin')),
      );
      return;
    }

    final suggestedSlot = _findNextAvailableSlot();
    if (suggestedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Aucun créneau libre trouvé dans les 30 prochains jours')),
      );
      return;
    }

    setState(() => selectedDateTime = suggestedSlot);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Créneau proposé : ${_formatDateTime(suggestedSlot)}')),
    );
  }

  DateTime? _findNextAvailableSlot() {
    final now = DateTime.now();
    final searchEnd = now.add(const Duration(days: 30));
    final start = selectedDateTime.isAfter(now) ? selectedDateTime : now;
    var candidate = _normalizeSlot(start);
    final doctorName = doctor.text.trim().toLowerCase();
    final busySlots = items
        .where((appointment) {
          final status = (appointment['status'] ?? 'PLANNED').toString();
          final sameDoctor = (appointment['doctorName'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase() ==
              doctorName;
          final isBeingEdited =
              appointment['id']?.toString() == editingId?.toString();
          return sameDoctor && status != 'CANCELLED' && !isBeingEdited;
        })
        .map((appointment) => _parseDateTime(appointment['dateTime']))
        .whereType<DateTime>();

    while (candidate.isBefore(searchEnd)) {
      final candidateEnd = candidate.add(const Duration(minutes: 30));
      final isOccupied = busySlots.any((slot) =>
          slot.isBefore(candidateEnd) &&
          slot.add(const Duration(minutes: 30)).isAfter(candidate));
      if (!isOccupied) return candidate;

      candidate = _normalizeSlot(candidate.add(const Duration(minutes: 30)));
    }

    return null;
  }

  DateTime _normalizeSlot(DateTime value) {
    final roundedMinute = ((value.minute + 29) ~/ 30) * 30;
    var slot =
        DateTime(value.year, value.month, value.day, value.hour, roundedMinute);
    if (slot.hour < 9) {
      return DateTime(slot.year, slot.month, slot.day, 9);
    }
    if (slot.hour >= 17) {
      final nextDay = slot.add(const Duration(days: 1));
      slot = DateTime(nextDay.year, nextDay.month, nextDay.day, 9);
    }
    return slot;
  }

  void editAppointment(Map<String, dynamic> appointment) {
    final parsedDate = _parseDateTime(appointment['dateTime']) ??
        DateTime.now().add(const Duration(days: 1));

    setState(() {
      editingId = appointment['id'];
      selectedDoctorId = appointment['doctorId'] as int?;
      doctor.text = appointment['doctorName'] ?? '';
      reason.text = appointment['reason'] ?? '';
      final type = (appointment['appointmentType'] ?? '').toString();
      selectedAppointmentType =
          appointmentTypes.contains(type) ? type : 'Consultation générale';
      selectedStatus = appointment['status'] ?? 'PLANNED';
      selectedDateTime = parsedDate;
    });
  }

  void resetForm() {
    setState(() {
      editingId = null;
      selectedDoctorId = null;
      doctor.clear();
      reason.clear();
      selectedAppointmentType = 'Consultation générale';
      selectedStatus = 'PLANNED';
      selectedDateTime = DateTime.now().add(const Duration(days: 1));
    });
  }

  @override
  void initState() {
    super.initState();
    load();
    loadDirectory();
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null || value.toString().isEmpty) return null;
    return DateTime.tryParse(value.toString());
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Date non définie';
    final value = dateTime.toLocal();
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year;
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  List<dynamic> get filteredAppointments {
    final query = searchController.text.trim().toLowerCase();
    final filtered = items.where((appointment) {
      final status = (appointment['status'] ?? 'PLANNED').toString();
      final matchesFilter = selectedFilter == 'ALL' || status == selectedFilter;
      if (!matchesFilter) return false;

      if (query.isEmpty) return true;

      final doctorName =
          (appointment['doctorName'] ?? '').toString().toLowerCase();
      final reasonText = (appointment['reason'] ?? '').toString().toLowerCase();
      final appointmentType =
          (appointment['appointmentType'] ?? '').toString().toLowerCase();
      return doctorName.contains(query) ||
          reasonText.contains(query) ||
          appointmentType.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final da = _parseDateTime(a['dateTime']);
      final db = _parseDateTime(b['dateTime']);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    return filtered;
  }

  Map<String, int> get summary {
    int stat(String key) => (serverStats[key] as num?)?.toInt() ?? 0;

    return {
      'total': stat('total'),
      'upcoming': stat('upcoming'),
      'confirmed': stat('confirmed'),
      'cancelled': stat('cancelled'),
    };
  }

  List<DateTime> get weekDates {
    final start = DateTime(
      selectedAgendaDay.year,
      selectedAgendaDay.month,
      selectedAgendaDay.day,
    ).subtract(Duration(days: selectedAgendaDay.weekday - 1));

    return List.generate(7, (index) => start.add(Duration(days: index)));
  }

  List<dynamic> get appointmentsForSelectedDay {
    final startOfDay = DateTime(
      selectedAgendaDay.year,
      selectedAgendaDay.month,
      selectedAgendaDay.day,
    );
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final result = items.where((appointment) {
      final date = _parseDateTime(appointment['dateTime']);
      return date != null &&
          !date.isBefore(startOfDay) &&
          date.isBefore(endOfDay);
    }).toList();

    result.sort((a, b) {
      final da = _parseDateTime(a['dateTime']);
      final db = _parseDateTime(b['dateTime']);
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _formatDateTime(selectedDateTime);
    final filteredItems = filteredAppointments;
    final stats = summary;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F7F6),
      appBar: AppBar(
        title: const Text('Rendez-vous'),
        centerTitle: false,
        backgroundColor: const Color(0xFF07575E),
        foregroundColor: Colors.white,
        actions: [
          if (canOpenSecretariat)
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SecretaryAppointmentsPage(isAdmin: isAdmin),
                ),
              ),
              icon: const Icon(Icons.support_agent),
              tooltip: 'Espace secrétaire',
            ),
          IconButton(
            onPressed: isAddingExamples ? null : addSampleAppointments,
            icon: isAddingExamples
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.playlist_add),
            tooltip: 'Ajouter 10 rendez-vous d’exemple',
          ),
          IconButton(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: SafeArea(
        child: Scrollbar(
          controller: _appointmentsScrollController,
          thumbVisibility: true,
          interactive: true,
          child: SingleChildScrollView(
            controller: _appointmentsScrollController,
            child: Column(
              children: [
                _appointmentsHero(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      _summaryCard('Total', stats['total'] ?? 0,
                          const Color(0xFF0C7778), Icons.calendar_month),
                      const SizedBox(width: 10),
                      _summaryCard('À venir', stats['upcoming'] ?? 0,
                        const Color(0xFFDB8A3B), Icons.event_available),
                      const SizedBox(width: 10),
                      _summaryCard('Confirmés', stats['confirmed'] ?? 0,
                        const Color(0xFF398A67), Icons.check_circle),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Rechercher un médecin ou un motif',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    children: [
                      _filterChip('ALL', 'Tout'),
                      _filterChip('PLANNED', 'Planifiés'),
                      _filterChip('CONFIRMED', 'Confirmés'),
                      _filterChip('COMPLETED', 'Terminés'),
                      _filterChip('CANCELLED', 'Annulés'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ToggleButtons(
                    isSelected: [agendaMode, !agendaMode],
                    onPressed: (index) {
                      setState(() => agendaMode = index == 0);
                    },
                    borderRadius: BorderRadius.circular(16),
                    selectedColor: Colors.white,
                    fillColor: const Color(0xFF0C7778),
                    color: const Color(0xFF0C7778),
                    constraints:
                        const BoxConstraints(minHeight: 42, minWidth: 120),
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month_outlined),
                            SizedBox(width: 8),
                            Text('Agenda'),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Icon(Icons.list_alt_outlined),
                            SizedBox(width: 8),
                            Text('Liste'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Form(
                    key: _formKey,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.medical_services_outlined,
                                  color: Color(0xFF0C7778)),
                              const SizedBox(width: 10),
                              Text(
                                editingId == null
                                    ? 'Nouveau rendez-vous'
                                    : 'Modifier le rendez-vous',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: doctor,
                            onChanged: (_) => selectedDoctorId = null,
                            decoration: InputDecoration(
                              labelText: 'Médecin',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.person_outline),
                              suffixIcon: registeredDoctors.isEmpty
                                  ? null
                                  : PopupMenuButton<Map>(
                                      tooltip: 'Choisir un médecin inscrit',
                                      icon: const Icon(Icons.arrow_drop_down),
                                      onSelected: (d) => setState(() {
                                        selectedDoctorId = d['id'] as int?;
                                        doctor.text = '${d['fullName']}';
                                      }),
                                      itemBuilder: (_) => registeredDoctors
                                          .map((d) => PopupMenuItem<Map>(
                                                value: d as Map,
                                                child: Text('${d['fullName']}'),
                                              ))
                                          .toList(),
                                    ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Le nom du médecin est obligatoire';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: selectedAppointmentType,
                            decoration: const InputDecoration(
                              labelText: 'Type de rendez-vous',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            items: appointmentTypes
                                .map((type) => DropdownMenuItem(
                                      value: type,
                                      child: Text(type),
                                    ))
                                .toList(),
                            onChanged: (type) {
                              if (type != null) {
                                setState(() => selectedAppointmentType = type);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: reason,
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Motif',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.note_alt_outlined),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: suggestSpecialty,
                              icon: const Icon(Icons.auto_awesome_outlined),
                              label: const Text('Suggérer une spécialité'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: pickDate,
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Date et heure',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.event),
                                    ),
                                    child: Text(dateText),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: selectedStatus,
                                  decoration: const InputDecoration(
                                    labelText: 'Statut',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'PLANNED',
                                        child: Text('Planifié')),
                                    DropdownMenuItem(
                                        value: 'CONFIRMED',
                                        child: Text('Confirmé')),
                                    DropdownMenuItem(
                                        value: 'CANCELLED',
                                        child: Text('Annulé')),
                                    DropdownMenuItem(
                                        value: 'COMPLETED',
                                        child: Text('Terminé')),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => selectedStatus = value);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: suggestNextAvailableSlot,
                              icon: const Icon(Icons.event_available_outlined),
                              label: const Text('Proposer un créneau libre'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: save,
                                  icon: Icon(editingId == null
                                      ? Icons.add
                                      : Icons.save),
                                  label: Text(editingId == null
                                      ? 'Ajouter'
                                      : 'Enregistrer'),
                                ),
                              ),
                              if (editingId != null) ...[
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: resetForm,
                                  child: const Text('Annuler'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                agendaMode
                    ? Container(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 90,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: weekDates.length,
                                itemBuilder: (_, index) {
                                  final day = weekDates[index];
                                  final isSelected = day.year ==
                                          selectedAgendaDay.year &&
                                      day.month == selectedAgendaDay.month &&
                                      day.day == selectedAgendaDay.day;
                                  final appointmentCount =
                                      items.where((appointment) {
                                    final date =
                                        _parseDateTime(appointment['dateTime']);
                                    if (date == null) return false;
                                    return date.year == day.year &&
                                        date.month == day.month &&
                                        date.day == day.day;
                                  }).length;

                                  return Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: InkWell(
                                      onTap: () => setState(
                                          () => selectedAgendaDay = day),
                                      child: Container(
                                        width: 72,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        decoration: BoxDecoration(
                                            color: isSelected
                                              ? const Color(0xFF0C7778)
                                              : Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          border: Border.all(
                                            color: isSelected
                                              ? const Color(0xFF0C7778)
                                                : Colors.grey.shade300,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '${day.day}',
                                              style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w700,
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.black,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _shortWeekday(day.weekday),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.grey[600],
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '$appointmentCount',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isSelected
                                                  ? Colors.white
                                                  : const Color(0xFF0C7778),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                            appointmentsForSelectedDay.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.event_busy_outlined,
                                            size: 42, color: Colors.grey[400]),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Aucun rendez-vous pour ce jour',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  color: Colors.grey[600]),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount:
                                        appointmentsForSelectedDay.length,
                                    itemBuilder: (_, i) {
                                      final item =
                                          appointmentsForSelectedDay[i];
                                      final status =
                                          (item['status'] ?? 'PLANNED')
                                              .toString();
                                      final doctorName =
                                          (item['doctorName'] ?? '').toString();
                                      final reasonText =
                                          (item['reason'] ?? '').toString();
                                      final appointmentType =
                                          (item['appointmentType'] ?? '')
                                              .toString();
                                      final parsedDate =
                                          _parseDateTime(item['dateTime']);
                                      final dateText =
                                          _formatDateTime(parsedDate);

                                      return Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.04),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 8),
                                          leading: CircleAvatar(
                                            radius: 24,
                                            backgroundColor:
                                                _statusColor(status)
                                                    .withValues(alpha: 0.12),
                                            child: Icon(
                                                Icons
                                                    .medical_information_outlined,
                                                color: _statusColor(status)),
                                          ),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  doctorName,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700),
                                                ),
                                              ),
                                              Chip(
                                                label:
                                                    Text(_statusLabel(status)),
                                                backgroundColor:
                                                    _statusColor(status),
                                                labelStyle: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11),
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            ],
                                          ),
                                          subtitle: Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(Icons.schedule,
                                                        size: 16,
                                                        color: Colors.grey),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                        child: Text(dateText)),
                                                  ],
                                                ),
                                                if (appointmentType
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.category_outlined,
                                                        size: 16,
                                                        color: Color(0xFF0C7778),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          appointmentType,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                                if (reasonText.isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Text(reasonText,
                                                      maxLines: 2,
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                ],
                                              ],
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (status == 'PLANNED' ||
                                                  status == 'CONFIRMED')
                                                IconButton(
                                                  tooltip: 'Risque d\'absence',
                                                  onPressed: () =>
                                                      showRisk(item['id']),
                                                  icon: const Icon(
                                                      Icons.insights_outlined),
                                                ),
                                              IconButton(
                                                tooltip: 'Modifier',
                                                onPressed: () =>
                                                    editAppointment(item),
                                                icon: const Icon(
                                                    Icons.edit_outlined),
                                              ),
                                              IconButton(
                                                tooltip: 'Supprimer',
                                                onPressed: () =>
                                                    remove(item['id']),
                                                icon: const Icon(
                                                    Icons.delete_outline),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ],
                        ),
                      )
                    : filteredItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded,
                                    size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 12),
                                Text(
                                  'Aucun rendez-vous trouvé',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            itemCount: filteredItems.length,
                            itemBuilder: (_, i) {
                              final item = filteredItems[i];
                              final status =
                                  (item['status'] ?? 'PLANNED').toString();
                              final doctorName =
                                  (item['doctorName'] ?? '').toString();
                              final reasonText =
                                  (item['reason'] ?? '').toString();
                              final appointmentType =
                                  (item['appointmentType'] ?? '').toString();
                              final parsedDate =
                                  _parseDateTime(item['dateTime']);
                              final dateText = _formatDateTime(parsedDate);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  leading: CircleAvatar(
                                    radius: 24,
                                    backgroundColor: _statusColor(status)
                                        .withValues(alpha: 0.12),
                                    child: Icon(
                                        Icons.medical_information_outlined,
                                        color: _statusColor(status)),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          doctorName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      Chip(
                                        label: Text(_statusLabel(status)),
                                        backgroundColor: _statusColor(status),
                                        labelStyle: const TextStyle(
                                            color: Colors.white, fontSize: 11),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.schedule,
                                                size: 16, color: Colors.grey),
                                            const SizedBox(width: 6),
                                            Expanded(child: Text(dateText)),
                                          ],
                                        ),
                                        if (appointmentType.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.category_outlined,
                                                size: 16,
                                                color: Color(0xFF0C7778),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  appointmentType,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        if (reasonText.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(reasonText,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis),
                                        ],
                                      ],
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (status == 'PLANNED' ||
                                          status == 'CONFIRMED')
                                        IconButton(
                                          tooltip: 'Risque d\'absence',
                                          onPressed: () => showRisk(item['id']),
                                          icon: const Icon(
                                              Icons.insights_outlined),
                                        ),
                                      IconButton(
                                        tooltip: 'Modifier',
                                        onPressed: () => editAppointment(item),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Supprimer',
                                        onPressed: () => remove(item['id']),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(String label, int value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final isSelected = selectedFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() => selectedFilter = value);
        },
        selectedColor: const Color(0xFF0C7778),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF0C7778),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _appointmentsHero() {
    const deepTeal = Color(0xFF07575E);
    const brightTeal = Color(0xFF0C7778);

    return Container(
      height: 292,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [deepTeal, brightTeal],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -48,
            bottom: -96,
            child: Container(
              width: 270,
              height: 270,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 26,
                ),
              ),
            ),
          ),
          Positioned(
            right: 24,
            bottom: 20,
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: const Color(0xFF65D3CA),
                borderRadius: BorderRadius.circular(34),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                size: 62,
                color: Color(0xFF07575E),
              ),
            ),
          ),
          Positioned(
            right: 116,
            bottom: 28,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFFF0B66A),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.access_time_rounded,
                color: Color(0xFF07575E),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'SUIVI DES RENDEZ-VOUS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Votre santé,\nbien planifiée.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const SizedBox(
                  width: 245,
                  child: Text(
                    'Organisez vos consultations et gardez votre suivi à portée de main.',
                    style: TextStyle(
                      color: Color(0xFFC6E8E6),
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'CONFIRMED':
        return Colors.green;
      case 'CANCELLED':
        return Colors.red;
      case 'COMPLETED':
        return Colors.blue;
      case 'PLANNED':
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'CONFIRMED':
        return 'Confirmé';
      case 'CANCELLED':
        return 'Annulé';
      case 'COMPLETED':
        return 'Terminé';
      case 'PLANNED':
      default:
        return 'Planifié';
    }
  }

  String _shortWeekday(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Lun';
      case DateTime.tuesday:
        return 'Mar';
      case DateTime.wednesday:
        return 'Mer';
      case DateTime.thursday:
        return 'Jeu';
      case DateTime.friday:
        return 'Ven';
      case DateTime.saturday:
        return 'Sam';
      case DateTime.sunday:
      default:
        return 'Dim';
    }
  }
}

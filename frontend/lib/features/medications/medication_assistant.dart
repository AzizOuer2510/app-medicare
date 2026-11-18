import 'medication.dart';

class MedicationAssistant {
  const MedicationAssistant();

  String answer(
    String question, {
    required List<Medication> medications,
    required List<Prescription> prescriptions,
  }) {
    final normalized = _normalize(question);
    if (normalized.isEmpty) {
      return 'Posez une question sur l’organisation de vos traitements, les '
          'champs d’une prescription ou une information déjà enregistrée.';
    }

    if (_asksForClinicalDecision(normalized)) {
      return 'Je ne peux pas recommander une dose, un changement de traitement, '
          'un arrêt ou une association de médicaments. Suivez votre prescription '
          'et demandez conseil à votre médecin ou à votre pharmacien. En cas '
          'd’urgence, contactez les services d’urgence.';
    }

    final medication = _findMedication(normalized, medications);
    if (medication != null) {
      return _medicationInformation(normalized, medication);
    }

    if (_asksAboutPrescription(normalized)) {
      return _prescriptionInformation(prescriptions);
    }

    final fieldAnswer = _fieldExplanation(normalized);
    if (fieldAnswer != null) return fieldAnswer;

    if (_asksAboutOrganization(normalized)) {
      return 'Pour organiser un traitement, ouvrez Médicaments puis ajoutez '
          'les informations telles qu’elles figurent sur votre prescription : '
          'horaires, fréquence, dates et instructions. Vous pouvez ensuite '
          'consulter les prises et gérer les rappels. Je ne peux pas définir '
          'ni modifier ces consignes.';
    }

    return 'Je peux vous aider à retrouver le nom, les horaires, les dates, les '
        'instructions ou le stock d’un médicament enregistré, expliquer les '
        'champs d’une prescription ou décrire l’organisation des rappels. '
        'Je ne fournis pas de conseil médical ni de dose.';
  }

  Medication? _findMedication(String query, List<Medication> medications) {
    for (final medication in medications) {
      final name = _normalize(medication.name);
      if (name.isNotEmpty && query.contains(name)) return medication;
    }
    return null;
  }

  String _medicationInformation(String query, Medication medication) {
    if (_containsAny(query, ['horaire', 'heure', 'rappel', 'prise'])) {
      final times = medication.reminderTimes
          .map((time) => time.length >= 5 ? time.substring(0, 5) : time)
          .toList();
      return times.isEmpty
          ? 'Aucun horaire n’est enregistré pour ${medication.name}.'
          : 'Horaires enregistrés pour ${medication.name} : '
              '${times.join(', ')}. Ces informations reprennent votre '
              'traitement enregistré; elles ne constituent pas une '
              'recommandation médicale.';
    }

    if (_containsAny(query, ['stock', 'quantite', 'quantite restante'])) {
      if (!medication.stockTracked || medication.currentQuantity == null) {
        return 'Aucun suivi de stock n’est configuré pour ${medication.name}.';
      }
      final warning =
          medication.isLowStock ? ' Le seuil configuré est atteint.' : '';
      return 'Stock enregistré pour ${medication.name} : '
          '${medication.currentQuantity} ${medication.quantityUnit ?? ''}.'
          '$warning';
    }

    if (_containsAny(query, ['date', 'debut', 'fin', 'periode'])) {
      return 'Période enregistrée pour ${medication.name} : '
          '${_date(medication.startDate)} à ${_date(medication.endDate)}.';
    }

    if (_containsAny(query, ['instruction', 'note', 'consigne'])) {
      final information = [
        if ((medication.instructions ?? '').trim().isNotEmpty)
          'Instructions : ${medication.instructions}',
        if ((medication.notes ?? '').trim().isNotEmpty)
          'Note : ${medication.notes}',
      ];
      return information.isEmpty
          ? 'Aucune instruction ni note n’est enregistrée pour ${medication.name}.'
          : '${medication.name} — ${information.join(' ')}';
    }

    final details = <String>[
      'Informations enregistrées pour ${medication.name}.',
      if ((medication.dosage ?? '').trim().isNotEmpty)
        'Dosage noté : ${medication.dosage}.',
      if ((medication.frequency ?? '').trim().isNotEmpty)
        'Fréquence notée : ${medication.frequency}.',
      if (medication.reminderTimes.isNotEmpty)
        'Horaires : ${medication.reminderTimes.map((time) => time.length >= 5 ? time.substring(0, 5) : time).join(', ')}.',
      'Statut : ${_status(medication.status)}.',
    ];
    return '${details.join(' ')} Ces informations sont recopiées du dossier '
        'et ne remplacent pas la prescription.';
  }

  String _prescriptionInformation(List<Prescription> prescriptions) {
    if (prescriptions.isEmpty) {
      return 'Aucune prescription ne vous est attribuée dans l’application. '
          'Demandez à votre médecin de la créer ou de l’associer à votre compte.';
    }
    final latest = prescriptions.first;
    final diagnosis = (latest.diagnosis ?? '').trim();
    return 'Vous avez ${prescriptions.length} prescription(s) enregistrée(s). '
        'La plus récente est datée du ${_date(latest.prescriptionDate)}'
        '${diagnosis.isEmpty ? '.' : ' (champ diagnostic : $diagnosis).'} '
        'Pour une interprétation médicale, demandez au professionnel qui l’a établie.';
  }

  String? _fieldExplanation(String query) {
    if (_containsAny(query, ['diagnostic', 'diagnosis'])) {
      return 'Le champ « diagnostic » correspond à l’information médicale '
          'saisie par le professionnel sur la prescription. Demandez-lui '
          'd’expliquer sa signification dans votre situation.';
    }
    if (_containsAny(query, ['posologie', 'dosage', 'dose'])) {
      return 'Le champ « dosage » ou « posologie » reprend les indications '
          'figurant sur la prescription. Je peux retrouver une valeur déjà '
          'enregistrée, mais je ne peux pas déterminer ni modifier une dose.';
    }
    if (_containsAny(query, ['frequence', 'frequence par jour'])) {
      return 'La fréquence indique le rythme d’administration qui a été '
          'enregistré à partir de la prescription. En cas de doute, vérifiez '
          'le document original ou contactez votre pharmacien.';
    }
    if (_containsAny(query, ['note', 'notes'])) {
      return 'Les notes sont des informations complémentaires enregistrées '
          'avec la prescription ou le traitement. Elles ne remplacent pas '
          'les indications officielles du professionnel.';
    }
    if (_containsAny(query, ['date de prescription', 'date prescription'])) {
      return 'La date de prescription correspond à la date enregistrée pour '
          'le document dans l’application. Elle ne confirme pas à elle seule '
          'qu’un traitement est toujours en cours.';
    }
    if (_containsAny(query, ['ordonnance', 'prescription'])) {
      return 'Une prescription regroupe les informations saisies par le '
          'professionnel de santé. Dans l’application, consultez la section '
          'Prescriptions. Pour toute interprétation ou correction, contactez '
          'le prescripteur.';
    }
    return null;
  }

  bool _asksForClinicalDecision(String query) {
    return _containsAny(query, [
      'augmenter la dose',
      'augmenter dosage',
      'augmenter ma dose',
      'diminuer la dose',
      'diminuer dosage',
      'diminuer ma dose',
      'reduire la dose',
      'modifier la dose',
      'modifier ma dose',
      'changer la dose',
      'changer ma dose',
      'changer dosage',
      'arreter le traitement',
      'arreter le medicament',
      'puis je arreter',
      'dois je arreter',
      'suspendre le traitement',
      'interrompre le traitement',
      'remplacer le medicament',
      'remplacer mon traitement',
      'quel medicament prendre',
      'que dois je prendre',
      'dois je prendre',
      'puis je prendre',
      'combien dois je prendre',
      'quelle dose dois je prendre',
      'quelle dose prendre',
      'interaction entre',
      'associer les medicaments',
      'compatible avec',
      'effet secondaire',
      'effets secondaires',
      'symptome',
      'symptomes',
    ]);
  }

  bool _asksAboutPrescription(String query) =>
      _containsAny(query, ['ordonnance', 'prescription']);

  bool _asksAboutOrganization(String query) => _containsAny(query, [
        'organiser',
        'organisation',
        'rappel',
        'rappels',
        'planning',
        'calendrier',
        'suivre mes prises',
        'comment utiliser',
      ]);

  bool _containsAny(String text, List<String> phrases) =>
      phrases.any(text.contains);

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâä]'), 'a')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[òóôö]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _date(DateTime? date) {
    if (date == null) return 'non précisée';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _status(String status) => switch (status.toLowerCase()) {
        'suspended' || 'paused' => 'en pause',
        'discontinued' => 'arrêté',
        'completed' || 'finished' => 'terminé',
        'active' => 'en cours',
        _ => status,
      };
}

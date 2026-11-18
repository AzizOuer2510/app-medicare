import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Patient consulté par un médecin. Absent quand l'utilisateur consulte son propre suivi.
class HealthPatient {
  const HealthPatient({required this.id, required this.name});
  final int id;
  final String name;
}

/// Transmet le patient consulté à toutes les pages du module.
/// Sans HealthScope (ou avec patient == null) : suivi personnel de l'utilisateur.
class HealthScope extends InheritedWidget {
  const HealthScope({super.key, required this.patient, required super.child});

  final HealthPatient? patient;

  /// Utilisable aussi dans initState (n'enregistre pas de dépendance).
  static HealthPatient? patientOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HealthScope>()?.patient;

  /// Vrai quand un médecin consulte le suivi d'un de ses patients.
  static bool isDoctorView(BuildContext context) => patientOf(context) != null;

  @override
  bool updateShouldNotify(HealthScope oldWidget) =>
      oldWidget.patient?.id != patient?.id;
}

/// Ajoute `patientId` aux paramètres de requête en vue médecin.
Map<String, dynamic> patientQuery(BuildContext context,
    [Map<String, dynamic> extra = const {}]) {
  final patient = HealthScope.patientOf(context);
  return {...extra, if (patient != null) 'patientId': patient.id};
}

/// Ouvre une page du module en conservant le patient consulté.
Future<T?> pushHealthPage<T>(BuildContext context, Widget page) {
  final patient = HealthScope.patientOf(context);
  return Navigator.push<T>(
    context,
    MaterialPageRoute(
        builder: (_) => HealthScope(patient: patient, child: page)),
  );
}

/// Incrémenté à chaque ajout / modification / suppression de données santé ou
/// nutrition : les onglets ouverts se rechargent automatiquement.
final healthRevisionProvider = StateProvider<int>((ref) => 0);

void notifyHealthDataChanged(WidgetRef ref) =>
    ref.read(healthRevisionProvider.notifier).state++;

/// Les modèles IA locaux (Ollama) peuvent mettre plusieurs minutes à répondre.
/// Sur le web, le délai de connexion court jusqu'à la réception de la réponse :
/// ce client reprend la configuration de l'API (jeton, intercepteurs) avec
/// des délais adaptés à l'IA.
Dio aiDio(WidgetRef ref) {
  final base = ref.read(apiClientProvider).dio;
  final dio = Dio(base.options.copyWith(
    connectTimeout: const Duration(minutes: 5),
    sendTimeout: const Duration(minutes: 2),
    receiveTimeout: const Duration(minutes: 5),
  ));
  // Un nouveau Dio contient déjà ses intercepteurs par défaut : on n'ajoute que
  // ceux de l'application (jeton d'authentification, expiration de session).
  final defaults = dio.interceptors.map((i) => i.runtimeType).toSet();
  dio.interceptors.addAll(
      base.interceptors.where((i) => !defaults.contains(i.runtimeType)));
  return dio;
}

const _fieldLabels = {
  'weight': 'poids',
  'heartRate': 'fréquence cardiaque',
  'systolic': 'tension systolique',
  'diastolic': 'tension diastolique',
  'temperature': 'température',
  'glycemia': 'glycémie',
  'calories': 'calories',
  'protein': 'protéines',
  'carbohydrates': 'glucides',
  'fat': 'lipides',
  'fiber': 'fibres',
  'quantityMl': 'quantité d’eau',
  'heightCm': 'taille',
  'targetWeight': 'poids cible',
  'dailyCalorieGoal': 'objectif calories',
  'dailyWaterGoalMl': 'objectif eau',
};

String healthErrorMessage(Object error,
    {String fallback = 'Une erreur est survenue. Réessayez.'}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final fields = data['fields'];
      if (fields is Map && fields.isNotEmpty) {
        final names = fields.keys
            .map((key) => _fieldLabels[key] ?? key.toString())
            .join(', ');
        return 'Valeur invalide : $names.';
      }
      final message = data['message'];
      if (message is String && message.isNotEmpty && message != 'Unexpected server error') {
        return message;
      }
    }
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return 'Serveur injoignable. Vérifiez que le backend est démarré.';
      case DioExceptionType.receiveTimeout:
        return 'Le serveur a mis trop de temps à répondre.';
      default:
        break;
    }
  }
  return fallback;
}

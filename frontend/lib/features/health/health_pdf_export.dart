import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/providers.dart';
import '../auth/authentication_state.dart';
import 'health_api.dart';
import 'health_theme.dart';

/// Demande la période puis génère et ouvre le rapport PDF (impression ou
/// enregistrement selon la plateforme).
Future<void> showHealthPdfExportDialog(BuildContext context, WidgetRef ref,
    {HealthPatient? patient}) async {
  final days = await showDialog<int>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Exporter mes données en PDF'),
      children: [
        for (final (value, label) in const [
          (7, '7 derniers jours'),
          (30, '30 derniers jours'),
          (90, '3 derniers mois'),
          (180, '6 derniers mois'),
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(label),
            ),
          ),
      ],
    ),
  );
  if (days == null || !context.mounted) return;
  try {
    final bytes = await buildHealthReport(ref, days, patient: patient);
    await Printing.layoutPdf(
      name: 'MediCare_suivi_sante_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      onLayout: (_) async => bytes,
    );
  } catch (error) {
    if (context.mounted) {
      showHealthSnack(context,
          healthErrorMessage(error, fallback: 'La génération du PDF a échoué.'),
          error: true);
    }
  }
}

/// Les polices PDF standard ne contiennent pas les espaces insécables fines.
String _pdfNum(num? value, {int decimals = 1}) => formatNumber(value, decimals: decimals)
    .replaceAll(' ', ' ')
    .replaceAll(' ', ' ')
    .replaceAll('—', '-');

Future<Uint8List> buildHealthReport(WidgetRef ref, int days,
    {HealthPatient? patient}) async {
  final dio = ref.read(apiClientProvider).dio;
  final query = {'days': days, if (patient != null) 'patientId': patient.id};
  final goalQuery = {if (patient != null) 'patientId': patient.id};
  final results = await Future.wait([
    dio.get('/health-records/history', queryParameters: query),
    dio.get('/meals/history', queryParameters: query),
    dio.get('/meals/stats/daily', queryParameters: query),
    dio.get('/hydration/history', queryParameters: query),
    dio.get('/health-goals', queryParameters: goalQuery),
  ]);
  final records = asMapList(results[0].data);
  final meals = asMapList(results[1].data);
  final nutrition = asMapList(results[2].data);
  final water = asMapList(results[3].data);
  final goal = asMap(results[4].data);
  final user = ref.read(authenticationStateProvider).valueOrNull;
  final patientName = patient?.name ?? user?.fullName ?? '';
  final doctorName = patient != null ? user?.fullName : null;

  pw.MemoryImage? logo;
  try {
    final data = await rootBundle.load('assets/images/medicare_logo.png');
    logo = pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {}

  const teal = PdfColor.fromInt(0xFF07575E);
  const light = PdfColor.fromInt(0xFFF1F7F6);
  final now = DateTime.now();
  final from = now.subtract(Duration(days: days - 1));
  final dateFmt = DateFormat('dd/MM/yyyy');

  List<double> values(String field) =>
      records.map((r) => asDouble(r[field])).whereType<double>().toList();

  pw.TableRow statRow(String label, List<double> v, String unit, int decimals) {
    String f(double x) => _pdfNum(x, decimals: decimals);
    if (v.isEmpty) {
      return pw.TableRow(children: [
        _cell(label), _cell('-'), _cell('-'), _cell('-'), _cell('-'), _cell('0'),
      ]);
    }
    final avg = v.reduce((a, b) => a + b) / v.length;
    final minV = v.reduce((a, b) => a < b ? a : b);
    final maxV = v.reduce((a, b) => a > b ? a : b);
    return pw.TableRow(children: [
      _cell(label),
      _cell('${f(v.last)} $unit'),
      _cell('${f(minV)} $unit'),
      _cell('${f(avg)} $unit'),
      _cell('${f(maxV)} $unit'),
      _cell('${v.length}'),
    ]);
  }

  double sum(List<Map<String, dynamic>> list, String key) =>
      list.fold(0, (s, d) => s + (asDouble(d[key]) ?? 0));
  final daysWithMeals =
      nutrition.where((d) => (asDouble(d['mealCount']) ?? 0) > 0).length;
  final divisor = daysWithMeals == 0 ? 1 : daysWithMeals;
  final avgWater = averageWaterPerDay(water);

  final doc = pw.Document(
    title: 'MediCare - Suivi santé et nutrition',
    author: doctorName ?? patientName,
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: teal, width: 1.5)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) pw.Image(logo, height: 46),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Rapport - Suivi santé et nutrition',
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold, color: teal)),
                  pw.Text(
                      'Patient : $patientName   |   Période : ${dateFmt.format(from)} au ${dateFmt.format(now)}'
                      '${doctorName == null ? '' : '   |   Édité par $doctorName'}',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Généré le ${DateFormat('dd/MM/yyyy à HH:mm').format(now)} - données indicatives, sans valeur de diagnostic',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.Text('Page ${context.pageNumber}/${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ],
      ),
      build: (context) {
        final systolic = <double>[];
        final diastolic = <double>[];
        for (final r in records) {
          final s = asDouble(r['systolic']);
          final d = asDouble(r['diastolic']);
          if (s != null) systolic.add(s);
          if (d != null) diastolic.add(d);
        }
        return [
          _title('Objectifs'),
          pw.Text(
            'Taille : ${goal['heightCm'] == null ? '-' : '${_pdfNum(asDouble(goal['heightCm']), decimals: 0)} cm'}   |   '
            'Poids cible : ${goal['targetWeight'] == null ? '-' : '${_pdfNum(asDouble(goal['targetWeight']))} kg'}   |   '
            'Calories : ${_pdfNum(asDouble(goal['dailyCalorieGoal']), decimals: 0)} kcal/j   |   '
            'Eau : ${_pdfNum(asDouble(goal['dailyWaterGoalMl']), decimals: 0)} ml/j',
            style: const pw.TextStyle(fontSize: 10),
          ),
          _title('Statistiques des mesures'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: light),
                children: [
                  for (final h in ['Mesure', 'Dernière', 'Min', 'Moyenne', 'Max', 'Nb'])
                    _cell(h, bold: true),
                ],
              ),
              statRow('Poids', values('weight'), 'kg', 1),
              statRow('Tension systolique', systolic, 'mmHg', 0),
              statRow('Tension diastolique', diastolic, 'mmHg', 0),
              statRow('Fréquence cardiaque', values('heartRate'), 'bpm', 0),
              statRow('Température', values('temperature'), '°C', 1),
              statRow('Glycémie', values('glycemia'), 'g/L', 2),
            ],
          ),
          _title('Nutrition et hydratation'),
          pw.Bullet(
              text: 'Repas enregistrés : ${meals.length} '
                  '(${_pdfNum(meals.length / divisor)} par jour en moyenne)',
              style: const pw.TextStyle(fontSize: 10)),
          pw.Bullet(
              text: 'Calories estimées : ${_pdfNum(sum(nutrition, 'totalCalories') / divisor, decimals: 0)} kcal par jour '
                  '(sur $daysWithMeals jours avec repas)',
              style: const pw.TextStyle(fontSize: 10)),
          pw.Bullet(
              text: 'Moyennes par jour : protéines ${_pdfNum(sum(nutrition, 'totalProtein') / divisor)} g, '
                  'glucides ${_pdfNum(sum(nutrition, 'totalCarbohydrates') / divisor)} g, '
                  'lipides ${_pdfNum(sum(nutrition, 'totalFat') / divisor)} g, '
                  'fibres ${_pdfNum(sum(nutrition, 'totalFiber') / divisor)} g',
              style: const pw.TextStyle(fontSize: 10)),
          pw.Bullet(
              text: 'Hydratation moyenne : ${_pdfNum(avgWater / 1000, decimals: 2)} L par jour '
                  '(objectif ${_pdfNum((asDouble(goal['dailyWaterGoalMl']) ?? 2000) / 1000, decimals: 2)} L)',
              style: const pw.TextStyle(fontSize: 10)),
          _title('Historique des mesures'),
          if (records.isEmpty)
            pw.Text('Aucune mesure sur la période.', style: const pw.TextStyle(fontSize: 10))
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: light),
                  children: [
                    for (final h in ['Date', 'Poids', 'Tension', 'FC', 'Temp.', 'Glycémie'])
                      _cell(h, bold: true),
                  ],
                ),
                for (final r in records.reversed)
                  pw.TableRow(children: [
                    _cell(() {
                      final d = parseApiDateTime(r['recordedAt']);
                      return d == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(d);
                    }()),
                    _cell(r['weight'] == null ? '' : '${_pdfNum(asDouble(r['weight']))} kg'),
                    _cell(r['systolic'] == null ? '' : '${r['systolic']}/${r['diastolic'] ?? '?'}'),
                    _cell(r['heartRate'] == null ? '' : '${r['heartRate']} bpm'),
                    _cell(r['temperature'] == null ? '' : '${_pdfNum(asDouble(r['temperature']))} °C'),
                    _cell(r['glycemia'] == null ? '' : '${_pdfNum(asDouble(r['glycemia']), decimals: 2)} g/L'),
                  ]),
              ],
            ),
          _title('Journal alimentaire'),
          if (meals.isEmpty)
            pw.Text('Aucun repas sur la période.', style: const pw.TextStyle(fontSize: 10))
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
              columnWidths: const {
                0: pw.FixedColumnWidth(70),
                1: pw.FixedColumnWidth(70),
                2: pw.FlexColumnWidth(),
                3: pw.FixedColumnWidth(50),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: light),
                  children: [
                    for (final h in ['Date', 'Repas', 'Aliments', 'kcal']) _cell(h, bold: true),
                  ],
                ),
                for (final m in meals)
                  pw.TableRow(children: [
                    _cell(() {
                      final d = DateTime.tryParse(m['mealDate']?.toString() ?? '');
                      return d == null ? '' : '${dateFmt.format(d)} ${shortTime(m['mealTime'])}';
                    }()),
                    _cell(mealTypeLabels[m['mealType']] ?? ''),
                    _cell(_clean(m['description']?.toString() ?? '')),
                    _cell(m['calories'] == null ? '' : _pdfNum(asDouble(m['calories']), decimals: 0)),
                  ]),
              ],
            ),
        ];
      },
    ),
  );
  return doc.save();
}

/// Retire les caractères non pris en charge par la police PDF standard.
String _clean(String text) => text
    .replaceAll(' ', ' ')
    .replaceAll(' ', ' ')
    .replaceAll(RegExp(r'[^\u0000-ÿŒœ–—‘’“”…€]'), '');

pw.Widget _title(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFF0C7778))),
    );

pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(_clean(text),
          style: pw.TextStyle(
              fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );

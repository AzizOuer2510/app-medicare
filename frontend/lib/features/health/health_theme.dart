import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Palette et composants partagés du module « Suivi santé et nutrition ».
/// Ils reprennent le design des modules Rendez-vous et Médicaments
/// (sarcelle profond, cartes blanches arrondies, bandeau d'en-tête illustré).
class HealthColors {
  static const deepTeal = Color(0xFF07575E);
  static const brightTeal = Color(0xFF0C7778);
  static const accent = Color(0xFF65D3CA);
  static const amber = Color(0xFFF0B66A);
  static const background = Color(0xFFF1F7F6);
  static const ink = Color(0xFF17464D);
  static const muted = Color(0xFF557278);
  static const heroText = Color(0xFFC6E8E6);

  static const weight = Color(0xFF0C7778);
  static const heart = Color(0xFFD1495B);
  static const pressure = Color(0xFF4F6BD8);
  static const temperature = Color(0xFFDB8A3B);
  static const glycemia = Color(0xFF8E5BC9);
  static const water = Color(0xFF2B8FD6);
  static const calories = Color(0xFFDB8A3B);
  static const protein = Color(0xFF4F6BD8);
  static const carbs = Color(0xFFD9A21B);
  static const fat = Color(0xFFD1495B);
  static const fiber = Color(0xFF398A67);
  static const success = Color(0xFF398A67);
}

AppBar healthAppBar(String title,
    {List<Widget>? actions, PreferredSizeWidget? bottom}) {
  return AppBar(
    title: Text(title),
    centerTitle: false,
    backgroundColor: HealthColors.deepTeal,
    foregroundColor: Colors.white,
    actions: actions,
    bottom: bottom,
  );
}

/// Limite la largeur du contenu sur grand écran (web / desktop).
class HealthBody extends StatelessWidget {
  const HealthBody({super.key, required this.child, this.maxWidth = 820});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Bandeau d'en-tête dans le style des modules Rendez-vous et Médicaments.
class HealthHero extends StatelessWidget {
  const HealthHero({
    super.key,
    required this.label,
    required this.title,
    required this.subtitle,
    this.icon = Icons.monitor_heart_rounded,
    this.badgeIcon = Icons.restaurant_rounded,
    this.height = 260,
  });

  final String label;
  final String title;
  final String subtitle;
  final IconData icon;
  final IconData badgeIcon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [HealthColors.deepTeal, HealthColors.brightTeal],
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
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: HealthColors.accent,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, size: 58, color: HealthColors.deepTeal),
            ),
          ),
          Positioned(
            right: 108,
            bottom: 26,
            child: Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: HealthColors.amber,
                shape: BoxShape.circle,
              ),
              child: Icon(badgeIcon, color: HealthColors.deepTeal),
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
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 240,
                  child: Text(
                    subtitle,
                    style: const TextStyle(
                      color: HealthColors.heroText,
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
}

/// Carte blanche arrondie (même style que les formulaires de Rendez-vous).
class HealthCard extends StatelessWidget {
  const HealthCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onTap,
    this.color = Colors.white,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Padding(
      padding: margin,
      child: Material(
        color: color,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: borderColor == null
                  ? null
                  : Border.all(color: borderColor!, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Pastille d'icône colorée (carré arrondi), comme les cartes de synthèse.
class HealthIconBadge extends StatelessWidget {
  const HealthIconBadge(this.icon, this.color, {super.key, this.size = 40});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size * .32),
        ),
        child: Icon(icon, color: color, size: size * .55),
      );
}

class HealthSectionTitle extends StatelessWidget {
  const HealthSectionTitle(this.title, {super.key, this.trailing, this.icon});

  final String title;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: HealthColors.brightTeal, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: HealthColors.ink,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Carte de synthèse compacte (valeur + libellé), identique au module Rendez-vous.
class HealthSummaryTile extends StatelessWidget {
  const HealthSummaryTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.trailing,
    this.progress,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  final double? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return HealthCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              HealthIconBadge(icon, color, size: 36),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: HealthColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 5,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Puces de sélection dans le style du filtre de statut des rendez-vous.
class HealthChoiceChips<T> extends StatelessWidget {
  const HealthChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        padding: padding,
        scrollDirection: Axis.horizontal,
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(option.$2),
                selected: option.$1 == selected,
                onSelected: (_) => onSelected(option.$1),
                selectedColor: HealthColors.brightTeal,
                showCheckmark: false,
                backgroundColor: Colors.white,
                side: BorderSide(
                    color: HealthColors.brightTeal.withValues(alpha: .25)),
                labelStyle: TextStyle(
                  color: option.$1 == selected
                      ? Colors.white
                      : HealthColors.brightTeal,
                  fontWeight: option.$1 == selected
                      ? FontWeight.w600
                      : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HealthEmptyState extends StatelessWidget {
  const HealthEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return HealthCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: HealthColors.brightTeal),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: HealthColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: HealthColors.muted),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

class HealthErrorState extends StatelessWidget {
  const HealthErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => HealthEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Chargement impossible',
        message: message,
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Réessayer'),
        ),
      );
}

InputDecoration healthInputDecoration(String label,
    {IconData? icon, String? hint, String? suffix}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixText: suffix,
    prefixIcon: icon == null ? null : Icon(icon),
    filled: true,
    fillColor: const Color(0xFFF8FAFB),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFDCE6EA)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFDCE6EA)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: HealthColors.brightTeal, width: 1.6),
    ),
  );
}

ButtonStyle healthFilledButtonStyle([Color color = HealthColors.brightTeal]) =>
    FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );

void showHealthSnack(BuildContext context, String message,
    {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? const Color(0xFFB3261E) : HealthColors.deepTeal,
    ),
  );
}

Future<bool> confirmHealthDelete(BuildContext context, String what) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Confirmer la suppression'),
      content: Text('Voulez-vous supprimer $what ?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  return result == true;
}

// ── Formatage ────────────────────────────────────────────────────────────────

double? asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return null;
  return double.tryParse(value.toString());
}

/// Lit un nombre saisi par l'utilisateur, avec virgule ou point décimal.
double? parseUserNumber(String text) {
  final cleaned = text.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

String formatNumber(num? value, {int decimals = 1}) {
  if (value == null) return '—';
  final pattern = decimals == 0 ? '#,##0' : '#,##0.${'#' * decimals}';
  return NumberFormat(pattern, 'fr_FR').format(value);
}

String formatLiters(num ml) =>
    '${NumberFormat('0.##', 'fr_FR').format(ml / 1000)} L';

String capitalize(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

String formatLongDate(DateTime date) =>
    capitalize(DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(date));

String formatShortDate(DateTime date) => DateFormat('dd/MM', 'fr_FR').format(date);

DateTime? parseApiDateTime(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString());

String apiDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

String apiTime(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';

TimeOfDay? parseApiTime(dynamic value) {
  if (value == null) return null;
  final parts = value.toString().split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return TimeOfDay(hour: hour, minute: minute);
}

String shortTime(dynamic value) {
  final time = parseApiTime(value);
  if (time == null) return '';
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Moyenne journalière de l'hydratation, calculée sur les jours renseignés.
double averageWaterPerDay(List<Map<String, dynamic>> days) {
  final filled = days.map((d) => asDouble(d['totalMl']) ?? 0).where((v) => v > 0).toList();
  return filled.isEmpty ? 0 : filled.reduce((a, b) => a + b) / filled.length;
}

List<Map<String, dynamic>> asMapList(dynamic data) =>
    data is List ? data.whereType<Map<String, dynamic>>().toList() : [];

Map<String, dynamic> asMap(dynamic data) =>
    data is Map<String, dynamic> ? data : <String, dynamic>{};

const mealTypeLabels = {
  'BREAKFAST': 'Petit-déjeuner',
  'LUNCH': 'Déjeuner',
  'DINNER': 'Dîner',
  'SNACK': 'Collation',
};

const mealTypeIcons = {
  'BREAKFAST': Icons.free_breakfast_outlined,
  'LUNCH': Icons.lunch_dining_outlined,
  'DINNER': Icons.dinner_dining_outlined,
  'SNACK': Icons.apple_outlined,
};

const mealTypeColors = {
  'BREAKFAST': Color(0xFFDB8A3B),
  'LUNCH': Color(0xFF0C7778),
  'DINNER': Color(0xFF4F6BD8),
  'SNACK': Color(0xFF398A67),
};

// ── IMC ──────────────────────────────────────────────────────────────────────

double? computeBmi(double? weightKg, double? heightCm) {
  if (weightKg == null || heightCm == null || heightCm <= 0) return null;
  return weightKg / math.pow(heightCm / 100, 2);
}

String bmiLabel(double bmi) {
  if (bmi < 18.5) return 'Insuffisance pondérale';
  if (bmi < 25) return 'Corpulence normale';
  if (bmi < 30) return 'Surpoids';
  return 'Obésité';
}

Color bmiColor(double bmi) {
  if (bmi < 18.5) return HealthColors.pressure;
  if (bmi < 25) return HealthColors.success;
  if (bmi < 30) return HealthColors.temperature;
  return HealthColors.heart;
}

// ── Graphiques ───────────────────────────────────────────────────────────────

class ChartSeries {
  const ChartSeries(this.values, this.color, {this.label});
  final List<double> values;
  final Color color;
  final String? label;
}

/// Courbe(s) d'évolution avec repères min / max et dates de début / fin.
class HealthLineChart extends StatelessWidget {
  const HealthLineChart({
    super.key,
    required this.series,
    this.height = 140,
    this.startLabel,
    this.endLabel,
    this.decimals = 1,
  });

  final List<ChartSeries> series;
  final double height;
  final String? startLabel;
  final String? endLabel;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final all = series.expand((s) => s.values).toList();
    if (all.isEmpty) return SizedBox(height: height);
    final minV = all.reduce(math.min);
    final maxV = all.reduce(math.max);
    const labelStyle = TextStyle(fontSize: 10, color: HealthColors.muted);
    return Column(
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatNumber(maxV, decimals: decimals), style: labelStyle),
                  Text(formatNumber(minV, decimals: decimals), style: labelStyle),
                ],
              ),
              const SizedBox(width: 6),
              Expanded(
                child: CustomPaint(
                  painter: _LineChartPainter(series, minV, maxV),
                ),
              ),
            ],
          ),
        ),
        if (startLabel != null || endLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 30),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(startLabel ?? '', style: labelStyle),
                Text(endLabel ?? '', style: labelStyle),
              ],
            ),
          ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter(this.series, this.minV, this.maxV);

  final List<ChartSeries> series;
  final double minV;
  final double maxV;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE3ECEB)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = 6 + (size.height - 12) * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;
    for (final s in series) {
      final values = s.values;
      if (values.isEmpty) continue;
      final pts = <Offset>[];
      for (var i = 0; i < values.length; i++) {
        final x = values.length == 1
            ? size.width / 2
            : 6 + (size.width - 12) * i / (values.length - 1);
        final y = 6 + (size.height - 12) * (1 - (values[i] - minV) / range);
        pts.add(Offset(x, y));
      }
      if (series.length == 1 && pts.length > 1) {
        final fill = Path()..moveTo(pts.first.dx, size.height);
        for (final p in pts) {
          fill.lineTo(p.dx, p.dy);
        }
        fill
          ..lineTo(pts.last.dx, size.height)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                s.color.withValues(alpha: 0.25),
                s.color.withValues(alpha: 0.02),
              ],
            ).createShader(Offset.zero & size),
        );
      }
      if (pts.length > 1) {
        final line = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (var i = 1; i < pts.length; i++) {
          final midX = (pts[i - 1].dx + pts[i].dx) / 2;
          line.cubicTo(midX, pts[i - 1].dy, midX, pts[i].dy, pts[i].dx, pts[i].dy);
        }
        canvas.drawPath(
          line,
          Paint()
            ..color = s.color
            ..strokeWidth = 2.5
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
        );
      }
      for (final p in pts) {
        canvas.drawCircle(p, 4, Paint()..color = Colors.white);
        canvas.drawCircle(p, 3, Paint()..color = s.color);
      }
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.series != series || old.minV != minV || old.maxV != maxV;
}

/// Histogramme simple (une barre par jour) avec ligne d'objectif optionnelle.
class HealthBarChart extends StatelessWidget {
  const HealthBarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    this.goal,
    this.height = 150,
  });

  final List<double> values;
  final List<String> labels;
  final Color color;
  final double? goal;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxV = [
      ...values,
      if (goal != null) goal!,
      1.0,
    ].reduce(math.max);
    final showEvery = values.length <= 10 ? 1 : (values.length / 7).ceil();
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, constraints) {
        final chartHeight = constraints.maxHeight - 18;
        return Stack(
          children: [
            if (goal != null)
              Positioned(
                left: 0,
                right: 0,
                top: chartHeight * (1 - goal! / maxV),
                child: Container(
                  height: 1.5,
                  color: HealthColors.success.withValues(alpha: .6),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Tooltip(
                          message: '${labels[i]} : ${formatNumber(values[i], decimals: 0)}',
                          child: Container(
                            height: math.max(2, chartHeight * values[i] / maxV),
                            margin: EdgeInsets.symmetric(
                                horizontal: values.length > 20 ? 1 : 3),
                            decoration: BoxDecoration(
                              color: goal != null && values[i] >= goal!
                                  ? HealthColors.success
                                  : color,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5)),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 18,
                          child: i % showEvery == 0
                              ? FittedBox(
                                  child: Text(labels[i],
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: HealthColors.muted)),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// Anneau de progression (hydratation).
class HealthRing extends StatelessWidget {
  const HealthRing({
    super.key,
    required this.progress,
    required this.color,
    required this.child,
    this.size = 180,
  });

  final double progress;
  final Color color;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(progress.clamp(0.0, 1.0), color),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 10;
    final base = Paint()
      ..color = color.withValues(alpha: .15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, base);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      base..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

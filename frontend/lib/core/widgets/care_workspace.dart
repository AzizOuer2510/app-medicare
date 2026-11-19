import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

abstract final class CareColors {
  static const canvas = Color(0xFFF4F7F8);
  static const ink = Color(0xFF183A3A);
  static const primary = Color(0xFF237A6B);
  static const mint = Color(0xFFE8F4EE);
  static const muted = Color(0xFF738584);
  static const line = Color(0xFFE3ECE8);
  static const violet = Color(0xFF7865B3);
  static const amber = Color(0xFFC18A3A);
}

ThemeData careTheme(BuildContext context) => Theme.of(context).copyWith(
  scaffoldBackgroundColor: CareColors.canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: CareColors.primary,
    primary: CareColors.primary,
    surface: Colors.white,
  ),
  textTheme: Theme.of(
    context,
  ).textTheme.apply(bodyColor: CareColors.ink, displayColor: CareColors.ink),
  appBarTheme: const AppBarTheme(
    backgroundColor: CareColors.canvas,
    foregroundColor: CareColors.ink,
    elevation: 0,
    scrolledUnderElevation: 0,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: CareColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: CareColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: CareColors.primary, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  chipTheme: ChipThemeData(
    side: const BorderSide(color: CareColors.line),
    backgroundColor: Colors.white,
    selectedColor: CareColors.mint,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
  dialogTheme: DialogThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    backgroundColor: Colors.white,
  ),
);

class CareWorkspace extends StatelessWidget {
  const CareWorkspace({
    super.key,
    required this.index,
    required this.onNavigate,
    required this.child,
    required this.onRefresh,
  });
  final int index;
  final ValueChanged<int> onNavigate;
  final Widget child;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Theme(
    data: careTheme(context),
    child: Builder(
      builder: (context) {
        final wide = MediaQuery.sizeOf(context).width >= 760;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 76,
            leading: Navigator.canPop(context)
                ? IconButton(
                    tooltip: 'Retour',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  )
                : null,
            titleSpacing: Navigator.canPop(context) ? 0 : 20,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: CareColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.health_and_safety_outlined,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'MediCare',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    fontSize: 23,
                  ),
                ),
              ],
            ),
            actions: [
              if (wide) ...[
                TextButton.icon(
                  onPressed: () => onNavigate(0),
                  icon: Icon(
                    index == 0
                        ? Icons.notifications_rounded
                        : Icons.notifications_outlined,
                  ),
                  label: const Text('Notifications & rappels'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => onNavigate(1),
                  icon: Icon(
                    index == 1 ? Icons.folder_rounded : Icons.folder_outlined,
                  ),
                  label: const Text('Documents médicaux'),
                ),
                const SizedBox(width: 16),
              ],
              IconButton(
                onPressed: onRefresh,
                tooltip: 'Actualiser',
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: SafeArea(top: false, child: child),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: onNavigate,
                  backgroundColor: Colors.white,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.notifications_outlined),
                      selectedIcon: Icon(Icons.notifications_rounded),
                      label: 'Notifications',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.folder_outlined),
                      selectedIcon: Icon(Icons.folder_rounded),
                      label: 'Documents',
                    ),
                  ],
                ),
        );
      },
    ),
  );
}

class CareHero extends StatelessWidget {
  const CareHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    this.action,
  });
  final String eyebrow, title, description;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        colors: [Color(0xFF183E3C), Color(0xFF286B5D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -36,
          top: -85,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 40,
              ),
            ),
          ),
        ),
        Positioned(
          right: 52,
          bottom: -85,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.035),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 650 ? 20 : 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: const Color(0xFFB8DBCB)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      eyebrow.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFB8DBCB),
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: MediaQuery.sizeOf(context).width < 650 ? 10 : 16,
              ),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: MediaQuery.sizeOf(context).width < 650 ? 24 : 32,
                  height: 1.12,
                  letterSpacing: -1.1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (MediaQuery.sizeOf(context).width >= 650) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFFCCE0D8),
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
              if (action != null) ...[
                SizedBox(
                  height: MediaQuery.sizeOf(context).width < 650 ? 14 : 22,
                ),
                action!,
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class CareStat extends StatelessWidget {
  const CareStat({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    this.color = CareColors.primary,
  });
  final String value, label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => CarePanel(
    padding: const EdgeInsets.all(18),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: CareColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class CareStats extends StatelessWidget {
  const CareStats({super.key, required this.children, this.compactIndices});
  final List<Widget> children;
  final List<int>? compactIndices;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final visible = constraints.maxWidth < 650 && compactIndices != null
          ? compactIndices!.map((index) => children[index]).toList()
          : children;
      final columns = constraints.maxWidth < 650 ? 2 : visible.length;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: visible
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
  );
}

class CarePanel extends StatelessWidget {
  const CarePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: CareColors.line),
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class CareBadge extends StatelessWidget {
  const CareBadge(
    this.text, {
    super.key,
    this.color = CareColors.primary,
    this.icon,
  });
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

class CareEmpty extends StatelessWidget {
  const CareEmpty({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.action,
  });
  final String title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => CarePanel(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Column(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: CareColors.mint,
              child: Icon(icon, color: CareColors.primary, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CareColors.muted, height: 1.6),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    ),
  );
}

class CareError extends StatelessWidget {
  const CareError({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => CarePanel(
    child: Row(
      children: [
        const Icon(Icons.wifi_off_rounded, color: CareColors.amber),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    ),
  );
}

String careDate(dynamic value, {bool time = true}) => DateFormat(
  time ? 'dd/MM/yyyy · HH:mm' : 'dd/MM/yyyy',
).format(DateTime.parse(value as String).toLocal());

String careSize(num size) => size >= 1024 * 1024
    ? '${(size / (1024 * 1024)).toStringAsFixed(1)} Mo'
    : '${(size / 1024).toStringAsFixed(1)} Ko';

String careDay(dynamic value) {
  final date = DateTime.parse(value as String).toLocal();
  final now = DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Aujourd’hui';
  if (day == today.subtract(const Duration(days: 1))) return 'Hier';
  if (day == today.add(const Duration(days: 1))) return 'Demain';
  return DateFormat('dd/MM/yyyy').format(date);
}

String careRelative(dynamic value) {
  final difference = DateTime.parse(value as String).difference(DateTime.now());
  if (difference.inSeconds < 0) return 'Échéance atteinte';
  if (difference.inMinutes < 1) return 'Dans moins d’une minute';
  if (difference.inMinutes < 60) return 'Dans ${difference.inMinutes} min';
  if (difference.inHours < 24) return 'Dans ${difference.inHours} h';
  return 'Dans ${difference.inDays} j';
}

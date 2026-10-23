import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:auramind/services/sensor_service.dart';
import 'package:auramind/models/auramind_models.dart';
import 'package:auramind/auramind_theme.dart';
import 'package:auramind/auramind_widgets.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<SensorService>().importBackendHistory(hours: 24 * 30);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorService>(builder: (context, s, _) {
      final report = s.buildLocalReport(days: 7);
      final checkIns = s.moodCheckIns.where((c) =>
          c.timestamp.isAfter(DateTime.now().subtract(const Duration(days: 7)))).toList();
      final closeMatches = checkIns.where((c) => c.closeMatch).length;
      final accuracy = checkIns.isEmpty ? 0.0 : closeMatches / checkIns.length * 100;
      final completed = s.interventionRecords.where((r) => r.response == 'done').length;
      final notHelpful = s.interventionRecords.where((r) => r.response == 'not_helpful').length;
      final deferred = s.interventionRecords.where((r) => r.response == 'not_now' || r.response == 'remind').length;
      final unread = s.unreadAlerts;
      final helpfulAlerts = s.alerts.where((a) => a.feedback == 'helpful').length;
      final notHelpfulAlerts = s.alerts.where((a) => a.feedback == 'not_helpful').length;
      final trigger = _mostCommonTrigger(s.interventionRecords);

      return Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(children: [
                  const Text('Report',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600,
                          color: C.t1, letterSpacing: -0.5)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.read<SensorService>().importBackendHistory(hours: 24 * 30, force: true),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: C.card, shape: BoxShape.circle, boxShadow: C.shadowSm),
                      child: const Icon(Icons.sync_rounded, color: C.t2, size: 20),
                    ),
                  ),
                ]),
              ),
            ),
            if (s.backendHistoryImporting ||
                (s.backendImportStatus ?? '').startsWith('Imported'))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: C.tealSoft, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      const Icon(Icons.sync_rounded, color: C.teal, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        s.backendHistoryImporting ? 'Checking previous backend readings...' : (s.backendImportStatus ?? ''),
                        style: const TextStyle(fontSize: 11, color: C.t2, fontWeight: FontWeight.w600),
                      )),
                    ]),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Weekly wellbeing summary',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.t1)),
                    const SizedBox(height: 4),
                    const Text('Based on tracked temperature, humidity, optional sound, check-ins, alerts, and reset feedback.',
                        style: TextStyle(fontSize: 12, color: C.t3, height: 1.45)),
                    const SizedBox(height: 18),
                    Row(children: [
                      _metric('Avg mood', '${report.avgScore.toStringAsFixed(0)}%', C.accent),
                      const SizedBox(width: 10),
                      _metric('Readings', '${report.readingCount}', C.teal),
                      const SizedBox(width: 10),
                      _metric('Check-ins', '${checkIns.length}', C.warning),
                    ]),
                  ]),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: SectionLabel('Prediction validation'),
            )),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AppCard(
                  child: Row(children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(color: C.tealSoft, borderRadius: BorderRadius.circular(13)),
                      child: const Icon(Icons.fact_check_rounded, color: C.teal, size: 21),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${accuracy.toStringAsFixed(0)}% close match',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.t1)),
                      const SizedBox(height: 3),
                      Text(checkIns.isEmpty
                          ? 'No check-ins yet. Ask the user to check in to validate predictions.'
                          : '$closeMatches of ${checkIns.length} mood check-ins were close to the prediction.',
                          style: const TextStyle(fontSize: 12, color: C.t3, height: 1.4)),
                    ])),
                  ]),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: SectionLabel('Reset effectiveness'),
            )),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AppCard(
                  child: Column(children: [
                    Row(children: [
                      _metric('Done', '$completed', C.success),
                      const SizedBox(width: 10),
                      _metric('Deferred', '$deferred', C.warning),
                      const SizedBox(width: 10),
                      _metric('Not helpful', '$notHelpful', C.danger),
                    ]),
                    const SizedBox(height: 14),
                    _infoRow(Icons.auto_awesome_rounded, 'Most common trigger', trigger ?? 'Not enough reset feedback yet'),
                    const SizedBox(height: 8),
                    _infoRow(Icons.psychology_alt_rounded, 'How this improves personalization',
                        'Done increases confidence in similar resets; Not helpful suppresses repeated suggestions for longer.'),
                  ]),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: SectionLabel('Alerts'),
            )),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AppCard(
                  child: Column(children: [
                    Row(children: [
                      _metric('Total', '${s.alerts.length}', C.accent),
                      const SizedBox(width: 10),
                      _metric('Unread', '$unread', C.danger),
                      const SizedBox(width: 10),
                      _metric('Helpful', '$helpfulAlerts', C.success),
                    ]),
                    if (notHelpfulAlerts > 0) ...[
                      const SizedBox(height: 14),
                      _infoRow(Icons.tune_rounded, 'Alert tuning',
                          '$notHelpfulAlerts alert(s) were marked not helpful. AuraMind can use this to adjust future sensitivity.'),
                    ],
                  ]),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: SectionLabel('Scope and data source'),
            )),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 40),
                child: AppCard(
                  child: Text(
                    'This report does not use light or CO₂ because those are not tracked by the current app. Location is broad user-declared context, not exact address tracking. AuraMind estimates wellbeing patterns and does not diagnose mental health conditions.',
                    style: TextStyle(fontSize: 12, color: C.t3, height: 1.45),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }

  static Widget _metric(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 10, color: C.t3)),
      ]),
    ),
  );

  static Widget _infoRow(IconData icon, String title, String body) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 17, color: C.accent),
      const SizedBox(width: 9),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.t1)),
        const SizedBox(height: 2),
        Text(body, style: const TextStyle(fontSize: 11, color: C.t3, height: 1.35)),
      ])),
    ],
  );

  static String? _mostCommonTrigger(List<InterventionRecord> records) {
    final counts = <String, int>{};
    for (final r in records) {
      final trigger = r.trigger;
      if (trigger == null || trigger.isEmpty) continue;
      counts[trigger] = (counts[trigger] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final entry = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    switch (entry.key) {
      case 'temp': return 'Temperature comfort';
      case 'humidity': return 'Humidity comfort';
      case 'sound': return 'Sound level';
      case 'sedentary': return 'Long time in one context';
      default: return entry.key;
    }
  }
}

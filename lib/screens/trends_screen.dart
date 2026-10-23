import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:auramind/services/sensor_service.dart';
import 'package:auramind/services/agent_client.dart';
import 'package:auramind/models/auramind_models.dart';
import 'package:auramind/auramind_theme.dart';
import 'package:auramind/auramind_widgets.dart';

// Navigation guide:
//  [1] Trend period selection and loading state
//  [2] Chart rendering, summary, and detail expansion

enum TrendPeriod { day, week, month }

/// Trends view displays historical mood data grouped by day, week, or month.
/// Includes chart style selection, summary stats, and a drill-down breakdown.
class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});
  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  TrendPeriod period = TrendPeriod.day;
  int? expandedIndex;
  bool loading = true;
  List<_Bucket> buckets = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { loading = true; expandedIndex = null; });
    final service = context.read<SensorService>();

    try {
      if (period == TrendPeriod.day) {
        await service.importBackendHistory(hours: 24, force: true);
        final pts = service.buildLocalHistoryPoints(hours: 24);
        buckets = _bucketByHour(pts);
      } else {
        final days = period == TrendPeriod.week ? 7 : 30;
        await service.importBackendHistory(hours: days * 24, force: true);
        final pts = service.buildLocalHistoryPoints(hours: days * 24);
        buckets = _bucketByDay(pts, days);
      }
    } catch (_) {
      if (period == TrendPeriod.day) {
        buckets = _bucketByHour(service.buildLocalHistoryPoints(hours: 24));
      } else {
        final days = period == TrendPeriod.week ? 7 : 30;
        buckets = _bucketByDay(service.buildLocalHistoryPoints(hours: days * 24), days);
      }
    }
    if (mounted) setState(() => loading = false);
  }

  // Group readings into hourly buckets (for Day view).
  List<_Bucket> _bucketByHour(List<HistoryPoint> pts) {
    final map = <int, List<HistoryPoint>>{};
    for (final p in pts) {
      map.putIfAbsent(p.ts.toLocal().hour, () => []).add(p);
    }
    final out = <_Bucket>[];
    final sorted = map.keys.toList()..sort();
    for (final h in sorted) {
      out.add(_Bucket.fromPoints('${h.toString().padLeft(2, '0')}:00', map[h]!));
    }
    return out;
  }

  // Group readings into daily buckets (for Week / Month view).
  List<_Bucket> _bucketByDay(List<HistoryPoint> pts, int days) {
    final map = <String, List<HistoryPoint>>{};
    final fmtDays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    for (final p in pts) {
      final d = p.ts.toLocal();
      final key = '${d.year}-${d.month}-${d.day}';
      map.putIfAbsent(key, () => []).add(p);
    }
    final out = <_Bucket>[];
    final sorted = map.keys.toList()..sort();
    for (final k in sorted) {
      final sample = map[k]!.first.ts.toLocal();
      final label = days <= 7 ? fmtDays[sample.weekday - 1] : '${sample.day}';
      out.add(_Bucket.fromPoints(label, map[k]!));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final chartKind = context.watch<SensorService>().chartKind;

    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: C.accent,
          child: CustomScrollView(slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(children: [
                  if (Navigator.canPop(context)) ...[
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: C.card, shape: BoxShape.circle, boxShadow: C.shadowSm),
                        child: const Icon(Icons.arrow_back_rounded, color: C.t2, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  const Text('Trends', style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w600,
                      color: C.t1, letterSpacing: -0.5)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _load,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: C.card,
                          shape: BoxShape.circle, boxShadow: C.shadowSm),
                      child: const Icon(Icons.refresh_rounded, color: C.t2, size: 20),
                    ),
                  ),
                ]),
              ),
            ),

            // Period selector
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(children: TrendPeriod.values.map((p) {
                  const labels = {TrendPeriod.day: 'Day', TrendPeriod.week: 'Week', TrendPeriod.month: 'Month'};
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChipButton(label: labels[p]!, selected: period == p,
                        onTap: () { setState(() => period = p); _load(); }),
                  );
                }).toList()),
              ),
            ),

            if (context.watch<SensorService>().backendHistoryImporting ||
                (context.watch<SensorService>().backendImportStatus ?? '').startsWith('Imported'))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  child: _ImportStatusCard(service: context.watch<SensorService>()),
                ),
              ),

            if (loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator(color: C.accent)),
                ),
              )
            else if (buckets.isEmpty)
              SliverToBoxAdapter(child: _empty(period))
            else ...[
              // Summary
              SliverToBoxAdapter(child: _Summary(buckets: buckets)),

              // Chart
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: AppCard(
                    child: SizedBox(
                      height: 200,
                      child: _ChartView(
                        kind: chartKind, buckets: buckets,
                        expandedIndex: expandedIndex,
                        onTapIndex: (i) => setState(() =>
                            expandedIndex = expandedIndex == i ? null : i),
                      ),
                    ),
                  ),
                ),
              ),

              if (expandedIndex != null && expandedIndex! < buckets.length)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: _Detail(bucket: buckets[expandedIndex!]),
                  ),
                ),

              // History list
              const SliverToBoxAdapter(child: Padding(
                padding: EdgeInsets.fromLTRB(24, 28, 24, 12),
                child: SectionLabel('Breakdown'),
              )),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: buckets.asMap().entries.map((e) {
                      final i = e.key; final b = e.value;
                      final last = i == buckets.length - 1;
                      return InkWell(
                        onTap: () => setState(() =>
                            expandedIndex = expandedIndex == i ? null : i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(border: last ? null
                              : const Border(bottom: BorderSide(color: C.borderL, width: 0.5))),
                          child: Row(children: [
                            Icon(moodIcon(b.level), size: 20, color: C.mood(b.level)),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(b.label, style: const TextStyle(fontSize: 13,
                                  fontWeight: FontWeight.w600, color: C.t1)),
                              Text('${b.count} reading${b.count == 1 ? "" : "s"}',
                                  style: const TextStyle(fontSize: 11, color: C.t3)),
                            ])),
                            Text('${b.avg.toStringAsFixed(0)}%',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                                    color: C.mood(b.level))),
                          ]),
                        ),
                      );
                    }).toList()),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _empty(TrendPeriod p) {
    final span = p == TrendPeriod.day ? 'today'
        : p == TrendPeriod.week ? 'this week' : 'this month';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
      child: Column(children: [
        Container(
          width: 64, height: 64,
          decoration: const BoxDecoration(color: C.accentSoft, shape: BoxShape.circle),
          child: const Icon(Icons.insights_rounded, color: C.accent, size: 30),
        ),
        const SizedBox(height: 16),
        Text('Not enough data $span',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.t1)),
        const SizedBox(height: 6),
        const Text('Keep AuraMind running and your mood trend will build here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: C.t3, height: 1.4)),
      ]),
    );
  }
}


class _ImportStatusCard extends StatelessWidget {
  final SensorService service;
  const _ImportStatusCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final msg = service.backendHistoryImporting
        ? 'Checking previous backend readings...'
        : (service.backendImportStatus ?? '');
    if (msg.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: C.tealSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Icon(Icons.sync_rounded, color: C.teal, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg,
            style: const TextStyle(fontSize: 11, color: C.t2, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class _Bucket {
  final String label;
  final double avg;          // average mood score
  final MoodLevel level;
  final int count;
  final double temp, humidity, sound;
  _Bucket({required this.label, required this.avg, required this.level,
      required this.count, required this.temp, required this.humidity,
      required this.sound});

  factory _Bucket.fromPoints(String label, List<HistoryPoint> pts) {
    double s(double Function(HistoryPoint) f) =>
        pts.map(f).reduce((a, b) => a + b) / pts.length;
    final avg = s((p) => p.moodScore);
    return _Bucket(
      label: label, avg: avg, level: _level(avg), count: pts.length,
      temp: s((p) => p.temperature), humidity: s((p) => p.humidity),
      sound: s((p) => p.sound),
    );
  }

  static MoodLevel _level(double c) {
    if (c >= 80) return MoodLevel.excellent;
    if (c >= 65) return MoodLevel.good;
    if (c >= 50) return MoodLevel.neutral;
    if (c >= 35) return MoodLevel.low;
    return MoodLevel.veryLow;
  }
}

class _Summary extends StatelessWidget {
  final List<_Bucket> buckets;
  const _Summary({required this.buckets});
  @override
  Widget build(BuildContext context) {
    final avg = buckets.map((b) => b.avg).reduce((a, b) => a + b) / buckets.length;
    final best = buckets.map((b) => b.avg).reduce(max);
    final worst = buckets.map((b) => b.avg).reduce(min);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(children: [
        _c('Average', '${avg.toStringAsFixed(0)}%', C.accent),
        const SizedBox(width: 10),
        _c('Best', '${best.toStringAsFixed(0)}%', C.success),
        const SizedBox(width: 10),
        _c('Lowest', '${worst.toStringAsFixed(0)}%', C.warning),
      ]),
    );
  }
  Widget _c(String l, String v, Color color) => Expanded(child: AppCard(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Column(children: [
      Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
      const SizedBox(height: 2),
      Text(l, style: const TextStyle(fontSize: 11, color: C.t3)),
    ]),
  ));
}

class _ChartView extends StatelessWidget {
  final ChartKind kind;
  final List<_Bucket> buckets;
  final int? expandedIndex;
  final ValueChanged<int> onTapIndex;
  const _ChartView({required this.kind, required this.buckets,
      required this.expandedIndex, required this.onTapIndex});

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case ChartKind.line:
        return CustomPaint(
          painter: LinePainter(buckets.map((b) => b.avg / 100).toList()),
          size: Size.infinite,
        );
      case ChartKind.bar:
        return Row(crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(buckets.length, (i) {
          final b = buckets[i];
          final h = (b.avg / 100) * 168;
          final sel = i == expandedIndex;
          return Expanded(child: GestureDetector(
            onTap: () => onTapIndex(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(height: h, decoration: BoxDecoration(
                  color: sel ? C.mood(b.level) : C.mood(b.level).withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                  border: sel ? Border.all(color: C.t1, width: 1.2) : null,
                )),
                const SizedBox(height: 6),
                if (buckets.length <= 12)
                  Text(b.label, style: const TextStyle(fontSize: 9, color: C.t3),
                      maxLines: 1, overflow: TextOverflow.clip),
              ]),
            ),
          ));
        }));
      case ChartKind.wheel:
        final counts = <MoodLevel, int>{};
        for (final b in buckets) { counts[b.level] = (counts[b.level] ?? 0) + 1; }
        return Row(children: [
          Expanded(child: AspectRatio(aspectRatio: 1,
            child: CustomPaint(painter: _WheelPainter(counts, buckets.length)))),
          const SizedBox(width: 16),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: MoodLevel.values.reversed.map((l) {
            final c = counts[l] ?? 0;
            final pct = buckets.isEmpty ? 0 : (c / buckets.length * 100).round();
            return Padding(padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(moodIcon(l), size: 16, color: C.mood(l)),
                const SizedBox(width: 8),
                Text(moodLabel(l), style: const TextStyle(fontSize: 12, color: C.t2)),
                const Spacer(),
                Text('$pct%', style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w600, color: C.t1)),
              ]),
            );
          }).toList())),
        ]);
    }
  }
}

class _WheelPainter extends CustomPainter {
  final Map<MoodLevel, int> counts;
  final int total;
  _WheelPainter(this.counts, this.total);
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final center = Offset(size.width / 2, size.height / 2);
    double start = -pi / 2;
    for (final l in MoodLevel.values) {
      final c = counts[l] ?? 0;
      if (c == 0) continue;
      final sweep = (c / total) * 2 * pi;
      canvas.drawArc(Rect.fromCircle(center: center, radius: r),
          start, sweep, true, Paint()..color = C.mood(l));
      start += sweep;
    }
    canvas.drawCircle(center, r * 0.56, Paint()..color = C.card);
  }
  @override
  bool shouldRepaint(_WheelPainter old) => true;
}

class _Detail extends StatelessWidget {
  final _Bucket bucket;
  const _Detail({required this.bucket});
  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: C.mood(bucket.level).withValues(alpha: 0.08),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(moodIcon(bucket.level), size: 28, color: C.mood(bucket.level)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(bucket.label, style: const TextStyle(fontSize: 12, color: C.t3)),
            Text('${moodLabel(bucket.level)} · ${bucket.avg.toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: C.t1)),
          ]),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _metric(Icons.thermostat_rounded, '${bucket.temp.toStringAsFixed(1)}°'),
          _metric(Icons.water_drop_rounded, '${bucket.humidity.toStringAsFixed(0)}%'),
          _metric(Icons.graphic_eq_rounded, '${bucket.sound.toStringAsFixed(0)} dB'),
        ]),
      ]),
    );
  }
  Widget _metric(IconData i, String v) => Expanded(child: Row(children: [
    Icon(i, size: 15, color: C.accent),
    const SizedBox(width: 6),
    Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.t1)),
  ]));
}
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:auramind/services/sensor_service.dart';
import 'package:auramind/services/mood_engine.dart';
import 'package:auramind/services/ai_coping_service.dart';
import 'package:auramind/models/auramind_models.dart';
import 'package:auramind/auramind_theme.dart';
import 'package:auramind/auramind_widgets.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final _aiCoping = AiCopingService();
  Future<List<ActionStep>>? _copingFuture;
  String? _lastConditionKey;

  void _refreshIfNeeded(SensorService s) {
    final conditions = _aiCoping.buildConditionsPublic(
      s.current, s.comfortProfile, s.currentSoundDb, s.currentLightLux,
    );
    final key = conditions.join('|');
    if (key == _lastConditionKey) return;
    _lastConditionKey = key;
    _copingFuture = conditions.isEmpty
        ? Future.value([])
        : _aiCoping.getCopingSteps(
            sensor: s.current,
            profile: s.comfortProfile,
            soundDb: s.currentSoundDb,
            lightLux: s.currentLightLux,
          );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SensorService>();
    final plan = s.actionPlan;
    final mood = MoodEngine.predict(s.current, profile: s.comfortProfile);
    final envSteps = plan?.steps
            .where((st) => !st.isCoping && !st.completed && !st.skipped)
            .toList() ??
        [];

    _refreshIfNeeded(s);

    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: CustomScrollView(slivers: [

          // ── Header ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Plan', style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w600,
                    color: C.t1, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text(envSteps.isNotEmpty
                    ? 'Steps to improve your environment.'
                    : 'Your environment looks good right now.',
                    style: const TextStyle(fontSize: 13, color: C.t3, height: 1.4)),
              ]),
            ),
          ),

          // ── Fix the space ────────────────────────────────────────
          if (envSteps.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: _SectionHeader(
                  icon: Icons.home_repair_service_rounded,
                  label: 'Fix the space',
                  sub: 'Change your environment',
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _EnvStepList(steps: envSteps),
              ),
            ),
          ],

          // ── All-clear state ──────────────────────────────────────
          if (envSteps.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                child: Column(children: [
                  Container(
                    width: 80, height: 80,
                    decoration: const BoxDecoration(
                        color: C.successSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded,
                        color: C.success, size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text('Score: ${mood.confidence.toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: C.mood(mood.level))),
                  const SizedBox(height: 6),
                  const Text('No actions needed right now',
                      style: TextStyle(fontSize: 14, color: C.t2)),
                  const SizedBox(height: 4),
                  const Text('We\'ll suggest steps if your environment changes.',
                      style: TextStyle(fontSize: 12, color: C.t3)),
                ]),
              ),
            ),

          // ── Can't change the space? (AI coping) ─────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
              child: _SectionHeader(
                icon: Icons.self_improvement_rounded,
                label: "Can't change the space?",
                sub: 'AI-suggested ways to cope right now',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: FutureBuilder<List<ActionStep>>(
                future: _copingFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const _CopingShimmer();
                  }
                  final steps = snap.data ?? [];
                  if (steps.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                        'No environmental issues detected right now.',
                        style: const TextStyle(fontSize: 12, color: C.t3),
                      ),
                    );
                  }
                  return _CopingStepList(steps: steps);
                },
              ),
            ),
          ),

          // ── Today's progress ─────────────────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: TodaysProgressCard(),
            ),
          ),

          // ── Did you know ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: _DidYouKnowCard(mood: mood, s: s),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ]),
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.icon, required this.label, required this.sub});
  final IconData icon;
  final String label;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
            color: C.accentSoft,
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: C.accent),
      ),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600, color: C.t1)),
        Text(sub, style: const TextStyle(fontSize: 11, color: C.t3)),
      ]),
    ]);
  }
}

// ── Env steps (numbered, Do this → startResetStep) ─────────────────────────
class _EnvStepList extends StatelessWidget {
  const _EnvStepList({required this.steps});
  final List<ActionStep> steps;

  @override
  Widget build(BuildContext context) {
    final sensor = context.watch<SensorService>();
    return Column(
      children: steps.asMap().entries.map((e) {
        final i = e.key;
        final step = e.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 24, height: 24,
                decoration: const BoxDecoration(
                    color: C.accentSoft, shape: BoxShape.circle),
                child: Center(
                  child: Text('${i + 1}', style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: C.accent)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(step.title, style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: C.t1)),
                  const SizedBox(height: 3),
                  Text(step.description, style: const TextStyle(
                      fontSize: 12, color: C.t2, height: 1.4)),
                ]),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => sensor.startResetStep(step.id),
                child: const Text('Do this'),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

// ── AI coping steps (Do this → startCopingStep) ────────────────────────────
class _CopingStepList extends StatelessWidget {
  const _CopingStepList({required this.steps});
  final List<ActionStep> steps;

  @override
  Widget build(BuildContext context) {
    final sensor = context.watch<SensorService>();
    return Column(
      children: steps.map((step) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            color: C.accentSoft.withValues(alpha: 0.4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.self_improvement_rounded,
                  size: 18, color: C.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(step.title, style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: C.t1)),
                  const SizedBox(height: 3),
                  Text(step.description, style: const TextStyle(
                      fontSize: 12, color: C.t2, height: 1.4)),
                  const SizedBox(height: 2),
                  Text('~${step.estimatedMinutes} min',
                      style: const TextStyle(fontSize: 11, color: C.t3)),
                ]),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => sensor.startCopingStep(step),
                style: FilledButton.styleFrom(
                  backgroundColor: C.accent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Do this',
                    style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

// ── Loading shimmer ────────────────────────────────────────────────────────
class _CopingShimmer extends StatelessWidget {
  const _CopingShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (_) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: C.accentSoft.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Text('Generating suggestions…',
                style: TextStyle(fontSize: 12, color: C.t3)),
          ),
        ),
      )),
    );
  }
}

// ── Did you know ───────────────────────────────────────────────────────────
class _DidYouKnowCard extends StatelessWidget {
  final MoodReading mood;
  final SensorService s;
  const _DidYouKnowCard({required this.mood, required this.s});

  @override
  Widget build(BuildContext context) {
    final tip = _pickTip(s.current, s.comfortProfile);
    return AppCard(
      color: C.accentSoft,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.auto_awesome_rounded, size: 18, color: C.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Did you know?', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: C.accent, letterSpacing: 0.05)),
            const SizedBox(height: 4),
            Text(tip, style: const TextStyle(
                fontSize: 12, color: C.t2, height: 1.5)),
          ]),
        ),
      ]),
    );
  }

  String _pickTip(SensorData d, ComfortProfile p) {
    final minute = DateTime.now().minute;
    if (d.temperature > p.maxTemperature) {
      return 'Temperatures above ${p.maxTemperature.toStringAsFixed(0)}°C can '
          'increase cortisol and reduce focus. Even a 2°C drop helps.';
    }
    if (d.humidity > p.maxHumidity) {
      return 'High humidity makes sweat harder to evaporate — '
          'that is why humid days feel more draining than dry ones.';
    }
    if (d.temperature < p.minTemperature) {
      return 'Cool temperatures below ${p.minTemperature.toStringAsFixed(0)}°C '
          'can cause muscle tension. Ideal study temp is 22–24°C.';
    }
    final neutral = [
      'Ambient noise at 50–70 dB can boost creative thinking, while silence suits analytical work.',
      'NASA research found 22°C produces the fewest cognitive errors.',
      'Humidity between 40–60% is ideal for both comfort and respiratory health.',
      'Your body is naturally more alert between 10 AM and 2 PM — environment matters more outside those hours.',
      'Breaks every 45–60 minutes restore attention and reduce noise exposure effects.',
    ];
    return neutral[minute % neutral.length];
  }
}

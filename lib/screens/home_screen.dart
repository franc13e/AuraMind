import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:auramind/services/auth_service.dart';
import 'package:auramind/services/sensor_service.dart';
import 'package:auramind/services/mood_engine.dart';
import 'package:auramind/models/auramind_models.dart';
import 'package:auramind/auramind_theme.dart';
import 'package:auramind/auramind_widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorService>(builder: (context, s, _) {
      final mood = MoodEngine.predict(s.current, profile: s.comfortProfile);
      final now  = DateTime.now();
      final hour = now.hour;
      final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
      final userName = context.read<AuthService>().currentUser?.name.split(' ').first ?? '';
      final greetingText = userName.isNotEmpty ? '$greeting, $userName' : greeting;
      final days   = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final date   = '${days[now.weekday-1]} · ${now.day} ${months[now.month-1]}';

      return Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
          child: CustomScrollView(slivers: [

            // ── Header ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(date,
                        style: const TextStyle(fontSize: 12, color: C.t3,
                            letterSpacing: 0.4, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Text(greetingText,
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w600,
                            color: C.t1, height: 1.1, letterSpacing: -0.5)),
                  ])),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/settings'),
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: C.card,
                        shape: BoxShape.circle,
                        boxShadow: C.shadowSm,
                      ),
                      child: const Icon(Icons.tune_rounded, color: C.t2, size: 20),
                    ),
                  ),
                ]),
              ),
            ),

            // ── Location pill ────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: C.accentSoft,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.place_rounded, size: 14, color: C.accent),
                      const SizedBox(width: 5),
                      Text(s.currentPlace,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                              color: C.accent)),
                    ]),
                  ),
                ]),
              ),
            ),

            // ── Mood Orb ────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: _MoodOrb(mood: mood),
              ),
            ),



            // ── Insights ─────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: _InsightsCard(sensor: s),
              ),
            ),

            // ── Agent alert ─────────────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 16, 0, 0),
                child: AgentBanner(),
              ),
            ),



            // ── Today's progress ────────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: TodaysProgressCard(),
              ),
            ),

            // ── Action Plan ──────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: s.actionPlan != null
                    ? const ActionPlanCard()
                    : const SizedBox.shrink(),
              ),
            ),


            // ── Environment ─────────────────────────────────
            const SliverToBoxAdapter(child: Padding(
              padding: EdgeInsets.fromLTRB(24, 28, 24, 14),
              child: SectionLabel('Environment'),
            )),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: LayoutBuilder(builder: (context, constraints) {
                  final tileWidth = (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(width: tileWidth, child: _SensorTile(
                          icon: Icons.thermostat_rounded,
                          label: 'Temp',
                          value: '${s.current.temperature.toStringAsFixed(1)}°',
                          sub: _tempStatus(s.current.temperature, s.comfortProfile),
                          good: _tempStatus(s.current.temperature, s.comfortProfile) == 'Ideal')),
                      SizedBox(width: tileWidth, child: _SensorTile(
                          icon: Icons.water_drop_rounded,
                          label: 'Humidity',
                          value: '${s.current.humidity.toStringAsFixed(0)}%',
                          sub: _humStatus(s.current.humidity, s.comfortProfile),
                          good: _humStatus(s.current.humidity, s.comfortProfile) == 'Ideal')),
                      SizedBox(width: tileWidth, child: _SensorTile(
                          icon: Icons.light_mode_rounded,
                          label: 'Light',
                          value: s.currentLightLux < 0
                              ? '—'
                              : s.currentLightLux.toStringAsFixed(0),
                          sub: s.currentLightLux < 0
                              ? 'off'
                              : _lightStatus(s.currentLightLux, s.comfortProfile),
                          good: _lightStatus(s.currentLightLux, s.comfortProfile) == 'Ideal')),
                      SizedBox(width: tileWidth, child: _SensorTile(
                          icon: Icons.graphic_eq_rounded,
                          label: 'Sound',
                          value: s.currentSoundDb == 0
                              ? '—'
                              : s.currentSoundDb.toStringAsFixed(0),
                          sub: s.currentSoundDb == 0
                              ? 'off'
                              : _soundStatus(s.currentSoundDb, s.comfortProfile),
                          good: _soundStatus(s.currentSoundDb, s.comfortProfile) == 'Normal')),
                    ],
                  );
                }),
              ),
            ),



            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ]),
        ),
      );
    });
  }

  String _tempStatus(double v, ComfortProfile p) =>
      v < p.minTemperature ? 'Cool' : v > p.maxTemperature ? 'Warm' : 'Ideal';
  String _humStatus(double v, ComfortProfile p) =>
      v < p.minHumidity ? 'Dry' : v > p.maxHumidity ? 'Humid' : 'Ideal';
  String _lightStatus(double v, ComfortProfile p) {
    if (v < 0) return 'off';
    if (v < p.minLight) return 'Dim';
    if (v > p.maxLight) return 'Bright';
    return 'Ideal';
  }
  String _soundStatus(double v, ComfortProfile p) {
    if (v < 40) return 'Quiet';
    if (v > p.maxSound) return 'Loud';
    return 'Normal';
  }
}


// ── Compact mood check-in ──────────────────────────────────────
// Home should stay lightweight. Full check-in analytics live in Trends.
class _CompactMoodCheckIn extends StatelessWidget {
  const _CompactMoodCheckIn();

  @override
  Widget build(BuildContext context) {
    final sensor = context.watch<SensorService>();
    final latest = sensor.latestMoodCheckIn;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: C.shadowSm,
        border: Border.all(color: C.borderL, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: C.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.favorite_rounded, size: 15, color: C.accent),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Feeling now?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                  color: C.t1, letterSpacing: -0.2)),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/trends'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Details',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: SelfMood.values.map((mood) {
            return _MoodChip(
              mood: mood,
              selected: latest?.reportedMood == mood,
              onTap: () => context.read<SensorService>().submitMoodCheckIn(mood),
            );
          }).toList(),
        ),
        if (latest != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(
              latest.closeMatch
                  ? Icons.check_circle_rounded
                  : Icons.info_rounded,
              size: 14,
              color: latest.closeMatch ? C.success : C.warning,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Logged: ${latest.reportedMood.label} · Prediction ${latest.matchLabel.toLowerCase()}',
                style: const TextStyle(fontSize: 12, color: C.t3, height: 1.3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _MoodChip extends StatelessWidget {
  final SelfMood mood;
  final bool selected;
  final VoidCallback onTap;

  const _MoodChip({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 46,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? C.accentSoft : C.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? C.accent.withValues(alpha: 0.45) : C.borderL,
            width: selected ? 1.2 : 0.7,
          ),
        ),
        child: Text(
          _emoji(mood),
          style: const TextStyle(fontSize: 22),
        ),
      ),
    );
  }

  String _emoji(SelfMood mood) {
    switch (mood) {
      case SelfMood.calm:
        return '😌';
      case SelfMood.good:
        return '🙂';
      case SelfMood.neutral:
        return '😐';
      case SelfMood.uneasy:
        return '😟';
      case SelfMood.stressed:
        return '😣';
    }
  }
}

// ── Mood orb ────────────────────────────────────────────────────
class _MoodOrb extends StatefulWidget {
  final MoodReading mood;
  const _MoodOrb({required this.mood});
  @override
  State<_MoodOrb> createState() => _MoodOrbState();
}

class _MoodOrbState extends State<_MoodOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = C.mood(widget.mood.level);

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = (sin(_c.value * pi) + 1) / 2;
        final scale     = 0.95 + 0.09 * t;
        final outerOpac = 0.08 + 0.08 * t;
        final midOpac   = 0.18 + 0.08 * t;

        return Center(
          child: Column(children: [
            SizedBox(
              width: 210, height: 210,
              child: Stack(alignment: Alignment.center, children: [
                Transform.scale(scale: scale,
                  child: Container(
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: color.withValues(alpha: outerOpac)),
                  ),
                ),
                Transform.scale(scale: scale * 0.76,
                  child: Container(
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        color.withValues(alpha: midOpac + 0.05),
                        color.withValues(alpha: midOpac - 0.04),
                      ]),
                    ),
                  ),
                ),
                Container(
                  width: 112, height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.3, -0.4),
                      colors: [color.withValues(alpha: 0.96), color.withValues(alpha: 0.78)],
                    ),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.32),
                        blurRadius: 34, spreadRadius: 2)],
                  ),
                ),
                Positioned(
                  top: 66, left: 74,
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        Colors.white.withValues(alpha: 0.6),
                        Colors.white.withValues(alpha: 0.0),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Text(widget.mood.mood,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600,
                    color: C.t1, letterSpacing: -0.6)),
            const SizedBox(height: 4),
            Text(widget.mood.description,
                style: const TextStyle(fontSize: 13, color: C.t2, height: 1.4)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome_rounded, size: 13, color: color),
                const SizedBox(width: 6),
                Text('${widget.mood.confidence.toStringAsFixed(0)}% confidence',
                    style: TextStyle(fontSize: 11, color: color,
                        fontWeight: FontWeight.w600, letterSpacing: 0.2)),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// ── Sensor tile ────────────────────────────────────────────────
class _SensorTile extends StatelessWidget {
  final IconData icon;
  final String label, value, sub;
  final bool good;
  const _SensorTile({
    required this.icon, required this.label,
    required this.value, required this.sub, required this.good,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: C.shadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: C.accentSoft,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: C.accent),
        ),
        const SizedBox(height: 12),
        Text(value,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600,
                color: C.t1, letterSpacing: -0.5, height: 1)),
        const SizedBox(height: 5),
        Row(children: [
          Container(width: 5, height: 5,
            decoration: BoxDecoration(
                color: good ? C.success : C.accentMed, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Expanded(child: Text('$label · $sub',
              style: const TextStyle(fontSize: 10, color: C.t3),
              overflow: TextOverflow.ellipsis)),
        ]),
      ]),
    );
  }
}

// ── Hourly mood map — uses LOCAL data ──────────────────────────
/// Draws a 24-hour grid coloured by mood, built entirely from
/// the in-memory history so it always reflects real readings.

// ── Insights card ────────────────────────────────────────────
/// Shows contextual insights about the user's environment based
/// on current sensor data — useful, rotating, educational tips.
class _InsightsCard extends StatelessWidget {
  final SensorService sensor;
  const _InsightsCard({required this.sensor});

  @override
  Widget build(BuildContext context) {
    final d = sensor.current;
    final p = sensor.comfortProfile;
    final tip = _pickTip(d, p);
    final historyLen = sensor.history.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: C.shadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: C.accentSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 15, color: C.accent),
          ),
          const SizedBox(width: 10),
          const Text('Insight',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                  color: C.t1, letterSpacing: -0.2)),
          const Spacer(),
          if (historyLen > 0)
            Text('$historyLen readings today',
                style: const TextStyle(fontSize: 11, color: C.t4)),
        ]),
        const SizedBox(height: 14),
        Text(tip.title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: C.t1)),
        const SizedBox(height: 4),
        Text(tip.body,
            style: const TextStyle(fontSize: 12, color: C.t3, height: 1.5)),
      ]),
    );
  }

  ({String title, String body}) _pickTip(SensorData d, ComfortProfile p) {
    // Contextual — responds to current conditions
    if (d.temperature > p.maxTemperature + 2) {
      return (
        title: 'Your room is getting hot',
        body: 'At ${d.temperature.toStringAsFixed(1)}°C, cognitive performance '
            'can drop by up to 10%. Opening a window or turning on a fan '
            'could make a noticeable difference.',
      );
    }
    if (d.temperature < p.minTemperature) {
      return (
        title: 'It\'s a bit cold',
        body: 'At ${d.temperature.toStringAsFixed(1)}°C, your body spends '
            'energy staying warm instead of focusing. The sweet spot for '
            'studying is around 22–24°C.',
      );
    }
    if (d.humidity > p.maxHumidity) {
      return (
        title: 'Humidity is high',
        body: 'At ${d.humidity.toStringAsFixed(0)}%, sweat evaporates slower '
            'so warmth feels more intense. Cross-ventilation helps — open '
            'two windows on opposite sides if you can.',
      );
    }

    // Neutral rotating tips
    final tips = [
      (
        title: 'Why environment matters',
        body: 'Research shows that indoor conditions account for up to 20% '
            'of variations in cognitive performance — temperature, humidity '
            'and noise all play a role.',
      ),
      (
        title: 'The 50-dB sweet spot',
        body: 'Ambient noise around 50 dB (like light rain) can boost '
            'creative thinking. Complete silence is better for analytical '
            'tasks like math or coding.',
      ),
      (
        title: 'Break patterns matter',
        body: 'Your brain needs a 5-minute break every 45–60 minutes '
            'to maintain peak focus. Environmental discomfort shortens '
            'that window further.',
      ),
      (
        title: 'Humidity and health',
        body: 'The ideal humidity range is 40–60%. Below that, your skin '
            'and airways dry out. Above it, mould thrives and you feel '
            'sluggish.',
      ),
      (
        title: 'Temperature and mood',
        body: 'NASA research found that 22°C produces the fewest errors '
            'in cognitive tasks. Every degree above 25°C reduces '
            'productivity by about 2%.',
      ),
    ];

    final index = DateTime.now().minute ~/ 12; // rotates every ~12 min
    return tips[index % tips.length];
  }
}
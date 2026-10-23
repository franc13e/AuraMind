import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:auramind/services/sensor_service.dart';
import 'package:auramind/services/demo_scenario.dart';
import 'package:auramind/auramind_theme.dart';
import 'package:auramind/auramind_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorService>(builder: (context, s, _) {
      return Scaffold(
        backgroundColor: C.bg,
        appBar: AppBar(
          backgroundColor: C.bg,
          elevation: 0,
          iconTheme: const IconThemeData(color: C.t1),
          title: const Text('Settings',
              style: TextStyle(color: C.t1, fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            // ── 1. Location ─────────────────────────────────
            _SectionHeader(title: 'Location'),
            const SizedBox(height: 8),
            _LocationSection(s: s),
            const SizedBox(height: 20),

            // ── 2. Comfort Profile ──────────────────────────
            _SectionHeader(title: 'Comfort profile'),
            const SizedBox(height: 8),
            _ComfortSection(s: s),
            const SizedBox(height: 20),

            // ── 3. Display & Alerts ─────────────────────────
            _SectionHeader(title: 'Display & alerts'),
            const SizedBox(height: 8),
            _DisplaySection(s: s),
            const SizedBox(height: 20),

            // ── 4. Survey ───────────────────────────────────
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/survey'),
              child: AppCard(child: Row(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(color: C.accentSoft, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.poll_outlined, color: C.accent, size: 18),
                ),
                const SizedBox(width: 12),
                const Text('Adoption survey',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.t1)),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, color: C.t3, size: 20),
              ])),
            ),
            const SizedBox(height: 20),

            // ── 5. Demo (collapsed by default) ──────────────
            const _DemoSection(),
            const SizedBox(height: 20),

            // ── Scope note ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: C.accentSoft.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'AuraMind uses temperature and humidity from weather APIs, '
                'optional device microphone for sound, and broad user-declared '
                'location context. It does not diagnose mental health conditions.',
                style: TextStyle(fontSize: 11, color: C.t3, height: 1.45),
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ─── Section header ──────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) => SectionLabel(title);
}

// ─── 1. Location Section ─────────────────────────────────────────────────
class _LocationSection extends StatelessWidget {
  final SensorService s;
  const _LocationSection({required this.s});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Where are you now?',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.t1)),
        const SizedBox(height: 4),
        Text(
          s.currentPlace,
          style: const TextStyle(fontSize: 12, color: C.t3),
        ),
        const SizedBox(height: 14),

        // Place chips
        Wrap(
          spacing: 8, runSpacing: 8,
          children: s.locationOptions.map((place) {
            final isCustom = place == 'Custom' && !s.locationOptions.contains(s.currentPlace);
            final selected = s.currentPlace == place || isCustom;
            return ChoiceChip(
              selected: selected,
              label: Text(isCustom ? s.currentPlace : place),
              selectedColor: C.accentSoft,
              labelStyle: TextStyle(
                color: selected ? C.accent : C.t2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
              side: BorderSide(color: selected ? C.accent.withValues(alpha: 0.35) : C.border),
              onSelected: (_) async {
                if (place == 'Custom') {
                  final custom = await _askCustomPlace(context, s.currentPlace);
                  if (custom != null && custom.trim().isNotEmpty) s.setPlace(custom);
                } else {
                  s.setPlace(place);
                }
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 16),
        const Divider(height: 1, color: C.borderL),
        const SizedBox(height: 12),

        // GPS toggle — simplified
        Row(children: [
          const Icon(Icons.my_location_rounded, size: 18, color: C.accent),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Auto-detect location',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.t1)),
            Text(
              s.autoGeofenceEnabled
                  ? '${s.geofencePlaces.length} saved place${s.geofencePlaces.length == 1 ? '' : 's'}'
                  : 'Off — set manually above',
              style: const TextStyle(fontSize: 11, color: C.t3),
            ),
          ])),
          Switch(
            value: s.autoGeofenceEnabled,
            activeThumbColor: C.accent,
            onChanged: (v) async {
              await s.setAutoGeofenceEnabled(v);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.geofenceStatus)),
              );
            },
          ),
        ]),

        if (s.autoGeofenceEnabled) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _actionButton(
              icon: Icons.add_location_alt_rounded,
              label: 'Save current GPS',
              onTap: () async {
                final config = await _askGeofencePlace(context, s.currentPlace);
                if (config == null) return;
                final msg = await s.addGeofenceFromCurrentLocation(
                  label: config.label, radiusMeters: config.radius,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              },
            )),
            const SizedBox(width: 8),
            Expanded(child: _actionButton(
              icon: Icons.refresh_rounded,
              label: 'Refresh match',
              onTap: () async {
                final msg = await s.refreshGeofenceNow();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              },
            )),
          ]),

          if (s.geofencePlaces.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...s.geofencePlaces.map((place) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: C.bg, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: C.borderL, width: 0.6),
              ),
              child: Row(children: [
                const Icon(Icons.location_on_rounded, size: 14, color: C.accent),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '${place.label} · ${place.radiusMeters.round()}m',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.t2),
                )),
                GestureDetector(
                  onTap: () => s.removeGeofencePlace(place.label),
                  child: const Icon(Icons.close_rounded, size: 16, color: C.t4),
                ),
              ]),
            )),
          ],
        ],
      ]),
    );
  }

  Widget _actionButton({required IconData icon, required String label, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: C.bg, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: C.borderL),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15, color: C.accent),
            const SizedBox(width: 6),
            Flexible(child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.t2))),
          ]),
        ),
      );

  Future<String?> _askCustomPlace(BuildContext context, String current) async {
    final controller = TextEditingController(text: current == 'Custom' ? '' : current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom location'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. Study room, Lab'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<_GeofenceConfig?> _askGeofencePlace(BuildContext context, String current) async {
    final labelController = TextEditingController(text: current == 'Custom' ? 'Home' : current);
    double radius = 50;
    return showDialog<_GeofenceConfig>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: const Text('Save geofence place'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: labelController,
              decoration: const InputDecoration(labelText: 'Place label', hintText: 'Home, Campus...'),
            ),
            const SizedBox(height: 16),
            Text('Radius: ${radius.round()}m', style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(
              value: radius, min: 30, max: 300, divisions: 27,
              activeColor: C.accent,
              onChanged: (v) => setDialogState(() => radius = v),
            ),
            const Text('Tip: 50m for rooms, 150–300m for campus.',
                style: TextStyle(fontSize: 11, color: C.t3)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, _GeofenceConfig(labelController.text.trim(), radius)),
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
  }
}

class _GeofenceConfig {
  final String label;
  final double radius;
  const _GeofenceConfig(this.label, this.radius);
}

// ─── 2. Comfort Profile ──────────────────────────────────────────────────
class _ComfortSection extends StatelessWidget {
  final SensorService s;
  const _ComfortSection({required this.s});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _rangeRow(
          icon: Icons.thermostat_rounded, label: 'Temperature',
          values: RangeValues(s.comfortProfile.minTemperature, s.comfortProfile.maxTemperature),
          min: 16, max: 34, unit: '°C',
          onChanged: (v) => s.updateComfortProfile(s.comfortProfile.copyWith(
            minTemperature: v.start, maxTemperature: v.end,
          )),
        ),
        _rangeRow(
          icon: Icons.water_drop_rounded, label: 'Humidity',
          values: RangeValues(s.comfortProfile.minHumidity, s.comfortProfile.maxHumidity),
          min: 20, max: 90, unit: '%',
          onChanged: (v) => s.updateComfortProfile(s.comfortProfile.copyWith(
            minHumidity: v.start, maxHumidity: v.end,
          )),
        ),
        _sliderRow(
          icon: Icons.graphic_eq_rounded, label: 'Sound limit',
          value: s.comfortProfile.maxSound, min: 40, max: 90, divisions: 10, unit: 'dB',
          onChanged: (v) => s.updateComfortProfile(s.comfortProfile.copyWith(maxSound: v)),
        ),
        _rangeRow(
          icon: Icons.light_mode_rounded, label: 'Light',
          values: RangeValues(s.comfortProfile.minLight, s.comfortProfile.maxLight),
          min: 0, max: 1000, unit: 'lux',
          onChanged: (v) => s.updateComfortProfile(s.comfortProfile.copyWith(
            minLight: v.start, maxLight: v.end,
          )),
        ),
        const Divider(height: 1, color: C.borderL),
        const SizedBox(height: 12),
        _LightToggleRow(s: s),
        const SizedBox(height: 10),
        _MicToggleRow(s: s),
      ]),
    );
  }

  Widget _rangeRow({
    required IconData icon, required String label, required RangeValues values,
    required double min, required double max, required String unit,
    required ValueChanged<RangeValues> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 18, color: C.accent),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13, color: C.t1, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('${values.start.round()}–${values.end.round()} $unit',
            style: const TextStyle(fontSize: 12, color: C.t3)),
      ]),
      RangeSlider(values: values, min: min, max: max, divisions: (max - min).round(),
          activeColor: C.accent, inactiveColor: C.border, onChanged: onChanged),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: C.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Min: ${values.start.round()} $unit',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.accent)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: C.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Max: ${values.end.round()} $unit',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.accent)),
          ),
        ]),
      ),
    ]),
  );

  Widget _sliderRow({
    required IconData icon, required String label, required double value,
    required double min, required double max, required int divisions,
    required String unit, required ValueChanged<double> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 18, color: C.accent),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13, color: C.t1, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('${value.round()} $unit', style: const TextStyle(fontSize: 12, color: C.t3)),
      ]),
      Slider(value: value, min: min, max: max, divisions: divisions,
          activeColor: C.accent, inactiveColor: C.border, onChanged: onChanged),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: C.accentSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('Limit: ${value.round()} $unit',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.accent)),
        ),
      ),
    ]),
  );
}

class _LightToggleRow extends StatelessWidget {
  final SensorService s;
  const _LightToggleRow({required this.s});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: C.accentSoft, borderRadius: BorderRadius.circular(9)),
        child: const Icon(Icons.light_mode_rounded, size: 16, color: C.accent),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ambient light', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.t1)),
        Text(s.hasLightData ? '${s.currentLightLux.round()} lux · active' : s.lightSourceLabel,
            style: const TextStyle(fontSize: 11, color: C.t3)),
      ])),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: s.hasLightData ? C.successSoft : C.accent,
          foregroundColor: s.hasLightData ? C.success : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: s.hasLightData ? null : () async {
          await s.requestLightAccess();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(s.hasLightData ? 'Light sensor active.' : 'Light sensor unavailable.'),
          ));
        },
        child: Text(s.hasLightData ? 'Active' : 'Enable',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}

class _MicToggleRow extends StatelessWidget {
  final SensorService s;
  const _MicToggleRow({required this.s});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: C.accentSoft, borderRadius: BorderRadius.circular(9)),
        child: const Icon(Icons.mic_rounded, size: 16, color: C.accent),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Device microphone', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.t1)),
        Text(s.hasSoundData ? '${s.currentSoundDb.round()} dB · active' : s.soundSourceLabel,
            style: const TextStyle(fontSize: 11, color: C.t3)),
      ])),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: s.hasSoundData ? C.successSoft : C.accent,
          foregroundColor: s.hasSoundData ? C.success : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: s.hasSoundData ? null : () async {
          await s.requestMicrophoneAccess();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(s.hasSoundData ? 'Microphone active.' : 'Microphone unavailable.'),
          ));
        },
        child: Text(s.hasSoundData ? 'Active' : 'Enable',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}

// ─── 3. Display & Alerts ─────────────────────────────────────────────────
class _DisplaySection extends StatelessWidget {
  final SensorService s;
  const _DisplaySection({required this.s});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Chart style
        const Text('Chart style', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.t1)),
        const SizedBox(height: 10),
        Row(children: [
          _chartOption(s, ChartKind.line, 'Line', Icons.show_chart_rounded),
          const SizedBox(width: 8),
          _chartOption(s, ChartKind.bar, 'Bar', Icons.bar_chart_rounded),
          const SizedBox(width: 8),
          _chartOption(s, ChartKind.wheel, 'Wheel', Icons.donut_large_rounded),
        ]),
        const SizedBox(height: 16),

        // Alert cooldown
        const Text('Alert cooldown', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.t1)),
        const SizedBox(height: 4),
        const Text('Minutes before the same alert can fire again.',
            style: TextStyle(fontSize: 11, color: C.t3)),
        const SizedBox(height: 10),
        Row(children: [5, 10, 20, 30].map((min) {
          final selected = s.alertCooldownMinutes == min;
          return Expanded(child: Padding(
            padding: EdgeInsets.only(right: min != 30 ? 8 : 0),
            child: GestureDetector(
              onTap: () => s.setAlertCooldownMinutes(min),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? C.accent : C.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? C.accent : C.border, width: 0.5),
                ),
                child: Center(child: Text('${min}m',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : C.t2))),
              ),
            ),
          ));
        }).toList()),
        const SizedBox(height: 16),

        // Sensor refresh
        const Text('Sensor refresh', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.t1)),
        const SizedBox(height: 10),
        Row(children: [1, 3, 5, 10].map((sec) {
          final selected = s.updateInterval == sec;
          return Expanded(child: Padding(
            padding: EdgeInsets.only(right: sec != 10 ? 8 : 0),
            child: GestureDetector(
              onTap: () => s.setInterval(sec),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? C.accent : C.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? C.accent : C.border, width: 0.5),
                ),
                child: Center(child: Text('${sec}s',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : C.t2))),
              ),
            ),
          ));
        }).toList()),
      ]),
    );
  }

  Widget _chartOption(SensorService s, ChartKind kind, String label, IconData icon) {
    final selected = s.chartKind == kind;
    return Expanded(
      child: GestureDetector(
        onTap: () => s.setChartKind(kind),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? C.accent : C.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? C.accent : C.border, width: 0.5),
          ),
          child: Column(children: [
            Icon(icon, size: 18, color: selected ? Colors.white : C.t2),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: selected ? Colors.white : C.t2)),
          ]),
        ),
      ),
    );
  }
}

// ─── 5. Demo Section (collapsed) ─────────────────────────────────────────
class _DemoSection extends StatefulWidget {
  const _DemoSection();
  @override
  State<_DemoSection> createState() => _DemoSectionState();
}

class _DemoSectionState extends State<_DemoSection> {
  bool _expanded = false;
  DemoScenario? _selected;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SensorService>();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Row(children: [
          const SectionLabel('Demo & testing'),
          const Spacer(),
          Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              size: 20, color: C.t3),
        ]),
      ),
      AnimatedCrossFade(
        duration: const Duration(milliseconds: 200),
        crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        firstChild: const SizedBox.shrink(),
        secondChild: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Critical sim
              Row(children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: s.criticalMode ? C.dangerSoft : C.borderL,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.warning_rounded,
                      color: s.criticalMode ? C.danger : C.t3, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  s.criticalMode ? 'Critical active — 32.5°C · 85%' : 'Simulate critical conditions',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: s.criticalMode ? C.danger : C.t1),
                )),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _btn(
                  label: s.criticalMode ? 'Active' : 'Trigger',
                  color: s.criticalMode ? C.borderL : C.danger,
                  textColor: s.criticalMode ? C.t3 : Colors.white,
                  onTap: s.criticalMode ? null : s.triggerCritical,
                )),
                if (s.criticalMode) ...[
                  const SizedBox(width: 8),
                  Expanded(child: _btn(
                    label: 'Reset', color: C.accent, textColor: Colors.white,
                    onTap: s.resetCritical,
                  )),
                ],
              ]),

              const SizedBox(height: 16),
              const Divider(height: 1, color: C.borderL),
              const SizedBox(height: 12),

              // Scenario playback
              Text(s.isDemoPlaying
                  ? 'Playing: ${s.activeDemoScenario?.title ?? ''}'
                  : 'Scenario playback',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: s.isDemoPlaying ? C.accent : C.t1)),
              if (s.isDemoPlaying && s.demoLabel != null) ...[
                const SizedBox(height: 4),
                Text(s.demoLabel!, style: const TextStyle(fontSize: 11, color: C.t3)),
              ],
              const SizedBox(height: 10),

              if (!s.isDemoPlaying) ...[
                ...DemoScenarios.all.map((scenario) {
                  final selected = _selected?.id == scenario.id;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = scenario),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: selected ? C.accent.withValues(alpha: 0.08) : C.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: selected ? C.accent : C.border, width: 0.6),
                      ),
                      child: Row(children: [
                        Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            size: 16, color: selected ? C.accent : C.t4),
                        const SizedBox(width: 8),
                        Expanded(child: Text(scenario.title,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.t1))),
                      ]),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                _btn(
                  label: 'Start demo',
                  color: _selected == null ? C.borderL : C.accent,
                  textColor: _selected == null ? C.t4 : Colors.white,
                  onTap: _selected == null ? null : () => s.startDemo(_selected!),
                ),
              ] else
                _btn(label: 'Stop demo', color: C.dangerSoft, textColor: C.danger, onTap: s.stopDemo),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _btn({required String label, required Color color, required Color textColor, VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor))),
        ),
      );
}

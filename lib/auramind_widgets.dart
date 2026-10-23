import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:auramind/services/sensor_service.dart';
import 'package:auramind/services/agent_client.dart';
import 'package:auramind/models/auramind_models.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:auramind/auramind_theme.dart';
import 'package:auramind/config.dart';

// Navigation guide:
//  [1] Shared UI components and cards
//  [2] Mood utility helpers and feedback UI


/// Quiet section heading (sentence case, tight tracking).
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: C.t2, letterSpacing: -0.1));
}

/// Soft-elevation card — shadow instead of hard border.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding, this.color, this.onTap});
  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: color ?? C.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: C.shadowSm,
      ),
      padding: padding ?? const EdgeInsets.all(18),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: card,
      ),
    );
  }
}

/// Pill chip used for selectors.
class ChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const ChipButton({super.key, required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? C.accent : C.card,
        borderRadius: BorderRadius.circular(99),
        boxShadow: selected
            ? [BoxShadow(color: C.accent.withValues(alpha: 0.28),
                blurRadius: 12, offset: const Offset(0, 4))]
            : C.shadowSm,
      ),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          letterSpacing: -0.1, color: selected ? Colors.white : C.t2)),
    ),
  );
}

class LinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  LinePainter(this.values, {this.color = C.accent});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final stroke = Paint()..color = color..strokeWidth = 2.5
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final fill = Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.0)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
    ..style = PaintingStyle.fill;

    final path = Path(), fillPath = Path();
    for (int i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - values[i] * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevX = (i - 1) / (values.length - 1) * size.width;
        final prevY = size.height - values[i - 1] * size.height;
        final cpX = (prevX + x) / 2;
        path.cubicTo(cpX, prevY, cpX, y, x, y);
        fillPath.cubicTo(cpX, prevY, cpX, y, x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, stroke);

    final dotBg = Paint()..color = C.card..style = PaintingStyle.fill;
    final dot   = Paint()..color = color..style = PaintingStyle.fill;
    for (int i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - values[i] * size.height;
      canvas.drawCircle(Offset(x, y), 5, dotBg);
      canvas.drawCircle(Offset(x, y), 3.5, dot);
    }
  }

  @override
  bool shouldRepaint(LinePainter old) => true;
}

/// Short text label for a mood level.
String moodLabel(MoodLevel l) {
  switch (l) {
    case MoodLevel.excellent: return 'Excellent';
    case MoodLevel.good:      return 'Good';
    case MoodLevel.neutral:   return 'Neutral';
    case MoodLevel.low:       return 'Low';
    case MoodLevel.veryLow:   return 'Very low';
  }
}

/// Icon for a mood level (used where a small symbol helps).
IconData moodIcon(MoodLevel l) {
  switch (l) {
    case MoodLevel.excellent: return Icons.sentiment_very_satisfied_rounded;
    case MoodLevel.good:      return Icons.sentiment_satisfied_rounded;
    case MoodLevel.neutral:   return Icons.sentiment_neutral_rounded;
    case MoodLevel.low:       return Icons.sentiment_dissatisfied_rounded;
    case MoodLevel.veryLow:   return Icons.sentiment_very_dissatisfied_rounded;
  }
}

/// Three feedback icons (okay / not okay / not relevant).
class FeedbackRow extends StatelessWidget {
  final AgentAction action;
  final Color accent;
  const FeedbackRow({super.key, required this.action, required this.accent});

  @override
  Widget build(BuildContext context) {
    final sensor = context.watch<SensorService>();
    final id = action.id;
    final response = id == null ? null : sensor.feedbackByAction[id];
    final isSuggestion = action.tool == 'suggest_activity';

    if (response != null) {
      final label = response == 'done'
          ? 'Marked: done'
          : response == 'not_now'
              ? 'Marked: not now'
              : response == 'okay'
                  ? "Marked: I'm okay"
                  : response == 'not_okay'
                      ? "Marked: not okay"
                      : "Marked: not relevant";
      final icon = response == 'done'
          ? Icons.task_alt_rounded
          : response == 'not_now'
              ? Icons.schedule_rounded
              : response == 'okay'
                  ? Icons.check_circle_rounded
                  : response == 'not_okay'
                      ? Icons.error_rounded
                      : Icons.do_not_disturb_on_rounded;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          Icon(icon, size: 15, color: C.t3),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: C.t3, height: 1)),
        ]),
      );
    }

    if (isSuggestion) {
      Widget pill(IconData icon, String label, String value, Color color) =>
          Expanded(
            child: Tooltip(
              message: label,
              child: Material(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () =>
                      context.read<SensorService>().submitFeedback(action, value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: 6),
                        Text(label,
                            style: TextStyle(
                                fontSize: 12,
                                color: color,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(children: [
          pill(Icons.task_alt_rounded, 'Done', 'done', C.success),
          const SizedBox(width: 10),
          pill(Icons.schedule_rounded, 'Not now', 'not_now', C.t3),
        ]),
      );
    }

    Widget btn(IconData icon, String tooltip, String value) => Tooltip(
      message: tooltip,
      child: Material(
        color: accent.withValues(alpha: 0.10),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.read<SensorService>().submitFeedback(action, value),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 18, color: accent),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(children: [
        btn(Icons.thumb_up_rounded, "I'm okay", 'okay'),
        const SizedBox(width: 10),
        btn(Icons.thumb_down_rounded, "I'm not okay", 'not_okay'),
        const SizedBox(width: 10),
        btn(Icons.do_not_disturb_alt_rounded, "Not relevant", 'not_relevant'),
        const Spacer(),
        const Text('How was this?',
            style: TextStyle(fontSize: 11, color: C.t4)),
      ]),
    );
  }
}

class InterventionTrackerCard extends StatelessWidget {
  const InterventionTrackerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final records = context.watch<SensorService>().interventionRecords;
    if (records.isEmpty) {
      return AppCard(
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: C.successSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.task_alt_rounded,
                size: 19, color: C.success),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Completed suggestions will show whether your mood score improved afterward.',
              style: TextStyle(fontSize: 13, color: C.t3, height: 1.4),
            ),
          ),
        ]),
      );
    }

    return AppCard(
      child: Column(
        children: records.take(4).map((record) {
          final delta = record.scoreDelta;
          final completed = record.isComplete;
          final color = !completed
              ? C.accent
              : delta == null || delta.abs() < 1
                  ? C.t3
                  : delta >= 0
                      ? C.success
                      : C.warning;
          final status = !completed
              ? (record.response == 'not_now' ? 'Deferred' : 'Awaiting action')
              : delta == null
                  ? 'Completed'
                  : delta >= 0
                      ? '+${delta.toStringAsFixed(0)} mood points'
                      : '${delta.toStringAsFixed(0)} mood points';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  completed
                      ? Icons.task_alt_rounded
                      : record.response == 'not_now'
                          ? Icons.schedule_rounded
                          : Icons.pending_actions_rounded,
                  size: 17,
                  color: color,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: C.t1, height: 1.35)),
                    const SizedBox(height: 3),
                    Text(status,
                        style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

/// Top-of-home alert banner with feedback.
class AgentBanner extends StatelessWidget {
  const AgentBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final sensor = context.watch<SensorService>();
    AgentAction? action;
    for (final a in sensor.latestAgentActions) {
      if (a.tool == 'send_alert') { action = a; break; }
    }
    if (action == null) return const SizedBox.shrink();

    final severity = (action.args['severity'] as String?) ?? 'info';
    final message = (action.args['message'] as String?) ?? '';
    final accent = severity == 'danger' ? C.danger
        : severity == 'warning' ? C.warning : C.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: AppCard(
        color: accent.withValues(alpha: 0.07),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.warning_rounded, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AuraMind alert',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: accent, letterSpacing: 0.2)),
              const SizedBox(height: 4),
              Text(message, style: const TextStyle(fontSize: 14, height: 1.4, color: C.t1)),
            ])),
          ]),
          FeedbackRow(action: action, accent: accent),
        ]),
      ),
    );
  }
}

/// Accumulating suggestion list.
class SuggestionsList extends StatelessWidget {
  const SuggestionsList({super.key});

  @override
  Widget build(BuildContext context) {
    final sensor = context.watch<SensorService>();
    final suggestions = sensor.recentSuggestions;

    if (suggestions.isEmpty) {
      return AppCard(
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: C.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.spa_rounded, size: 19, color: C.accent),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Gentle suggestions will appear here as AuraMind learns your patterns.',
              style: TextStyle(fontSize: 13, color: C.t3, height: 1.4),
            ),
          ),
        ]),
      );
    }

    return Column(
      children: suggestions.take(5).map((s) {
        final message = (s.args['message'] as String?) ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: C.accentSoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.lightbulb_rounded, size: 18, color: C.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(message,
                      style: const TextStyle(fontSize: 13, color: C.t1, height: 1.45)),
                ),
              ]),
              FeedbackRow(action: s, accent: C.accent),
            ]),
          ),
        );
      }).toList(),
    );
  }
}


/// Mood check-in card — lets the user confirm how they actually feel.
/// This is intentionally an add-on, so it does not change the existing
/// prediction logic and is low-risk for the current app.
class MoodCheckInCard extends StatelessWidget {
  const MoodCheckInCard({super.key});

  @override
  Widget build(BuildContext context) {
    final sensor = context.watch<SensorService>();
    final predicted = sensor.latestMoodCheckIn?.predictedMood;
    final reported = sensor.latestMoodCheckIn?.reportedMood;
    final calibration = sensor.calibrationProgress;
    final accuracy = sensor.predictionAccuracy;

    Widget moodButton(String emoji, SelfMood mood) {
      final selected = reported == mood;
      return Expanded(
        child: GestureDetector(
          onTap: () => context.read<SensorService>().submitMoodCheckIn(mood),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? C.accent : C.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? C.accent : C.border,
                width: 0.7,
              ),
            ),
            child: Column(children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                mood.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : C.t3,
                ),
              ),
            ]),
          ),
        ),
      );
    }

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: C.tealSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.favorite_border_rounded,
                color: C.teal, size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mood check-in',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: C.t1, letterSpacing: -0.2)),
              SizedBox(height: 2),
              Text('Tell AuraMind how you actually feel.',
                  style: TextStyle(fontSize: 11, color: C.t3)),
            ],
          )),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          moodButton('😌', SelfMood.calm),
          const SizedBox(width: 8),
          moodButton('🙂', SelfMood.good),
          const SizedBox(width: 8),
          moodButton('😐', SelfMood.neutral),
          const SizedBox(width: 8),
          moodButton('😟', SelfMood.uneasy),
          const SizedBox(width: 8),
          moodButton('😣', SelfMood.stressed),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: C.bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Calibration',
                  style: TextStyle(fontSize: 11, color: C.t3)),
              Text('$calibration/7 check-ins',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: C.t2)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: (calibration / 7).clamp(0.0, 1.0),
                backgroundColor: C.borderL,
                valueColor: const AlwaysStoppedAnimation<Color>(C.teal),
              ),
            ),
            const SizedBox(height: 8),
            if (reported == null)
              const Text('Start with one check-in. This helps compare prediction vs self-report.',
                  style: TextStyle(fontSize: 11, color: C.t4, height: 1.35))
            else
              Text(
                'Predicted: ${predicted?.mood ?? "—"} • You reported: ${reported.label} • ${sensor.latestMoodCheckIn?.matchLabel ?? "—"}',
                style: const TextStyle(fontSize: 11, color: C.t3, height: 1.35),
              ),
            if (sensor.checkInCount > 0) ...[
              const SizedBox(height: 4),
              Text('Session accuracy: ${accuracy.toStringAsFixed(0)}% close match',
                  style: const TextStyle(fontSize: 11, color: C.teal,
                      fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Suggested reset card — one recommendation at a time.
/// Flow: Do now → active reset → Done / Not helpful.
class ActionPlanCard extends StatefulWidget {
  const ActionPlanCard({super.key});

  @override
  State<ActionPlanCard> createState() => _ActionPlanCardState();
}

class _ActionPlanCardState extends State<ActionPlanCard> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final sensor = context.watch<SensorService>();
    final active = sensor.activeResetStep;

    if (active != null) {
      return _ActiveResetCard(step: active);
    }

    final plan = sensor.actionPlan;
    if (plan == null || plan.steps.isEmpty) return const SizedBox.shrink();

    final activeSteps = plan.steps.where((s) => !s.completed && !s.skipped).toList();
    if (activeSteps.isEmpty) return const SizedBox.shrink();

    final envStep = activeSteps.where((s) => !s.isCoping).firstOrNull;
    if (envStep == null) return const SizedBox.shrink();
    final step = envStep;
    final impact = step.estimatedImpact.clamp(0, 99).toStringAsFixed(0);

    const copeColor = Color(0xFF0DA99B);
    const copeSoft = Color(0xFFE6F7F6);
    final isCopingOnly = envStep == null;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isCopingOnly ? copeSoft : C.accentSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              isCopingOnly ? Icons.spa_rounded : Icons.self_improvement_rounded,
              size: 18,
              color: isCopingOnly ? copeColor : C.accent,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCopingOnly ? 'Coping technique' : 'Suggested reset',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: C.t1, letterSpacing: -0.2),
              ),
              const SizedBox(height: 3),
              Text(
                isCopingOnly
                    ? "Can't change the space? Regulate yourself instead"
                    : 'One small action based on tracked conditions',
                style: TextStyle(fontSize: 11, color: C.t3.withValues(alpha: 0.9)),
              ),
            ],
          )),
          GestureDetector(
            onTap: sensor.dismissActionPlan,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.close_rounded, size: 16, color: C.t4),
            ),
          ),
        ]),

        ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: C.bg,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: C.borderL, width: 0.6),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(envStep.title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                      color: C.t1, letterSpacing: -0.25))),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: C.successSoft, borderRadius: BorderRadius.circular(9)),
                child: Text('+${envStep.estimatedImpact.clamp(0, 99).toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.success)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(envStep.description,
                style: const TextStyle(fontSize: 12, color: C.t3, height: 1.45)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.schedule_rounded, size: 13, color: C.t4),
              const SizedBox(width: 5),
              Text('About ${envStep.estimatedMinutes} min',
                  style: const TextStyle(fontSize: 11, color: C.t4)),
              if (envStep.hasHistory) ...[
                Container(
                  width: 3, height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: const BoxDecoration(color: C.border, shape: BoxShape.circle),
                ),
                Text('Worked ${envStep.successLabel}',
                    style: const TextStyle(fontSize: 11, color: C.accent)),
              ],
            ]),
          ]),
        ),
      ],


        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _showDetails = !_showDetails),
          child: Row(children: [
            Icon(_showDetails ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 18, color: C.accent),
            const SizedBox(width: 4),
            Text(_showDetails ? 'Hide reason' : 'Why this?',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.accent)),
          ]),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: _showDetails ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _ResetReasonBox(
              step: step,
              currentScore: plan.currentScore,
              estimatedScore: plan.estimatedScore,
              patternInsight: plan.patternInsight,
            ),
          ),
        ),
        const SizedBox(height: 13),
        Row(children: [
          Expanded(child: _ResetButton(
            icon: Icons.play_arrow_rounded,
            label: 'Do now',
            background: C.accent,
            foreground: Colors.white,
            onTap: () => sensor.startResetStep(step.id),
          )),
          const SizedBox(width: 8),
          Expanded(child: _ResetButton(
            icon: Icons.schedule_rounded,
            label: 'Not now',
            background: C.bg,
            foreground: C.t3,
            onTap: () => sensor.notNowActionStep(step.id),
          )),
          const SizedBox(width: 8),
          Expanded(child: _ResetButton(
            icon: Icons.notifications_active_outlined,
            label: 'Remind',
            background: C.bg,
            foreground: C.t3,
            onTap: () => sensor.remindActionStep(step.id),
          )),
        ]),
        const SizedBox(height: 16),
        const Divider(height: 1, thickness: 0.5),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.self_improvement_rounded, size: 13, color: C.accent),
          const SizedBox(width: 5),
          const Text("Can't change the space?",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.accent)),
        ]),
        const SizedBox(height: 10),
        if (sensor.activeResetStep == null) _AiCopingSection(sensor: sensor),
      ]),
    );
  }
}

class _ActiveResetCard extends StatelessWidget {
  final ActionStep step;
  const _ActiveResetCard({required this.step});

  @override
  Widget build(BuildContext context) {
    final sensor = context.watch<SensorService>();
    return AppCard(
      color: C.accentSoft.withValues(alpha: 0.75),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.timer_rounded, color: C.accent, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Reset in progress',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: C.t1)),
            Text('Try this for about ${step.estimatedMinutes} minutes',
                style: const TextStyle(fontSize: 11, color: C.t3)),
          ])),
        ]),
        const SizedBox(height: 14),
        Text(step.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.t1)),
        const SizedBox(height: 5),
        Text(step.description,
            style: const TextStyle(fontSize: 12, color: C.t2, height: 1.45)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _ResetButton(
            icon: Icons.task_alt_rounded,
            label: 'Done',
            background: C.success,
            foreground: Colors.white,
            onTap: () async {
              final result = await _showResetFeedbackPrompt(
                context,
                title: 'Did this reset help?',
                subtitle: 'This feedback helps AuraMind avoid useless suggestions and repeat helpful ones.',
              );
              if (!context.mounted || result == null) return;
              sensor.completeActiveReset(
                response: result.helpful ? 'done_helpful' : 'done_not_helpful',
                note: result.note,
              );
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(result.helpful
                    ? 'Saved. AuraMind will prioritise similar helpful resets.'
                    : 'Saved. AuraMind will reduce this reset in similar situations.'),
              ));
            },
          )),
          const SizedBox(width: 10),
          Expanded(child: _ResetButton(
            icon: Icons.thumb_down_alt_outlined,
            label: 'Not helpful',
            background: C.card,
            foreground: C.t3,
            onTap: () async {
              final result = await _showResetFeedbackPrompt(
                context,
                title: 'What was not helpful?',
                subtitle: 'Tell AuraMind why this reset did not work so it can avoid repeating it too soon.',
                defaultHelpful: false,
              );
              if (!context.mounted || result == null) return;
              sensor.markActiveResetNotHelpful(note: result.note);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Saved. This reset will be hidden for a while.'),
              ));
            },
          )),
        ]),
      ]),
    );
  }
}


class _ResetFeedbackResult {
  final bool helpful;
  final String? note;
  const _ResetFeedbackResult({required this.helpful, this.note});
}

Future<_ResetFeedbackResult?> _showResetFeedbackPrompt(
  BuildContext context, {
  required String title,
  required String subtitle,
  bool defaultHelpful = true,
}) {
  final controller = TextEditingController();
  bool helpful = defaultHelpful;

  return showDialog<_ResetFeedbackResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: C.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.t1)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(subtitle, style: const TextStyle(fontSize: 12, color: C.t3, height: 1.45)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _PromptChoice(
              selected: helpful,
              icon: Icons.thumb_up_alt_outlined,
              label: 'Helpful',
              onTap: () => setState(() => helpful = true),
            )),
            const SizedBox(width: 8),
            Expanded(child: _PromptChoice(
              selected: !helpful,
              icon: Icons.thumb_down_alt_outlined,
              label: 'Not helpful',
              onTap: () => setState(() => helpful = false),
            )),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: helpful
                  ? 'Optional: what helped?'
                  : 'Optional: what was wrong?',
              hintStyle: const TextStyle(fontSize: 12, color: C.t4),
              filled: true,
              fillColor: C.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: C.borderL),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: C.borderL),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: C.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(
              dialogContext,
              _ResetFeedbackResult(
                helpful: helpful,
                note: controller.text.trim().isEmpty ? null : controller.text.trim(),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

class _PromptChoice extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PromptChoice({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: selected ? C.accentSoft : C.bg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: selected ? C.accent.withValues(alpha: 0.35) : C.borderL),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 15, color: selected ? C.accent : C.t3),
        const SizedBox(width: 6),
        Flexible(child: Text(label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: selected ? C.accent : C.t3))),
      ]),
    ),
  );
}

class _ResetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _ResetButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: background == C.bg || background == C.card
            ? Border.all(color: C.borderL, width: 0.7)
            : null,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 15, color: foreground),
        const SizedBox(width: 5),
        Flexible(child: Text(label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: foreground))),
      ]),
    ),
  );
}

class _ResetReasonBox extends StatelessWidget {
  final ActionStep step;
  final double currentScore;
  final double estimatedScore;
  final String? patternInsight;

  const _ResetReasonBox({
    required this.step,
    required this.currentScore,
    required this.estimatedScore,
    required this.patternInsight,
  });

  @override
  Widget build(BuildContext context) {
    final scoreLift = (estimatedScore - currentScore).clamp(0, 99).toStringAsFixed(0);
    final triggerLabel = switch (step.trigger) {
      'temp' => 'Temperature is outside your comfort range.',
      'humidity' => 'Humidity is outside your comfort range.',
      'sound' => 'Sound is above your preferred limit.',
      'sedentary' => 'You have stayed in the same context for a while.',
      _ => 'Tracked conditions suggest this reset may help.',
    };
    final reasons = <String>[
      triggerLabel,
      'Current wellbeing score is ${currentScore.toStringAsFixed(0)}%, with an estimated +$scoreLift point lift.',
      if (patternInsight != null && patternInsight!.trim().isNotEmpty) patternInsight!,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.accentSoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Reasoning',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.accent)),
        const SizedBox(height: 7),
        ...reasons.map((reason) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(top: 6, right: 8),
              decoration: const BoxDecoration(color: C.accent, shape: BoxShape.circle),
            ),
            Expanded(child: Text(reason,
                style: const TextStyle(fontSize: 11, color: C.t2, height: 1.35))),
          ]),
        )),
      ]),
    );
  }
}

/// Daily progress ring — shows mood points recovered through
/// completed action-plan steps. Gives tangible meaning to the score.
class TodaysProgressCard extends StatelessWidget {
  const TodaysProgressCard({super.key});

  @override
  Widget build(BuildContext context) {
    final sensor = context.watch<SensorService>();
    final plan = sensor.actionPlan;

    // Gather completed steps (from the current plan).
    final completedSteps = plan?.steps.where((s) => s.completed).toList() ?? [];
    if (completedSteps.isEmpty) return const SizedBox.shrink();

    final earnedPoints = completedSteps.fold(
        0.0, (sum, s) => sum + s.estimatedImpact);
    final totalPossible = plan!.totalImpact;
    final fraction = totalPossible > 0
        ? (earnedPoints / totalPossible).clamp(0.0, 1.0)
        : 0.0;

    return AppCard(
      child: Row(children: [
        // Progress ring
        SizedBox(
          width: 58, height: 58,
          child: CustomPaint(
            painter: _ProgressRingPainter(fraction: fraction),
            child: Center(
              child: Text(earnedPoints.toStringAsFixed(0),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: C.t1)),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${earnedPoints.toStringAsFixed(0)} of '
              '${totalPossible.toStringAsFixed(0)} points recovered',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                  color: C.t1, letterSpacing: -0.2),
            ),
            const SizedBox(height: 3),
            Text(
              '${completedSteps.length} '
              'action${completedSteps.length == 1 ? "" : "s"} completed today',
              style: const TextStyle(fontSize: 12, color: C.t3),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: completedSteps.map((step) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: C.successSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_rounded, size: 11, color: C.success),
                  const SizedBox(width: 4),
                  Text(step.title,
                      style: const TextStyle(fontSize: 10,
                          fontWeight: FontWeight.w600, color: C.success)),
                ]),
              )).toList(),
            ),
          ],
        )),
      ]),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double fraction;
  _ProgressRingPainter({required this.fraction});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 3;
    const strokeWidth = 5.0;

    // Background ring
    canvas.drawCircle(center, radius,
        Paint()..color = C.borderL..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth);

    // Progress arc
    if (fraction > 0) {
      final sweep = 2 * pi * fraction;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2, sweep, false,
        Paint()..color = C.success..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) => old.fraction != fraction;
}

// ── AI coping section (inside ActionPlanCard) ────────────────────────────────
class _AiCopingSection extends StatefulWidget {
  const _AiCopingSection({required this.sensor});
  final SensorService sensor;

  @override
  State<_AiCopingSection> createState() => _AiCopingSectionState();
}

class _AiCopingSectionState extends State<_AiCopingSection> {
  Future<List<dynamic>>? _future;
  String? _lastKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  DateTime? _suppressedUntil;

  void _refresh() {
    // Stay hidden for 3 minutes after user taps Do this
    if (_suppressedUntil != null && DateTime.now().isBefore(_suppressedUntil!)) return;

    final s = widget.sensor;
    final conditions = <String>[];
    final d = s.current;
    final p = s.comfortProfile;
    if (d.temperature > p.maxTemperature + 2) {
      conditions.add('too hot (${d.temperature.round()}C)');
    }
    if (d.temperature < p.minTemperature - 2) {
      conditions.add('too cold (${d.temperature.round()}C)');
    }
    if (s.currentSoundDb > p.maxSound) {
      conditions.add('too loud (${s.currentSoundDb.round()} dB)');
    }
    if (s.currentLightLux >= 0 && s.currentLightLux < p.minLight * 0.3) {
      conditions.add('very dim (${s.currentLightLux.round()} lux)');
    }
    if (s.currentLightLux >= 0 && s.currentLightLux > p.maxLight * 1.5) {
      conditions.add('glare (${s.currentLightLux.round()} lux)');
    }
    if (d.humidity > p.maxHumidity + 10) {
      conditions.add('very humid (${d.humidity.round()}%)');
    }

    final key = conditions.join('|');
    if (key == _lastKey) return;
    _lastKey = key;

    if (conditions.isEmpty) {
      setState(() => _future = Future.value([]));
      return;
    }
    setState(() { _future = _fetchCoping(conditions); });
  }

  void _suppress() {
    setState(() {
      _suppressedUntil = DateTime.now().add(const Duration(minutes: 3));
      _future = Future.value([]);
      _lastKey = null;
    });
  }

  Future<List<dynamic>> _fetchCoping(List<String> conditions) async {
    try {
      final response = await http.post(
        Uri.parse('$apiBase/coping'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'conditions': conditions}),
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final data = jsonDecode(response.body);
      return data['steps'] as List;
    } catch (e) {
      debugPrint('AiCopingSection error: $e');
      return [
        {'title': 'Slow your breathing', 'description': 'Breathe in 4 counts, hold 2, out 6. Repeat 5 times.', 'minutes': 2},
        {'title': 'Cool your wrists', 'description': 'Press something cool to your wrists for 20 seconds.', 'minutes': 1},
        {'title': 'Focus anchor', 'description': 'Pick one nearby object and describe it mentally for 60 seconds.', 'minutes': 1},
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: C.accent),
              ),
              SizedBox(width: 8),
              Text('Getting AI suggestions...', style: TextStyle(fontSize: 11, color: C.t3)),
            ]),
          );
        }
        final steps = snap.data ?? [];
        if (steps.isEmpty) {
          return const Text('Environment looks manageable right now.',
              style: TextStyle(fontSize: 11, color: C.t3));
        }
        return Column(
          children: steps.map<Widget>((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: C.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item['title'] as String,
                        style: const TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w600, color: C.t1)),
                    const SizedBox(height: 2),
                    Text(item['description'] as String,
                        style: const TextStyle(fontSize: 11, color: C.t2, height: 1.4)),
                    const SizedBox(height: 2),
                    Text('~${item['minutes'] as num} min',
                        style: const TextStyle(fontSize: 10, color: C.t4)),
                  ])),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      _suppress();
                      widget.sensor.startCopingStep(ActionStep(
                        id: 'ai_${item['title'].hashCode}',
                        title: item['title'] as String,
                        description: item['description'] as String,
                        estimatedImpact: 8,
                        estimatedMinutes: (item['minutes'] as num).toInt(),
                        trigger: 'ai_coping',
                        isCoping: true,
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: C.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Do this',
                          style: TextStyle(fontSize: 11,
                              fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

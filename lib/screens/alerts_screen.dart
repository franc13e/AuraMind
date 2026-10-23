import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:auramind/services/sensor_service.dart';
import 'package:auramind/services/agent_client.dart';
import 'package:auramind/models/auramind_models.dart';
import 'package:auramind/auramind_theme.dart';
import 'package:auramind/auramind_widgets.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  Color _color(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.danger: return C.danger;
      case AlertSeverity.warning: return C.warning;
      case AlertSeverity.info: return C.accent;
    }
  }

  Color _bg(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.danger: return C.dangerSoft;
      case AlertSeverity.warning: return C.warningSoft;
      case AlertSeverity.info: return C.accentSoft;
    }
  }

  IconData _icon(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.danger: return Icons.error_outline_rounded;
      case AlertSeverity.warning: return Icons.warning_amber_rounded;
      case AlertSeverity.info: return Icons.info_outline_rounded;
    }
  }

  String _label(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.danger: return 'Critical';
      case AlertSeverity.warning: return 'Warning';
      case AlertSeverity.info: return 'Info';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SensorService>(builder: (context, s, _) {
      final alerts = s.alerts;
      final unread = s.unreadAlerts;
      final interventions = [
        ...s.latestAgentActions.where((a) => a.tool == 'send_alert'),
        ...s.recentSuggestions,
      ];

      return Scaffold(
        backgroundColor: C.bg,
        body: SafeArea(
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                child: Row(children: [
                  const Text('Alerts', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: C.t1)),
                  const SizedBox(width: 8),
                  if (unread > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: C.danger, borderRadius: BorderRadius.circular(20)),
                      child: Text('$unread', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded, color: C.t2),
                    onSelected: (value) {
                      if (value == 'read') s.markAllRead();
                      if (value == 'clear') s.clearReadAlerts();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'read', child: Text('Mark all read')),
                      PopupMenuItem(value: 'clear', child: Text('Clear read alerts')),
                    ],
                  ),
                ]),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: AppCard(
                  color: C.accentSoft.withValues(alpha: 0.7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.timer_outlined, color: C.accent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      'Repeat alerts are cooled down for ${s.alertCooldownMinutes} minutes, so the same condition should not ping every second.',
                      style: const TextStyle(fontSize: 12, color: C.t2, height: 1.4),
                    )),
                  ]),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: Padding(
              padding: EdgeInsets.fromLTRB(20, 22, 20, 10),
              child: SectionLabel('Agent interventions'),
            )),
            if (interventions.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: AppCard(
                    child: SizedBox(
                      height: 60,
                      child: Center(child: Text('AuraMind has nothing to share right now.',
                          style: TextStyle(fontSize: 12, color: C.t3))),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((ctx, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _InterventionCard(action: interventions[i]),
                  ), childCount: interventions.length),
                ),
              ),

            const SliverToBoxAdapter(child: Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: SectionLabel('System alerts'),
            )),
            if (alerts.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: AppCard(
                    child: SizedBox(
                      height: 60,
                      child: Center(child: Text('All clear — tracked conditions are within range.',
                          style: TextStyle(fontSize: 12, color: C.t3))),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    final alert = alerts[i];
                    final color = _color(alert.severity);
                    final bg = _bg(alert.severity);
                    final ts = '${alert.timestamp.hour.toString().padLeft(2,'0')}:${alert.timestamp.minute.toString().padLeft(2,'0')}';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () => s.markAlertRead(alert),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          decoration: BoxDecoration(
                            color: alert.isRead ? C.card : bg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: alert.isRead ? C.border : color.withValues(alpha: 0.25), width: 0.5),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: alert.isRead ? C.borderL : color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_icon(alert.severity), color: alert.isRead ? C.t3 : color, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(alert.title,
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                          color: alert.isRead ? C.t2 : color))),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: alert.isRead ? C.borderL : color.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6)),
                                    child: Text(_label(alert.severity),
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                                            color: alert.isRead ? C.t3 : color)),
                                  ),
                                ]),
                                const SizedBox(height: 4),
                                Text(alert.message,
                                    style: TextStyle(fontSize: 12,
                                        color: alert.isRead ? C.t3 : color.withValues(alpha: 0.82), height: 1.35)),
                                const SizedBox(height: 6),
                                Text(ts, style: const TextStyle(fontSize: 10, color: C.t4)),
                              ])),
                              if (!alert.isRead) ...[
                                const SizedBox(width: 8),
                                Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4),
                                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                              ],
                            ]),
                            const SizedBox(height: 12),
                            if (alert.feedback == null)
                              Row(children: [
                                Expanded(child: _feedbackBtn(Icons.thumb_up_alt_outlined, 'Helpful', C.success,
                                    () async {
                                      final note = await _askAlertFeedback(context, helpful: true);
                                      if (!context.mounted || note == null) return;
                                      s.submitAlertFeedback(alert, 'helpful', note: note);
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                        content: Text('Saved as helpful.'),
                                      ));
                                    })),
                                const SizedBox(width: 8),
                                Expanded(child: _feedbackBtn(Icons.thumb_down_alt_outlined, 'Not helpful', C.warning,
                                    () async {
                                      final note = await _askAlertFeedback(context, helpful: false);
                                      if (!context.mounted || note == null) return;
                                      s.submitAlertFeedback(alert, 'not_helpful', note: note);
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                        content: Text('Saved as not helpful.'),
                                      ));
                                    })),
                                const SizedBox(width: 8),
                                Expanded(child: _feedbackBtn(Icons.check_rounded, 'Read', C.t3,
                                    () => s.markAlertRead(alert))),
                              ])
                            else
                              Row(children: [
                                Icon(alert.feedback == 'helpful'
                                    ? Icons.thumb_up_alt_rounded
                                    : Icons.thumb_down_alt_rounded,
                                    size: 15,
                                    color: alert.feedback == 'helpful' ? C.success : C.warning),
                                const SizedBox(width: 6),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(alert.feedback == 'helpful' ? 'Marked helpful' : 'Marked not helpful',
                                      style: const TextStyle(fontSize: 11, color: C.t3, fontWeight: FontWeight.w600)),
                                  if (alert.feedbackNote != null && alert.feedbackNote!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(alert.feedbackNote!,
                                        style: const TextStyle(fontSize: 10, color: C.t4, height: 1.3)),
                                  ],
                                ])),
                              ]),
                          ]),
                        ),
                      ),
                    );
                  }, childCount: alerts.length),
                ),
              ),
          ]),
        ),
      );
    });
  }

  Widget _feedbackBtn(IconData icon, String label, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(child: Text(label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color))),
      ]),
    ),
  );
}


Future<String?> _askAlertFeedback(BuildContext context, {required bool helpful}) {
  final controller = TextEditingController();
  return showDialog<String?>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: C.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(helpful ? 'What made this alert helpful?' : 'Why was this alert not helpful?',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.t1)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          helpful
              ? 'AuraMind will use this feedback to keep useful alerts visible.'
              : 'AuraMind will use this feedback to reduce unnecessary alerts.',
          style: const TextStyle(fontSize: 12, color: C.t3, height: 1.45),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: helpful ? 'Optional reason' : 'Optional: too frequent, irrelevant, wrong timing...',
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
          onPressed: () => Navigator.pop(dialogContext, null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: C.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _InterventionCard extends StatelessWidget {
  final AgentAction action;
  const _InterventionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    final isAlert = action.tool == 'send_alert';
    final severity = isAlert ? (action.args['severity'] as String?) ?? 'info' : 'info';
    final message = (action.args['message'] as String?) ?? '';
    final accent = !isAlert
        ? C.accent
        : severity == 'danger' ? C.danger
        : severity == 'warning' ? C.warning
        : C.accent;

    return AppCard(
      color: accent.withValues(alpha: 0.06),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(isAlert ? Icons.warning_amber_rounded : Icons.tips_and_updates_outlined,
              color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isAlert ? 'Agent alert' : 'Agent suggestion',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent, letterSpacing: 0.04)),
            const SizedBox(height: 3),
            Text(message, style: const TextStyle(fontSize: 13, color: C.t1, height: 1.35)),
          ])),
        ]),
        FeedbackRow(action: action, accent: accent),
      ]),
    );
  }
}

// lib/screens/adoption_survey_screen.dart
//
// Technology Acceptance Model (TAM) / UTAUT adoption survey.
// Validates H4: Agentic AI environmental monitoring positively
// influences user adoption in the mental health industry.
//
// Captures: perceived usefulness, perceived ease of use, trust in AI,
// privacy perception, intention to adopt, and overall satisfaction.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auramind/auramind_theme.dart';
import 'package:auramind/auramind_widgets.dart';

const String _surveyKey = 'auramind_adoption_survey_v1';

class _SurveyItem {
  final String id;
  final String construct; // TAM/UTAUT construct
  final String question;
  int? rating; // 1–5 Likert scale

  _SurveyItem({
    required this.id,
    required this.construct,
    required this.question,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'construct': construct,
    'question': question,
    'rating': rating,
  };
}

class AdoptionSurveyScreen extends StatefulWidget {
  const AdoptionSurveyScreen({super.key});
  @override
  State<AdoptionSurveyScreen> createState() => _AdoptionSurveyScreenState();
}

class _AdoptionSurveyScreenState extends State<AdoptionSurveyScreen> {
  bool _submitted = false;
  String? _additionalFeedback;
  final _feedbackCtrl = TextEditingController();

  final List<_SurveyItem> _items = [
    // ── Perceived Usefulness (PU) ──────────────────────────────
    _SurveyItem(
      id: 'pu1',
      construct: 'Perceived usefulness',
      question: 'The system helps me understand environmental factors affecting mood.',
    ),
    _SurveyItem(
      id: 'pu2',
      construct: 'Perceived usefulness',
      question: 'The proactive alerts are useful for early mood intervention.',
    ),
    _SurveyItem(
      id: 'pu3',
      construct: 'Perceived usefulness',
      question: 'The mood predictions help me take better care of patients or myself.',
    ),

    // ── Perceived Ease of Use (PEOU) ──────────────────────────
    _SurveyItem(
      id: 'peou1',
      construct: 'Perceived ease of use',
      question: 'The app interface is easy to navigate and understand.',
    ),
    _SurveyItem(
      id: 'peou2',
      construct: 'Perceived ease of use',
      question: 'The sensor data collection requires minimal effort from me.',
    ),

    // ── Trust in AI ───────────────────────────────────────────
    _SurveyItem(
      id: 'tr1',
      construct: 'Trust in AI',
      question: 'I trust the AI-generated mood assessments.',
    ),
    _SurveyItem(
      id: 'tr2',
      construct: 'Trust in AI',
      question: 'The system recommendations feel personalised and relevant.',
    ),

    // ── Privacy Perception ────────────────────────────────────
    _SurveyItem(
      id: 'pp1',
      construct: 'Privacy perception',
      question: 'I feel my environmental and mood data is handled securely.',
    ),
    _SurveyItem(
      id: 'pp2',
      construct: 'Privacy perception',
      question: 'The passive data collection method respects my privacy.',
    ),

    // ── Intention to Adopt ────────────────────────────────────
    _SurveyItem(
      id: 'ia1',
      construct: 'Intention to adopt',
      question: 'I would use this system regularly as part of mental health care.',
    ),
    _SurveyItem(
      id: 'ia2',
      construct: 'Intention to adopt',
      question: 'I would recommend this system to colleagues or other patients.',
    ),

    // ── Overall Satisfaction ──────────────────────────────────
    _SurveyItem(
      id: 'os1',
      construct: 'Overall satisfaction',
      question: 'Overall, I am satisfied with the AuraMind system.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedSurvey();
  }

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSurvey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_surveyKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _submitted = data['submitted'] as bool? ?? false;
      _additionalFeedback = data['feedback'] as String?;
      final ratings = data['ratings'] as Map<String, dynamic>? ?? {};
      for (final item in _items) {
        item.rating = ratings[item.id] as int?;
      }
      if (_additionalFeedback != null) {
        _feedbackCtrl.text = _additionalFeedback!;
      }
      setState(() {});
    } catch (_) {}
  }

  Future<void> _saveSurvey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ratings = <String, int>{};
      for (final item in _items) {
        if (item.rating != null) ratings[item.id] = item.rating!;
      }
      await prefs.setString(_surveyKey, jsonEncode({
        'submitted': _submitted,
        'feedback': _feedbackCtrl.text.trim(),
        'ratings': ratings,
        'submitted_at': DateTime.now().toIso8601String(),
      }));
    } catch (_) {}
  }

  bool get _allAnswered => _items.every((i) => i.rating != null);

  Map<String, double> get _constructAverages {
    final groups = <String, List<int>>{};
    for (final item in _items) {
      if (item.rating != null) {
        groups.putIfAbsent(item.construct, () => []).add(item.rating!);
      }
    }
    return groups.map((k, v) =>
        MapEntry(k, v.reduce((a, b) => a + b) / v.length));
  }

  void _submit() {
    if (!_allAnswered) return;
    setState(() => _submitted = true);
    _saveSurvey();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: C.t1),
        title: const Text('Adoption survey',
            style: TextStyle(
                color: C.t1, fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: _submitted ? _buildResults() : _buildSurvey(),
      ),
    );
  }

  Widget _buildSurvey() {
    String? currentConstruct;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Help us evaluate AuraMind',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: C.t1)),
              SizedBox(height: 6),
              Text(
                'This survey measures your perception of the system based on the '
                'Technology Acceptance Model (TAM). Your responses help validate '
                'whether agentic AI environmental monitoring positively influences '
                'user adoption in mental health care.',
                style: TextStyle(fontSize: 13, color: C.t3, height: 1.5),
              ),
              SizedBox(height: 10),
              Text(
                'Rate each statement from 1 (strongly disagree) to 5 (strongly agree).',
                style: TextStyle(
                    fontSize: 13, color: C.accent, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._items.map((item) {
          final showHeader = item.construct != currentConstruct;
          currentConstruct = item.construct;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader) ...[
                const SizedBox(height: 12),
                SectionLabel(item.construct),
                const SizedBox(height: 8),
              ],
              _QuestionCard(
                item: item,
                onChanged: (v) {
                  setState(() => item.rating = v);
                  _saveSurvey();
                },
              ),
              const SizedBox(height: 10),
            ],
          );
        }),
        const SizedBox(height: 8),
        const SectionLabel('Additional feedback (optional)'),
        const SizedBox(height: 8),
        TextField(
          controller: _feedbackCtrl,
          maxLines: 3,
          style: const TextStyle(fontSize: 13, color: C.t1),
          decoration: const InputDecoration(
            hintText: 'Share any thoughts about the system...',
            hintStyle: TextStyle(fontSize: 13, color: C.t4),
          ),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: _allAnswered ? _submit : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _allAnswered ? C.accent : C.borderL,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text('Submit survey',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _allAnswered ? Colors.white : C.t4)),
            ),
          ),
        ),
        if (!_allAnswered)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_items.where((i) => i.rating == null).length} question${_items.where((i) => i.rating == null).length == 1 ? '' : 's'} remaining',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: C.t3),
            ),
          ),
      ],
    );
  }

  Widget _buildResults() {
    final averages = _constructAverages;
    final overallAvg = averages.values.isEmpty
        ? 0.0
        : averages.values.reduce((a, b) => a + b) / averages.values.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: C.successSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: C.success, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Survey submitted',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: C.t1)),
                ),
              ]),
              const SizedBox(height: 14),
              Text('Overall adoption score: ${overallAvg.toStringAsFixed(1)} / 5.0',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: C.accent)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: overallAvg / 5.0,
                  backgroundColor: C.borderL,
                  valueColor: const AlwaysStoppedAnimation(C.accent),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const SectionLabel('Construct breakdown'),
        const SizedBox(height: 8),
        ...averages.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: C.t1)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: e.value / 5.0,
                            backgroundColor: C.borderL,
                            valueColor: AlwaysStoppedAnimation(
                                e.value >= 3.5 ? C.success : e.value >= 2.5 ? C.warning : C.danger),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(e.value.toStringAsFixed(1),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: e.value >= 3.5
                              ? C.success
                              : e.value >= 2.5
                                  ? C.warning
                                  : C.danger)),
                ]),
              ),
            )),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            setState(() => _submitted = false);
            _saveSurvey();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: C.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text('Edit responses',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: C.accent)),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final _SurveyItem item;
  final ValueChanged<int> onChanged;

  const _QuestionCard({required this.item, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.question,
              style: const TextStyle(
                  fontSize: 13, color: C.t1, height: 1.4)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Disagree',
                  style: TextStyle(fontSize: 10, color: C.t4)),
              const Spacer(),
              ...List.generate(5, (i) {
                final value = i + 1;
                final selected = item.rating == value;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => onChanged(value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: selected ? C.accent : C.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? C.accent : C.border,
                          width: selected ? 1.5 : 0.5,
                        ),
                      ),
                      child: Center(
                        child: Text('$value',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    selected ? FontWeight.w700 : FontWeight.w500,
                                color: selected ? Colors.white : C.t2)),
                      ),
                    ),
                  ),
                );
              }),
              const Spacer(),
              const Text('Agree',
                  style: TextStyle(fontSize: 10, color: C.t4)),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:laya_dart/laya_dart.dart';
import 'demo/snake_game.dart';

/// Local dev bundle assembled by tool/export_local_model.py; see laya_dart/models/laya.
const _modelDir =
    '/Users/manu.junjanna/Projects/open_source/laya_dart/laya_dart/models/laya';

const _sampleEmails = {
  'Billing dispute + churn risk':
      'Hi, we were billed twice for our March subscription. Please '
      'refund the duplicate charge today or we will have to cancel our plan and move to a '
      'competitor. This is the second billing issue this quarter.',
  'Technical bug report':
      "The export button on the dashboard throws a 500 error every time I "
      "click it, on both Chrome and Safari. This is blocking our end-of-month reporting. Can "
      "someone from engineering take a look?",
  'Sales enquiry':
      'Hello, we are evaluating your platform for a 200-seat rollout next quarter. '
      'Could you send pricing for the enterprise tier and let us know about volume discounts?',
  'Urgent refund threat':
      "I want a refund immediately. Your product does not work as advertised "
      "and I have already wasted three days trying to fix it myself. If I don't hear back by "
      "end of day I'm filing a chargeback and cancelling my account.",
  'Low-key technical question':
      'Quick question - is there a way to export reports as CSV instead '
      'of PDF? Not urgent, just curious if it is on the roadmap.',
  'Happy renewal, no issues':
      "Just wanted to say the new dashboard update is great, our team is "
      "really enjoying it. No issues to report, just renewed for another year.",
};

void main() {
  runApp(const LayaDemoApp());
}

class LayaDemoApp extends StatelessWidget {
  const LayaDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Laya Email Triage Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const LayaDemoPage(),
    );
  }
}

class LayaDemoPage extends StatefulWidget {
  const LayaDemoPage({super.key});

  @override
  State<LayaDemoPage> createState() => _LayaDemoPageState();
}

class _LayaDemoPageState extends State<LayaDemoPage> {
  final _controller = TextEditingController(text: _sampleEmails.values.first);
  String? _selectedSample = _sampleEmails.keys.first;
  Laya? _agent;
  Map<String, Object>? _result;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _agent?.close();
    super.dispose();
  }

  Future<void> _analyze() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      // Model load is one-time and stays resident for the rest of the session.
      _agent ??= await Laya.load(_modelDir);
      final result = await _agent!.predictAsync(_controller.text, {
        'department': LayaQuestion.choice(
          instructions: 'Which department should handle this request?',
          criteria: {
            'billing': 'invoices, payments, refunds',
            'technical': 'bugs, outages, system errors',
            'sales': 'pricing, new contracts',
            'other': 'everything else',
          },
        ),
        'urgency': LayaQuestion.score(
          instructions: 'How urgent is this request?',
          criteria: [
            'not urgent',
            'soon',
            'critical deadline or blocking issue',
          ],
        ),
        'churn_risk': LayaQuestion.noul(
          instructions: 'Does the sender threaten to cancel or leave?',
        ),
        'refund_requested': LayaQuestion.noul(
          instructions: 'Does the sender explicitly request a refund?',
        ),
      });
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final answers = _result?['answers'] as Map<String, Object>?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laya Email Triage Demo'),
        actions: [
          IconButton(
            tooltip: 'Open Laya Snake',
            icon: const Icon(Icons.sports_esports),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SnakeGamePage()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text(
              'Sample emails',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in _sampleEmails.keys)
                  ChoiceChip(
                    label: Text(name),
                    selected: _selectedSample == name,
                    onSelected: (_) => setState(() {
                      _selectedSample = name;
                      _controller.text = _sampleEmails[name]!;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'State (email body)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 6,
              onChanged: (_) => setState(() => _selectedSample = null),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Paste an email...',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _analyze,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.psychology),
              label: Text(_loading ? 'Running Laya…' : 'Analyze with Laya'),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (answers != null) ...[
              _ChoiceResultCard(
                title: 'Department',
                answer: answers['department'] as Map<String, Object>,
              ),
              const SizedBox(height: 12),
              _ScoreResultCard(
                title: 'Urgency',
                answer: answers['urgency'] as Map<String, Object>,
              ),
              const SizedBox(height: 12),
              _NoulResultCard(
                title: 'Churn risk',
                flaggedLabel: 'Customer may cancel',
                safeLabel: 'No churn signal',
                answer: answers['churn_risk'] as Map<String, Object>,
              ),
              const SizedBox(height: 12),
              _NoulResultCard(
                title: 'Refund requested',
                flaggedLabel: 'Refund requested',
                safeLabel: 'No refund requested',
                answer: answers['refund_requested'] as Map<String, Object>,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChoiceResultCard extends StatelessWidget {
  const _ChoiceResultCard({required this.title, required this.answer});

  final String title;
  final Map<String, Object> answer;

  @override
  Widget build(BuildContext context) {
    final choice = answer['choice'] as String;
    final probabilities = Map<String, double>.from(
      (answer['probabilities'] as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      ),
    );
    final confidence = (answer['confidence'] as num).toDouble();
    final sortedLabels = probabilities.keys.toList()
      ..sort((a, b) => probabilities[b]!.compareTo(probabilities[a]!));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(label: Text(choice.toUpperCase())),
                const SizedBox(width: 8),
                Text('confidence ${(confidence * 100).toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 8),
            for (final label in sortedLabels)
              _ProbabilityBar(label: label, value: probabilities[label]!),
          ],
        ),
      ),
    );
  }
}

class _NoulResultCard extends StatelessWidget {
  const _NoulResultCard({
    required this.title,
    required this.answer,
    required this.flaggedLabel,
    required this.safeLabel,
  });

  final String title;
  final Map<String, Object> answer;
  final String flaggedLabel;
  final String safeLabel;

  @override
  Widget build(BuildContext context) {
    final noul = (answer['noul'] as num).toDouble();
    final flagged = noul > 0.5;
    return Card(
      color: flagged ? Colors.orange.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  flagged ? Icons.warning_amber : Icons.check_circle,
                  color: flagged ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(flagged ? flaggedLabel : safeLabel),
              ],
            ),
            const SizedBox(height: 8),
            _ProbabilityBar(label: 'P(true)', value: noul),
          ],
        ),
      ),
    );
  }
}

class _ScoreResultCard extends StatelessWidget {
  const _ScoreResultCard({required this.title, required this.answer});

  final String title;
  final Map<String, Object> answer;

  @override
  Widget build(BuildContext context) {
    final score = (answer['score'] as num).toDouble();
    final legend = Map<String, String>.from(
      (answer['legend'] as Map).map(
        (k, v) => MapEntry(k as String, v as String),
      ),
    );
    final maxLevel = legend.length - 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${score.toStringAsFixed(2)} / $maxLevel'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: maxLevel == 0 ? 0 : (score / maxLevel).clamp(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProbabilityBar extends StatelessWidget {
  const _ProbabilityBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(label)),
          Expanded(child: LinearProgressIndicator(value: value.clamp(0, 1))),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text('${(value * 100).toStringAsFixed(0)}%'),
          ),
        ],
      ),
    );
  }
}

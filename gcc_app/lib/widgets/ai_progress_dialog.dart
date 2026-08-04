/// Step-by-step progress while the AI advisor works (field backlog #3b).
///
/// The operator asked to see what it is doing rather than a spinner. Worth
/// being precise about what is honest here, because a progress display
/// that invents activity is worse than a spinner:
///
///  - "Reading the mission" and "Checking the plan" are real local work.
///  - "Asking the model" is a real network wait, and it is the long one.
///  - "Placing on the map" is a REVEAL, not live streaming. The model
///    returns every placement at once; showing them appear one at a time
///    is presentation. It is defensible because it lets the operator watch
///    where each one lands instead of a plan materialising whole, and the
///    step is worded as placing rather than as receiving.
///
/// Nothing here claims the model is thinking step by step. It is not, and
/// a thesis that says otherwise would be wrong.
library;

import 'package:flutter/material.dart';

enum AiStep { reading, asking, checking, placing, done, failed }

class AiProgress extends ChangeNotifier {
  AiStep step = AiStep.reading;

  /// How many placements have been revealed so far, and how many there are
  /// in total once the answer has arrived.
  int placed = 0;
  int total = 0;
  String failure = '';

  void to(AiStep s) {
    step = s;
    notifyListeners();
  }

  void reveal(int count, int of) {
    placed = count;
    total = of;
    step = AiStep.placing;
    notifyListeners();
  }

  void fail(String message) {
    failure = message;
    step = AiStep.failed;
    notifyListeners();
  }
}

class AiProgressDialog extends StatelessWidget {
  const AiProgressDialog({super.key, required this.progress});

  final AiProgress progress;

  static const _labels = {
    AiStep.reading: 'Reading the mission',
    AiStep.asking: 'Asking the model',
    AiStep.checking: 'Checking the plan',
    AiStep.placing: 'Placing on the map',
  };

  static const _detail = {
    AiStep.reading: 'area, drones, modules, cached specs, and what you drew',
    AiStep.asking: 'this is the slow part, and it needs internet',
    AiStep.checking: 'inside the area, within range of each other, in budget',
    AiStep.placing: 'each one appears where the model put it',
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final order = [
          AiStep.reading,
          AiStep.asking,
          AiStep.checking,
          AiStep.placing,
        ];
        final currentIndex = order.indexOf(progress.step);
        return AlertDialog(
          title: const Text('AI deployment advisor'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < order.length; i++)
                  _row(
                    context,
                    label: _labels[order[i]]!,
                    detail: _detail[order[i]]!,
                    state: progress.step == AiStep.failed
                        ? (i <= currentIndex ? _RowState.failed : _RowState.todo)
                        : progress.step == AiStep.done || i < currentIndex
                            ? _RowState.done
                            : i == currentIndex
                                ? _RowState.active
                                : _RowState.todo,
                    trailing: order[i] == AiStep.placing && progress.total > 0
                        ? '${progress.placed} of ${progress.total}'
                        : '',
                  ),
                if (progress.step == AiStep.failed) ...[
                  const SizedBox(height: 12),
                  Text(progress.failure,
                      style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 12),
                Text(
                  'The advisor only proposes markers. It never commands a '
                  'drone, and nothing it suggests takes effect until you '
                  'approve it.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context,
      {required String label,
      required String detail,
      required _RowState state,
      String trailing = ''}) {
    final Widget leading;
    switch (state) {
      case _RowState.done:
        leading = const Icon(Icons.check_circle,
            size: 18, color: Colors.greenAccent);
        break;
      case _RowState.active:
        leading = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        break;
      case _RowState.failed:
        leading = const Icon(Icons.error, size: 18, color: Colors.redAccent);
        break;
      case _RowState.todo:
        leading = const Icon(Icons.circle_outlined,
            size: 18, color: Colors.white38);
        break;
    }
    final dim = state == _RowState.todo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontWeight:
                          state == _RowState.active ? FontWeight.bold : null,
                      color: dim ? Colors.white38 : null,
                    )),
                Text(detail,
                    style: TextStyle(
                        fontSize: 11,
                        color: dim ? Colors.white24 : Colors.white54)),
              ],
            ),
          ),
          if (trailing.isNotEmpty)
            Text(trailing, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

enum _RowState { todo, active, done, failed }

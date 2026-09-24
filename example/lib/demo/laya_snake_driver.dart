import 'dart:developer' as developer;

import 'package:laya_dart/laya_dart.dart';
import 'snake_game.dart';

/// Laya policy matching the reference Snake demo: Laya scores all four moves,
/// while the Hamiltonian-cycle planner supplies the safety shield.
class LayaSnakeDriver {
  LayaSnakeDriver._(this._model);

  static const _modelDir =
      '/Users/manu.junjanna/Projects/open_source/laya_dart/laya_dart/models/laya';

  static Future<LayaSnakeDriver> load() async =>
      LayaSnakeDriver._(await Laya.load(_modelDir));

  final Laya _model;
  void close() => _model.close();

  Future<SnakeDecision> choose(SnakeEngine game) async {
    final moves = SnakeDirection.values;
    final moveInfo = game.moves;
    final safeInfo = moveInfo.where((move) => move.safe).toList();
    if (safeInfo.isEmpty) {
      throw StateError('Cycle safety invariant violated: no safe action');
    }
    final safeMoves = safeInfo.map((move) => move.direction).toList();
    final preferred = safeInfo.isEmpty
        ? null
        : safeInfo.reduce((a, b) => a.advance >= b.advance ? a : b).direction;
    final reachability = game.foodReachability();

    final result = await _model.predictAsync(
      _describeState(game, safeMoves, reachability),
      {
        'move': LayaQuestion.choice(
          instructions: 'Choose the best safe move toward food.',
          criteria: {
            for (final move in moveInfo)
              _label(move.direction): _describeMove(move, preferred),
          },
        ),
        'risk': LayaQuestion.noul(
          instructions: 'Is a safe route available for the snake?',
        ),
        'food': LayaQuestion.noul(
          instructions: 'Is food reachable through empty cells?',
        ),
      },
    );

    final answers = result['answers'] as Map;
    final moveAnswer = answers['move'] as Map;
    final rawProbabilities = moveAnswer['probabilities'] as Map;
    final probabilities = <String, double>{
      for (final move in moves)
        move.name: ((rawProbabilities[_label(move)] as num?) ?? 0).toDouble(),
    };
    final risk = _noul(answers['risk']);
    final food = _noul(answers['food']);
    final scores = [...probabilities.values, risk, food];
    if (scores.any((value) => !value.isFinite || value < 0 || value > 1)) {
      throw StateError(
        'Laya returned an invalid probability; no move executed',
      );
    }
    // The reference policy defines the proposal as the raw top-1 probability,
    // rather than trusting the serialized choice field.
    final proposed = moves.reduce(
      (a, b) => probabilities[b.name]! > probabilities[a.name]! ? b : a,
    );

    // This is the reference policy: execute Laya's top-1 when safe; otherwise
    // execute Laya's highest-probability cycle-safe choice.
    final executable = safeMoves.contains(proposed)
        ? proposed
        : safeMoves.reduce(
            (a, b) => probabilities[b.name]! > probabilities[a.name]! ? b : a,
          );
    _log(
      game,
      probabilities,
      proposed,
      executable,
      safeMoves,
      preferred,
      risk,
      food,
    );
    return SnakeDecision(
      proposed,
      executable,
      probabilities,
      deadEndRisk: 1 - risk,
      foodReachable: food,
    );
  }

  double _noul(Object? answer) =>
      ((answer as Map?)?['noul'] as num?)?.toDouble() ?? 0;

  String _label(SnakeDirection move) => move.name.toUpperCase();

  String _describeState(
    SnakeEngine game,
    List<SnakeDirection> safeMoves,
    ({bool reachable, int openCells}) reachability,
  ) =>
      'Safe route: ${safeMoves.isNotEmpty ? 'yes' : 'no'}. '
      'Food reachable through empty cells: ${reachability.reachable ? 'yes' : 'no'}.';

  String _describeMove(SnakeMoveInfo move, SnakeDirection? preferred) {
    if (!move.legal) return 'Blocked. Collision.';
    if (!move.safe) return 'Unsafe. Traps the snake.';
    if (move.eats) return 'Safe. Eat food now. Best.';
    if (move.direction == preferred) return 'Safe. Best route to food.';
    return 'Safe. Slower route.';
  }

  void _log(
    SnakeEngine game,
    Map<String, double> probabilities,
    SnakeDirection requested,
    SnakeDirection executable,
    List<SnakeDirection> safeMoves,
    SnakeDirection? preferred,
    double risk,
    double food,
  ) {
    final details = game.moves
        .map((move) {
          final probability = ((probabilities[move.direction.name] ?? 0) * 100)
              .toStringAsFixed(1);
          return '${move.direction.name.toUpperCase()}: $probability% | '
              '${move.safe ? 'safe' : move.reason} | ${_describeMove(move, preferred)}';
        })
        .join('\n');
    developer.log(
      'Snake state: head=${game.snake.first} food=${game.food} heading=${game.direction.name} score=${game.score}\n'
      '$details\n'
      'safe=${safeMoves.map((move) => move.name).join(',')} plannerBest=${preferred?.name ?? 'none'} '
      'risk=${(risk * 100).toStringAsFixed(1)}% foodReachable=${(food * 100).toStringAsFixed(1)}%\n'
      'Laya requested=${requested.name.toUpperCase()} executed=${executable.name.toUpperCase()}',
      name: 'LayaSnake',
    );
  }
}

class SnakeDecision {
  const SnakeDecision(
    this.requested,
    this.direction,
    this.probabilities, {
    this.deadEndRisk = 0,
    this.foodReachable = 0,
  });

  final SnakeDirection requested;
  final SnakeDirection direction;
  final Map<String, double> probabilities;
  final double deadEndRisk;
  final double foodReachable;
}

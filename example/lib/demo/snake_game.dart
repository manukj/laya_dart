import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'laya_snake_driver.dart';

/// Snake rules and UI. Laya requests live in laya_snake_driver.dart.
class SnakeGamePage extends StatefulWidget {
  const SnakeGamePage({super.key});

  @override
  State<SnakeGamePage> createState() => _SnakeGamePageState();
}

class _SnakeGamePageState extends State<SnakeGamePage>
    with SingleTickerProviderStateMixin {
  // Match laya-coreml-snake's defaults: 24x16 at 12 decisions per second.
  static const _columns = 24;
  static const _rows = 16;
  static const _tick = Duration(milliseconds: 83);

  SnakeEngine _game = SnakeEngine(columns: _columns, rows: _rows);
  Timer? _timer;
  LayaSnakeDriver? _agent;
  String _status = 'Loading Laya…';
  bool _busy = false;
  int _generation = 0;
  int _moveNumber = 0;
  final List<_DecisionEntry> _decisions = [];
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    // An outstanding inference may still be using the model. Close after it
    // returns rather than invalidating its native session mid-call.
    if (!_busy) _agent?.close();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final agent = await LayaSnakeDriver.load();
      if (!mounted) {
        agent.close();
        return;
      }
      _agent = agent;
      setState(() => _status = 'Laya is driving');
      _timer = Timer.periodic(_tick, (_) => _step());
    } catch (error) {
      if (mounted) setState(() => _status = 'Could not load Laya: $error');
    }
  }

  Future<void> _step() async {
    if (_busy || _game.gameOver || _game.won || _agent == null) return;
    _busy = true;
    final generation = _generation;
    try {
      if (_game.legalMoves.isEmpty) {
        _endGame();
        return;
      }
      final decision = await _agent!.choose(_game);
      if (!mounted || generation != _generation) return;
      setState(() {
        _moveNumber++;
        _decisions.insert(
          0,
          _DecisionEntry(
            move: _moveNumber,
            requested: decision.requested.name,
            direction: decision.direction.name,
            probabilities: decision.probabilities,
            deadEndRisk: decision.deadEndRisk,
            foodReachable: decision.foodReachable,
          ),
        );
        if (_decisions.length > 40) _decisions.removeLast();
        _game.move(decision.direction);
        if (_game.won) {
          _status = 'Board filled — Laya won!';
          _timer?.cancel();
        } else {
          _status = 'Laya is driving';
        }
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        _timer?.cancel();
        setState(() => _status = 'Decision error: $error');
      }
    } finally {
      _busy = false;
      if (!mounted) _agent?.close();
    }
  }

  void _endGame() {
    _timer?.cancel();
    setState(() {
      _game.gameOver = true;
      _status =
          'Game over — Laya ate ${_game.score} food ${_game.score == 1 ? 'dot' : 'dots'}';
    });
  }

  void _reset() {
    _timer?.cancel();
    _generation++;
    setState(() {
      _game = SnakeEngine(columns: _columns, rows: _rows);
      _moveNumber = 0;
      _status = _agent == null ? 'Loading Laya…' : 'Laya is driving';
      _decisions.clear();
    });
    if (_agent != null) _timer = Timer.periodic(_tick, (_) => _step());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xff202020),
        elevation: 0,
        title: const Text('Laya Snake Demo'),
      ),
      body: ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 800),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'SCORE',
                              style: TextStyle(
                                color: Color(0xff777777),
                                fontSize: 11,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _game.score.toString().padLeft(3, '0'),
                              style: const TextStyle(
                                color: Color(0xff333333),
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.circle,
                        size: 9,
                        color: Color(0xff444444),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _status.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xff777777),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .7,
                        ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: _reset,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 320,
                          child: _DecisionPanel(decisions: _decisions),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: _columns / _rows,
                              child: AnimatedBuilder(
                                animation: _pulse,
                                builder: (context, child) => CustomPaint(
                                  painter: _SnakePainter(
                                    snake: _game.snake,
                                    food: _game.food,
                                    columns: _columns,
                                    rows: _rows,
                                    pulse: _pulse.value,
                                  ),
                                  child: child,
                                ),
                                child: _game.gameOver || _game.won
                                    ? Center(
                                        child: Card(
                                          child: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Text(
                                              _game.won
                                                  ? 'Board filled! Laya won. Press Reset to play again.'
                                                  : 'No safe moves left. Press Reset to try again.',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleLarge,
                                            ),
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Laya proposes every move; cycle safety intervenes only when needed.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DecisionEntry {
  const _DecisionEntry({
    required this.move,
    required this.requested,
    required this.direction,
    required this.probabilities,
    required this.deadEndRisk,
    required this.foodReachable,
  });

  final int move;
  final String requested;
  final String direction;
  final Map<String, double>? probabilities;
  final double deadEndRisk;
  final double foodReachable;
}

class _DecisionPanel extends StatelessWidget {
  const _DecisionPanel({required this.decisions});

  final List<_DecisionEntry> decisions;

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xff242424);
    const muted = Color(0xff707070);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffd0d0d0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: foreground),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.memory_rounded,
                    color: Color(0xff444444),
                    size: 20,
                  ),
                  SizedBox(width: 9),
                  Text(
                    'LAYA  /  LIVE DECISION',
                    style: TextStyle(
                      color: Color(0xff333333),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'NEXT MOVE',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              _DirectionProbabilities(
                probabilities: decisions.isEmpty
                    ? null
                    : decisions.first.probabilities,
                selected: decisions.isEmpty ? null : decisions.first.requested,
              ),
              if (decisions.isNotEmpty) ...[
                const SizedBox(height: 16),
                _EstimateBar(
                  label: 'DEAD-END RISK',
                  value: decisions.first.deadEndRisk,
                  color: const Color(0xff555555),
                ),
                const SizedBox(height: 11),
                _EstimateBar(
                  label: 'FOOD REACHABLE',
                  value: decisions.first.foodReachable,
                  color: const Color(0xff777777),
                ),
              ],
              const Divider(height: 30, color: Color(0xffd0d0d0)),
              decisions.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'WAITING FOR LAYA…',
                          style: TextStyle(color: muted),
                        ),
                      ),
                    )
                  : _CurrentDecision(decision: decisions.first),
              const Divider(height: 30, color: Color(0xffd0d0d0)),
              const Text(
                'RECENT MOVES',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: decisions.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.separated(
                        itemCount: decisions.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 7),
                        itemBuilder: (context, index) =>
                            _DecisionHistoryTile(decision: decisions[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionProbabilities extends StatelessWidget {
  const _DirectionProbabilities({required this.probabilities, this.selected});

  final Map<String, double>? probabilities;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    const directions = ['up', 'down', 'left', 'right'];
    return Column(
      children: [
        for (final direction in directions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 68,
                  child: Row(
                    children: [
                      Icon(
                        _directionIcon(direction),
                        size: 15,
                        color: selected == direction
                            ? const Color(0xff333333)
                            : const Color(0xff888888),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        direction.toUpperCase(),
                        style: TextStyle(
                          color: selected == direction
                              ? const Color(0xff444444)
                              : const Color(0xff666666),
                          fontSize: 12,
                          fontWeight: selected == direction
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: probabilities?[direction] ?? 0),
                    duration: const Duration(milliseconds: 300),
                    builder: (_, value, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 7,
                        color: selected == direction
                            ? const Color(0xff444444)
                            : const Color(0xff888888),
                        backgroundColor: const Color(0xffdddddd),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${((probabilities?[direction] ?? 0) * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: selected == direction
                          ? const Color(0xff222222)
                          : const Color(0xff777777),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  IconData _directionIcon(String direction) => switch (direction) {
    'up' => Icons.keyboard_arrow_up_rounded,
    'down' => Icons.keyboard_arrow_down_rounded,
    'left' => Icons.keyboard_arrow_left_rounded,
    _ => Icons.keyboard_arrow_right_rounded,
  };
}

class _EstimateBar extends StatelessWidget {
  const _EstimateBar({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xff777777),
                  fontSize: 11,
                  letterSpacing: .8,
                ),
              ),
            ),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 6,
            color: color,
            backgroundColor: const Color(0xffdddddd),
          ),
        ),
      ],
    );
  }
}

class _CurrentDecision extends StatelessWidget {
  const _CurrentDecision({required this.decision});
  final _DecisionEntry decision;

  @override
  Widget build(BuildContext context) {
    final intervened = decision.requested != decision.direction;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffc0c0c0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Color(0xffeeeeee),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _icon(decision.direction),
                color: const Color(0xff444444),
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EXECUTING',
                    style: TextStyle(
                      color: Color(0xff777777),
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    decision.direction.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xff222222),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    intervened
                        ? 'Laya proposed ${decision.requested.toUpperCase()} · safety shield'
                        : 'Laya top-1 · no intervention',
                    style: TextStyle(
                      color: intervened
                          ? const Color(0xff555555)
                          : const Color(0xff777777),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _icon(String direction) => switch (direction) {
    'up' => Icons.arrow_upward,
    'down' => Icons.arrow_downward,
    'left' => Icons.arrow_back,
    _ => Icons.arrow_forward,
  };
}

class _DecisionHistoryTile extends StatelessWidget {
  const _DecisionHistoryTile({required this.decision});

  final _DecisionEntry decision;

  @override
  Widget build(BuildContext context) {
    final intervened = decision.requested != decision.direction;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            '#${decision.move}',
            style: const TextStyle(
              color: Color(0xff888888),
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 9),
          Icon(
            _icon(decision.direction),
            color: const Color(0xff444444),
            size: 17,
          ),
          const SizedBox(width: 6),
          Text(
            decision.direction.toUpperCase(),
            style: const TextStyle(
              color: Color(0xff333333),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            intervened ? 'SHIELD' : 'LAYA',
            style: TextStyle(
              color: intervened
                  ? const Color(0xff555555)
                  : const Color(0xff888888),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: .7,
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon(String direction) => switch (direction) {
    'up' => Icons.arrow_upward_rounded,
    'down' => Icons.arrow_downward_rounded,
    'left' => Icons.arrow_back_rounded,
    _ => Icons.arrow_forward_rounded,
  };
}

class _SnakePainter extends CustomPainter {
  const _SnakePainter({
    required this.snake,
    required this.food,
    required this.columns,
    required this.rows,
    required this.pulse,
  });
  final List<Point<int>> snake;
  final Point<int> food;
  final int columns;
  final int rows;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = min(size.width / columns, size.height / rows);
    final offset = Offset(
      (size.width - cell * columns) / 2,
      (size.height - cell * rows) / 2,
    );
    final board = Paint()..color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(offset.dx, offset.dy, cell * columns, cell * rows),
      board,
    );
    final grid = Paint()
      ..color = const Color(0xffdddddd)
      ..style = PaintingStyle.stroke;
    for (var x = 0; x <= columns; x++) {
      canvas.drawLine(
        Offset(offset.dx + x * cell, offset.dy),
        Offset(offset.dx + x * cell, offset.dy + rows * cell),
        grid,
      );
    }
    for (var y = 0; y <= rows; y++) {
      canvas.drawLine(
        Offset(offset.dx, offset.dy + y * cell),
        Offset(offset.dx + columns * cell, offset.dy + y * cell),
        grid,
      );
    }
    final apple = Paint()..color = const Color(0xff444444);
    canvas.drawCircle(
      Offset(
        offset.dx + (food.x + .5) * cell,
        offset.dy + (food.y + .5) * cell,
      ),
      cell * (.28 + pulse * .06),
      apple,
    );
    for (var i = snake.length - 1; i >= 0; i--) {
      final segment = snake[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            offset.dx + segment.x * cell + 1,
            offset.dy + segment.y * cell + 1,
            cell - 2,
            cell - 2,
          ),
          Radius.circular(cell * .18),
        ),
        Paint()
          ..color = i == 0
              ? Color.lerp(
                  const Color(0xff222222),
                  const Color(0xff777777),
                  pulse * .25,
                )!
              : const Color(0xff666666),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnakePainter oldDelegate) => true;
}

enum SnakeDirection { up, down, left, right }

class SnakeMoveInfo {
  const SnakeMoveInfo({
    required this.direction,
    required this.legal,
    required this.safe,
    required this.advance,
    required this.reason,
    required this.eats,
  });

  final SnakeDirection direction;
  final bool legal;
  final bool safe;
  final int advance;
  final String reason;
  final bool eats;
}

extension SnakeDirectionMove on SnakeDirection {
  Point<int> get offset => switch (this) {
    SnakeDirection.up => const Point(0, -1),
    SnakeDirection.down => const Point(0, 1),
    SnakeDirection.left => const Point(-1, 0),
    SnakeDirection.right => const Point(1, 0),
  };

  SnakeDirection get opposite => switch (this) {
    SnakeDirection.up => SnakeDirection.down,
    SnakeDirection.down => SnakeDirection.up,
    SnakeDirection.left => SnakeDirection.right,
    SnakeDirection.right => SnakeDirection.left,
  };
}

/// Grid rules only; the UI and model can inspect legal moves before advancing.
class SnakeEngine {
  SnakeEngine({
    required this.columns,
    required this.rows,
    List<Point<int>>? initialSnake,
    Point<int>? initialFood,
    Random? random,
  }) : random = random ?? Random(7) {
    cycle = _hamiltonianCycle(columns, rows);
    cycleIndex = {for (var i = 0; i < cycle.length; i++) cycle[i]: i};
    snake = List.of(
      initialSnake ??
          [
            for (var i = 0; i < 6; i++)
              cycle[(cycle.length ~/ 2 - i) % cycle.length],
          ],
    );
    food = initialFood ?? _spawnFood();
    if (snake.isEmpty ||
        snake.toSet().length != snake.length ||
        snake.any((cell) => !_inside(cell)) ||
        !_inside(food) ||
        snake.contains(food)) {
      throw ArgumentError('Invalid initial snake or food position');
    }
  }

  final int columns;
  final int rows;
  final Random random;
  late final List<Point<int>> cycle;
  late final Map<Point<int>, int> cycleIndex;
  late List<Point<int>> snake;
  late Point<int> food;
  SnakeDirection direction = SnakeDirection.right;
  int score = 0;
  int ticks = 0;
  bool gameOver = false;
  bool won = false;
  String? deathReason;

  static List<Point<int>> _hamiltonianCycle(int width, int height) {
    if (width < 4 || height < 4 || (width.isOdd && height.isOdd)) {
      throw ArgumentError(
        'Snake board needs dimensions >= 4 with an even side',
      );
    }
    if (height.isOdd) {
      return [
        for (final cell in _hamiltonianCycle(height, width))
          Point(cell.y, cell.x),
      ];
    }
    final path = <Point<int>>[const Point(0, 0)];
    for (var y = 0; y < height; y++) {
      final xs = y.isEven
          ? Iterable.generate(width - 1, (i) => i + 1)
          : Iterable.generate(width - 1, (i) => width - 1 - i);
      path.addAll(xs.map((x) => Point(x, y)));
    }
    path.addAll(Iterable.generate(height - 1, (i) => Point(0, height - 1 - i)));
    return path;
  }

  Point<int> nextHead(SnakeDirection move) => snake.first + move.offset;

  bool _inside(Point<int> cell) =>
      cell.x >= 0 && cell.x < columns && cell.y >= 0 && cell.y < rows;

  String legalReason(SnakeDirection move) {
    if (gameOver || won) return 'finished';
    final next = nextHead(move);
    if (!_inside(next)) return 'wall';
    if (snake.length > 1 && next == snake[1]) return 'reverse';
    final eats = next == food;
    // On an ordinary move the tail vacates its cell. When eating it stays.
    final occupied = eats ? snake : snake.take(snake.length - 1);
    return occupied.contains(next) ? 'body' : 'legal';
  }

  bool isLegal(SnakeDirection move) => legalReason(move) == 'legal';

  List<SnakeMoveInfo> get moves {
    if (gameOver || won) return const [];
    final headIndex = cycleIndex[snake.first]!;
    final tailDistance = (cycleIndex[snake.last]! - headIndex) % cycle.length;
    final foodDistance = (cycleIndex[food]! - headIndex) % cycle.length;
    return SnakeDirection.values.map((move) {
      final reason = legalReason(move);
      final legal = reason == 'legal';
      final target = nextHead(move);
      final advance = (cycleIndex[target] ?? headIndex) - headIndex;
      final forward = (advance + cycle.length) % cycle.length;
      final eats = target == food;
      var safe = legal;
      var safeReason = reason;
      if (safe &&
          (forward > tailDistance || (forward == tailDistance && eats))) {
        safe = false;
        safeReason = 'would cross the tail';
      }
      if (safe && (forward == 0 || forward > foodDistance)) {
        safe = false;
        safeReason = 'would skip the food on the safe route';
      }
      return SnakeMoveInfo(
        direction: move,
        legal: legal,
        safe: safe,
        advance: forward,
        reason: safeReason,
        eats: eats,
      );
    }).toList();
  }

  List<SnakeDirection> get legalMoves =>
      moves.where((move) => move.legal).map((move) => move.direction).toList();

  ({bool reachable, int openCells}) foodReachability() {
    final blocked = snake.toSet()..remove(snake.first);
    final seen = <Point<int>>{snake.first};
    final queue = <Point<int>>[snake.first];
    for (var i = 0; i < queue.length; i++) {
      final cell = queue[i];
      for (final direction in SnakeDirection.values) {
        final next = cell + direction.offset;
        if (_inside(next) && !blocked.contains(next) && seen.add(next)) {
          queue.add(next);
        }
      }
    }
    return (reachable: seen.contains(food), openCells: seen.length);
  }

  bool move(SnakeDirection move) {
    ticks++;
    final reason = legalReason(move);
    if (reason != 'legal') {
      gameOver = true;
      deathReason = reason;
      return false;
    }
    final next = nextHead(move);
    final eats = next == food;
    snake.insert(0, next);
    if (eats) {
      score++;
      if (snake.length == columns * rows) {
        won = true;
      } else {
        _placeFood();
      }
    } else {
      snake.removeLast();
    }
    direction = move;
    return true;
  }

  void _placeFood() {
    final occupied = snake.toSet();
    final empty = cycle.where((cell) => !occupied.contains(cell)).toList();
    food = empty[random.nextInt(empty.length)];
  }

  Point<int> _spawnFood() {
    final occupied = snake.toSet();
    final empty = cycle.where((cell) => !occupied.contains(cell)).toList();
    return empty[random.nextInt(empty.length)];
  }
}

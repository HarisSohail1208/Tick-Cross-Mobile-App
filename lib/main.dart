import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const TickCrossApp());
}

class TickCrossApp extends StatelessWidget {
  const TickCrossApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tick Cross',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xff12031f),
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: TickCrossColors.purpleGlow,
          brightness: Brightness.dark,
        ),
      ),
      home: const GameScreen(),
    );
  }
}

enum Player { team1, team2 }

// Startup selection for human-vs-bot or human-vs-human play.
enum GameMode { singlePlayer, doublePlayer }

extension PlayerDetails on Player {
  String get symbol => this == Player.team1 ? '\u2713' : '\u2715';

  Color get color =>
      this == Player.team1 ? TickCrossColors.tick : TickCrossColors.cross;
}

class WinResult {
  const WinResult({
    required this.player,
    required this.cells,
  });

  final Player player;
  final List<int> cells;
}

class TickCrossColors {
  static const backgroundTop = Color(0xff251047);
  static const backgroundBottom = Color(0xff070012);
  static const panel = Color(0x1cffffff);
  static const purpleGlow = Color(0xffc05cff);
  static const tick = Color(0xffff4fab);
  static const cross = Color(0xff31f8ff);
  static const win = Color(0xfffff35a);
  static const draw = Color(0xff9cff7a);
}

class GameSoundController {
  static const _soundEnabledKey = 'sound_enabled';
  static const _tapSound = 'sounds/tap.wav';
  static const _winSound = 'sounds/win.wav';
  static const _drawSound = 'sounds/draw.wav';
  static const _buttonSound = 'sounds/button.wav';

  final AudioPlayer _player = AudioPlayer(playerId: 'tick_cross_effects');
  bool enabled = true;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(_soundEnabledKey) ?? true;
      await _player.setReleaseMode(ReleaseMode.stop);
    } catch (_) {
      enabled = true;
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_soundEnabledKey, value);
      if (!value) {
        await _player.stop();
      }
    } catch (_) {
      enabled = value;
    }
  }

  Future<void> playTap() => _play(_tapSound, volume: .22);

  Future<void> playWin() => _play(_winSound, volume: .34);

  Future<void> playDraw() => _play(_drawSound, volume: .28);

  Future<void> playButton() => _play(_buttonSound, volume: .24);

  Future<void> _play(String asset, {required double volume}) async {
    if (!enabled) return;

    try {
      await _player.stop();
      await _player.play(AssetSource(asset), volume: volume);
    } catch (_) {
      // Audio should enhance the game, never interrupt it.
    }
  }

  Future<void> dispose() => _player.dispose();
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  // Rows, columns, and diagonals for the 3x3 board.
  static const List<List<int>> _winPatterns = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
  ];

  late final AnimationController _lineController;
  late final GameSoundController _sounds;
  List<Player?> _board = List<Player?>.filled(9, null);
  List<int> _winningCells = [];
  // Remembers who should open the next board instead of always using Team 1.
  Player _startingPlayer = Player.team1;
  Player _currentPlayer = Player.team1;
  String _team1Name = 'Team 1';
  String _team2Name = 'Team 2';
  int _team1Score = 0;
  int _team2Score = 0;
  int _drawScore = 0;
  int _completedMatches = 0;
  // Single player mode turns Team 2 into a delayed medium-difficulty bot.
  GameMode? _gameMode;
  bool _roundLocked = false;
  bool _botThinking = false;
  int _botTurnId = 0;
  bool _dialogVisible = false;
  bool _soundEnabled = true;
  bool _adVisible = false;

  @override
  void initState() {
    super.initState();
    _sounds = GameSoundController();
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    unawaited(_loadSoundPreference());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showGameModeSelection());
    });
  }

  @override
  void dispose() {
    _lineController.dispose();
    unawaited(_sounds.dispose());
    super.dispose();
  }

  String get _currentPlayerName =>
      _currentPlayer == Player.team1 ? _team1Name : _team2Name;

  bool get _isSinglePlayer => _gameMode == GameMode.singlePlayer;

  bool get _isBotTurn => _isSinglePlayer && _currentPlayer == Player.team2;

  String _nameFor(Player player) =>
      player == Player.team1 ? _team1Name : _team2Name;

  // Shows once on launch before the first playable turn.
  Future<void> _showGameModeSelection() async {
    if (!mounted) return;

    final selectedMode = await showDialog<GameMode>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const GameModeDialog(),
    );

    if (!mounted) return;

    setState(() {
      _gameMode = selectedMode ?? GameMode.doublePlayer;
      if (_isSinglePlayer) {
        _team2Name = 'Bot';
      }
    });

    _startBotTurnIfNeeded();
  }

  Future<void> _loadSoundPreference() async {
    await _sounds.init();
    if (!mounted) return;

    setState(() {
      _soundEnabled = _sounds.enabled;
    });
  }

  Future<void> _toggleSound() async {
    final nextValue = !_soundEnabled;
    if (_soundEnabled) {
      unawaited(_sounds.playButton());
    }

    await _sounds.setEnabled(nextValue);
    if (!mounted) return;

    setState(() {
      _soundEnabled = nextValue;
    });

    if (nextValue) {
      unawaited(_sounds.playButton());
    }
  }

  void _onCellTap(int index) {
    if (_gameMode == null || _roundLocked || _botThinking || _isBotTurn) {
      return;
    }

    _playMove(index);
  }

  void _playMove(int index) {
    if (_roundLocked || _board[index] != null) return;

    HapticFeedback.lightImpact();
    unawaited(_sounds.playTap());

    setState(() {
      _board[index] = _currentPlayer;
    });

    final result = _findWinner();
    if (result != null) {
      _finishWithWinner(result);
      return;
    }

    if (_board.every((cell) => cell != null)) {
      _finishDraw();
      return;
    }

    setState(() {
      _currentPlayer =
          _currentPlayer == Player.team1 ? Player.team2 : Player.team1;
    });

    if (_isBotTurn) {
      _startBotTurnIfNeeded();
    }
  }

  void _startBotTurnIfNeeded() {
    if (_isBotTurn) {
      unawaited(_startBotTurn());
    }
  }

  // Bot turn entry point. The delay makes the AI feel intentional and blocks
  // human taps while the bot is thinking.
  Future<void> _startBotTurn() async {
    if (!_isBotTurn || _roundLocked || _botThinking) return;

    setState(() {
      _botThinking = true;
      _botTurnId++;
    });

    // Medium difficulty waits briefly, then chooses the strongest available move.
    final botTurnId = _botTurnId;
    final delayMs = 500 + math.Random().nextInt(301);
    await Future<void>.delayed(Duration(milliseconds: delayMs));

    if (!mounted || botTurnId != _botTurnId || !_isBotTurn || _roundLocked) {
      return;
    }

    _makeBotMove();
  }

  // Medium bot priority: win, block, center, corner, then any empty cell.
  void _makeBotMove() {
    final move = _findWinningMove(Player.team2) ??
        _findWinningMove(Player.team1) ??
        (_board[4] == null ? 4 : null) ??
        _findPreferredCornerMove() ??
        _findRandomEmptyMove();

    if (move == null) {
      if (mounted) {
        setState(() {
          _botThinking = false;
        });
      }
      return;
    }

    setState(() {
      _botThinking = false;
    });
    _playMove(move);
  }

  // Used for both the bot winning check and the human block check.
  int? _findWinningMove(Player player) {
    for (final pattern in _winPatterns) {
      final playerCells =
          pattern.where((index) => _board[index] == player).length;
      final emptyCells = pattern.where((index) => _board[index] == null);

      if (playerCells == 2 && emptyCells.length == 1) {
        return emptyCells.first;
      }
    }
    return null;
  }

  int? _findPreferredCornerMove() {
    const corners = [0, 2, 6, 8];
    final emptyCorners =
        corners.where((index) => _board[index] == null).toList();
    if (emptyCorners.isEmpty) return null;
    return emptyCorners[math.Random().nextInt(emptyCorners.length)];
  }

  int? _findRandomEmptyMove() {
    final emptyCells = <int>[
      for (var index = 0; index < _board.length; index++)
        if (_board[index] == null) index,
    ];
    if (emptyCells.isEmpty) return null;
    return emptyCells[math.Random().nextInt(emptyCells.length)];
  }

  WinResult? _findWinner() {
    for (final pattern in _winPatterns) {
      final first = _board[pattern[0]];
      if (first == null) continue;

      final hasWon = pattern.every((index) => _board[index] == first);
      if (hasWon) {
        return WinResult(player: first, cells: pattern);
      }
    }
    return null;
  }

  void _finishWithWinner(WinResult result) {
    HapticFeedback.mediumImpact();
    unawaited(_sounds.playWin());

    setState(() {
      _roundLocked = true;
      _winningCells = result.cells;
      _completedMatches++;
      // The losing player gets the first move in the next match.
      _startingPlayer =
          result.player == Player.team1 ? Player.team2 : Player.team1;
      if (result.player == Player.team1) {
        _team1Score++;
      } else {
        _team2Score++;
      }
    });

    _lineController.forward(from: 0);
    unawaited(
      _showResultAndReset('\u{1F389} ${_nameFor(result.player)} Wins!'),
    );
  }

  void _finishDraw() {
    HapticFeedback.lightImpact();
    unawaited(_sounds.playDraw());

    setState(() {
      _roundLocked = true;
      _drawScore++;
      _completedMatches++;
      // Drawn matches alternate the opener from whoever started this board.
      _startingPlayer =
          _startingPlayer == Player.team1 ? Player.team2 : Player.team1;
    });
    unawaited(_showResultAndReset('\u{1F91D} Match Draw!'));
  }

  Future<void> _showResultAndReset(String message) async {
    if (_dialogVisible) return;
    _dialogVisible = true;

    // Keep dialog ownership in one place so every round closes cleanly.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ResultDialog(message: message),
      ).whenComplete(() {
        _dialogVisible = false;
      }),
    );

    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    if (_dialogVisible && navigator.canPop()) {
      navigator.pop();
    }
    _clearBoard(startBotTurn: false);
    await _showAdIfNeeded();
    if (!mounted) return;

    _startBotTurnIfNeeded();
  }

  void _clearBoard({bool startBotTurn = true}) {
    setState(() {
      _board = List<Player?>.filled(9, null);
      _winningCells = [];
      _currentPlayer = _startingPlayer;
      _roundLocked = false;
      _botThinking = false;
      _botTurnId++;
    });
    _lineController.reset();
    if (startBotTurn) {
      _startBotTurnIfNeeded();
    }
  }

  void _onNewMatchPressed() {
    unawaited(_sounds.playButton());
    _clearBoard();
  }

  Future<void> _showAdIfNeeded() async {
    if (_completedMatches == 0 || _completedMatches % 3 != 0 || _adVisible) {
      return;
    }
    if (!mounted) return;

    _adVisible = true;

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, animation, __) {
          return FadeTransition(
            opacity: animation,
            child: const InterstitialAdScreen(),
          );
        },
      ),
    );

    _adVisible = false;
  }

  Future<void> _editName(Player player) async {
    if (_isSinglePlayer && player == Player.team2) return;

    final updatedName = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(initialName: _nameFor(player)),
    );

    final cleanName = updatedName?.trim();
    if (!mounted || cleanName == null || cleanName.isEmpty) return;

    setState(() {
      if (player == Player.team1) {
        _team1Name = cleanName;
      } else {
        _team2Name = cleanName;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.3,
            colors: [
              TickCrossColors.backgroundTop,
              TickCrossColors.backgroundBottom,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            child: Column(
              children: [
                HeaderBar(
                  soundEnabled: _soundEnabled,
                  onSoundPressed: _toggleSound,
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: PlayerScoreCard(
                        name: _team1Name,
                        score: _team1Score,
                        color: TickCrossColors.tick,
                        symbol: Player.team1.symbol,
                        onDoubleTap: () => _editName(Player.team1),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PlayerScoreCard(
                        name: 'Draw',
                        score: _drawScore,
                        color: TickCrossColors.draw,
                        symbol: '=',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PlayerScoreCard(
                        name: _team2Name,
                        score: _team2Score,
                        color: TickCrossColors.cross,
                        symbol: Player.team2.symbol,
                        onDoubleTap: () => _editName(Player.team2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: TurnLabel(
                    key: ValueKey('$_currentPlayerName-$_botThinking'),
                    text: _botThinking
                        ? '$_team2Name Thinking...'
                        : '$_currentPlayerName Turn',
                    color: _currentPlayer.color,
                  ),
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: Center(
                    child: GameBoard(
                      board: _board,
                      winningCells: _winningCells,
                      lineAnimation: _lineController,
                      onCellTap: _onCellTap,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                NewMatchButton(onPressed: _onNewMatchPressed),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HeaderBar extends StatelessWidget {
  const HeaderBar({
    required this.soundEnabled,
    required this.onSoundPressed,
    super.key,
  });

  final bool soundEnabled;
  final VoidCallback onSoundPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        const NeonTitle(),
        Align(
          alignment: Alignment.centerRight,
          child: NeonIconButton(
            icon: soundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            tooltip: soundEnabled ? 'Sound on' : 'Sound off',
            onPressed: onSoundPressed,
          ),
        ),
      ],
    );
  }
}

class NeonTitle extends StatelessWidget {
  const NeonTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 48),
      child: Text(
        'TICK CROSS',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
          color: Colors.white,
          shadows: [
            Shadow(color: TickCrossColors.purpleGlow, blurRadius: 8),
            Shadow(color: TickCrossColors.purpleGlow, blurRadius: 24),
            Shadow(color: TickCrossColors.tick, blurRadius: 42),
          ],
        ),
      ),
    );
  }
}

class NeonIconButton extends StatelessWidget {
  const NeonIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TickCrossColors.panel,
          shape: BoxShape.circle,
          border: Border.all(color: TickCrossColors.purpleGlow, width: 1.6),
          boxShadow: [
            BoxShadow(
              color: TickCrossColors.purpleGlow.withOpacity(.55),
              blurRadius: 22,
            ),
          ],
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class PlayerScoreCard extends StatelessWidget {
  const PlayerScoreCard({
    required this.name,
    required this.score,
    required this.color,
    required this.symbol,
    this.onDoubleTap,
    super.key,
  });

  final String name;
  final int score;
  final Color color;
  final String symbol;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: TickCrossColors.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(.9), width: 1.8),
          boxShadow: [
            BoxShadow(color: color.withOpacity(.55), blurRadius: 24),
            BoxShadow(color: color.withOpacity(.22), blurRadius: 48),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              symbol,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: color, blurRadius: 18)],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                shadows: [Shadow(color: color, blurRadius: 14)],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$score',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TurnLabel extends StatelessWidget {
  const TurnLabel({
    required this.text,
    required this.color,
    super.key,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: 23,
        fontWeight: FontWeight.w800,
        shadows: [
          Shadow(color: color, blurRadius: 18),
          Shadow(color: color, blurRadius: 34),
        ],
      ),
    );
  }
}

class GameBoard extends StatelessWidget {
  const GameBoard({
    required this.board,
    required this.winningCells,
    required this.lineAnimation,
    required this.onCellTap,
    super.key,
  });

  final List<Player?> board;
  final List<int> winningCells;
  final Animation<double> lineAnimation;
  final ValueChanged<int> onCellTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boardSize = math.min(constraints.maxWidth, constraints.maxHeight);

        return SizedBox.square(
          dimension: boardSize,
          child: Stack(
            children: [
              GridView.builder(
                itemCount: 9,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 13,
                  mainAxisSpacing: 13,
                ),
                itemBuilder: (_, index) {
                  return BoardCell(
                    player: board[index],
                    isWinning: winningCells.contains(index),
                    onTap: () => onCellTap(index),
                  );
                },
              ),
              if (winningCells.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: lineAnimation,
                      builder: (_, __) {
                        return CustomPaint(
                          painter: WinningLinePainter(
                            cells: winningCells,
                            progress: Curves.easeOutCubic.transform(
                              lineAnimation.value,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class BoardCell extends StatelessWidget {
  const BoardCell({
    required this.player,
    required this.isWinning,
    required this.onTap,
    super.key,
  });

  final Player? player;
  final bool isWinning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final symbolColor = player?.color ?? TickCrossColors.purpleGlow;
    final borderColor =
        isWinning ? TickCrossColors.win : TickCrossColors.purpleGlow;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: const Color(0x18ffffff),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor.withOpacity(isWinning ? 1 : .75),
            width: isWinning ? 3.5 : 1.7,
          ),
          boxShadow: [
            BoxShadow(
              color: borderColor.withOpacity(isWinning ? .95 : .45),
              blurRadius: isWinning ? 36 : 18,
            ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, animation) {
              return ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.elasticOut,
                ),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: player == null
                ? const SizedBox.shrink(key: ValueKey('empty'))
                : Text(
                    player!.symbol,
                    key: ValueKey(player),
                    style: TextStyle(
                      color: symbolColor,
                      fontSize: 58,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(color: symbolColor, blurRadius: 16),
                        Shadow(color: symbolColor, blurRadius: 34),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class WinningLinePainter extends CustomPainter {
  const WinningLinePainter({
    required this.cells,
    required this.progress,
  });

  final List<int> cells;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (cells.length != 3) return;

    Offset centerFor(int index) {
      final row = index ~/ 3;
      final column = index % 3;
      return Offset(
        (column + .5) * size.width / 3,
        (row + .5) * size.height / 3,
      );
    }

    final start = centerFor(cells.first);
    final end = centerFor(cells.last);
    final animatedEnd = Offset.lerp(start, end, progress)!;

    final glowPaint = Paint()
      ..color = TickCrossColors.win.withOpacity(.55)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    final linePaint = Paint()
      ..color = TickCrossColors.win
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;

    canvas
      ..drawLine(start, animatedEnd, glowPaint)
      ..drawLine(start, animatedEnd, linePaint);
  }

  @override
  bool shouldRepaint(covariant WinningLinePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.cells != cells;
  }
}

class NewMatchButton extends StatelessWidget {
  const NewMatchButton({
    required this.onPressed,
    super.key,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: TickCrossColors.purpleGlow,
          foregroundColor: Colors.white,
          elevation: 14,
          shadowColor: TickCrossColors.purpleGlow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text(
          'New Match',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class GameModeDialog extends StatelessWidget {
  const GameModeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        decoration: BoxDecoration(
          color: const Color(0xff12031f),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: TickCrossColors.purpleGlow, width: 2),
          boxShadow: [
            BoxShadow(
              color: TickCrossColors.purpleGlow.withOpacity(.65),
              blurRadius: 34,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose Game Mode',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(color: TickCrossColors.purpleGlow, blurRadius: 22),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _GameModeButton(
              icon: Icons.person_rounded,
              label: 'Single Player',
              color: TickCrossColors.tick,
              onPressed: () => Navigator.pop(context, GameMode.singlePlayer),
            ),
            const SizedBox(height: 12),
            _GameModeButton(
              icon: Icons.groups_rounded,
              label: 'Double Player',
              color: TickCrossColors.cross,
              onPressed: () => Navigator.pop(context, GameMode.doublePlayer),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameModeButton extends StatelessWidget {
  const _GameModeButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 14,
          shadowColor: color,
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class ResultDialog extends StatelessWidget {
  const ResultDialog({
    required this.message,
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
        decoration: BoxDecoration(
          color: const Color(0xff12031f),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: TickCrossColors.win, width: 2),
          boxShadow: [
            BoxShadow(
              color: TickCrossColors.win.withOpacity(.75),
              blurRadius: 34,
            ),
          ],
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(color: TickCrossColors.win, blurRadius: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class InterstitialAdScreen extends StatefulWidget {
  const InterstitialAdScreen({super.key});

  @override
  State<InterstitialAdScreen> createState() => _InterstitialAdScreenState();
}

class _InterstitialAdScreenState extends State<InterstitialAdScreen> {
  static const _adSeconds = 10;

  late final Timer _timer;
  int _remainingSeconds = _adSeconds;

  bool get _canClose => _remainingSeconds == 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSeconds == 0) {
        _timer.cancel();
        return;
      }

      setState(() {
        _remainingSeconds--;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _closeAd() {
    if (_canClose) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canClose,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xff070012),
                Color(0xff2b0c4c),
                Color(0xff001f30),
              ],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                const Positioned.fill(child: _AdArtwork()),
                Positioned(
                  top: 16,
                  right: 16,
                  child: _AdCloseControl(
                    remainingSeconds: _remainingSeconds,
                    onClose: _closeAd,
                  ),
                ),
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(26, 0, 26, 42),
                    child: _AdCopy(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdCloseControl extends StatelessWidget {
  const _AdCloseControl({
    required this.remainingSeconds,
    required this.onClose,
  });

  final int remainingSeconds;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final canClose = remainingSeconds == 0;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: canClose
          ? DecoratedBox(
              key: const ValueKey('close'),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.45),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(.35),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            )
          : Container(
              key: const ValueKey('countdown'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.5),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: TickCrossColors.purpleGlow),
                boxShadow: [
                  BoxShadow(
                    color: TickCrossColors.purpleGlow.withOpacity(.45),
                    blurRadius: 22,
                  ),
                ],
              ),
              child: Text(
                'Skip in $remainingSeconds',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
    );
  }
}

class _AdArtwork extends StatelessWidget {
  const _AdArtwork();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 250,
        height: 250,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [
              TickCrossColors.tick,
              TickCrossColors.purpleGlow,
              TickCrossColors.cross,
              TickCrossColors.win,
              TickCrossColors.tick,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: TickCrossColors.purpleGlow.withOpacity(.6),
              blurRadius: 70,
              spreadRadius: 10,
            ),
          ],
        ),
        child: const Center(
          child: Text(
            '\u2713 \u2715',
            style: TextStyle(
              color: Colors.white,
              fontSize: 72,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(color: TickCrossColors.win, blurRadius: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdCopy extends StatelessWidget {
  const _AdCopy();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Text(
          'Premium Break',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(color: TickCrossColors.purpleGlow, blurRadius: 24),
            ],
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Recharge before the next neon match.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class NameDialog extends StatefulWidget {
  const NameDialog({
    required this.initialName,
    super.key,
  });

  final String initialName;

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xff160729),
      title: const Text('Edit Name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 18,
        decoration: const InputDecoration(
          counterText: '',
          hintText: 'Player name',
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

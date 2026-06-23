import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const TickCrossApp());
}

class TickCrossApp extends StatelessWidget {
  const TickCrossApp({super.key});

  static const title = 'Rexwise';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: title,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: TickCrossColors.backgroundBottom,
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
  const WinResult({required this.player, required this.cells});

  final Player player;
  final List<int> cells;
}

class TickCrossColors {
  static const backgroundTop = Color(0xff18233c);
  static const backgroundMid = Color(0xff081220);
  static const backgroundBottom = Color(0xff02050b);
  static const glass = Color(0x1affffff);
  static const glassStrong = Color(0x4affffff);
  static const glassShade = Color(0x0c000000);
  static const purpleGlow = Color(0xff9f7cff);
  static const violetHot = Color(0xff7e6cff);
  static const primaryButton = Color(0xff795dff);
  static const tick = Color(0xffff5f9e);
  static const cross = Color(0xff63e6ff);
  static const win = Color(0xffffdf7a);
  static const draw = Color(0xff8dff86);
}

class GameLayoutMetrics {
  const GameLayoutMetrics({
    required this.screenWidth,
    required this.screenHeight,
  });

  final double screenWidth;
  final double screenHeight;

  bool get isCompact => screenWidth < 380 || screenHeight < 720;

  bool get isWide => screenWidth >= 700;

  double get horizontalPadding => isCompact ? 12 : (isWide ? 28 : 18);

  double get topPadding => isCompact ? 10 : 16;

  double get bottomPadding => isCompact ? 12 : 20;

  double get sectionGap => isCompact ? 12 : 22;

  double get smallGap => isCompact ? 10 : 18;

  double get maxContentWidth => isWide ? 560 : double.infinity;

  double get boardMaxSize {
    final widthCap = screenWidth - (horizontalPadding * 2);
    final heightCap = screenHeight * (isCompact ? .42 : .48);
    return math.min(widthCap, heightCap).clamp(248.0, 520.0);
  }

  double get titleSize => (screenWidth * .09).clamp(27.0, 42.0);

  double get turnSize => (screenWidth * .057).clamp(19.0, 26.0);

  double get scoreSymbolSize => (screenWidth * .058).clamp(19.0, 25.0);

  double get scoreNameSize => (screenWidth * .04).clamp(13.0, 17.0);

  double get scoreNumberSize => (screenWidth * .075).clamp(25.0, 34.0);

  double get scoreCardVerticalPadding => isCompact ? 8 : 12;

  double get scoreCardHorizontalPadding => isCompact ? 8 : 14;

  double get scoreCardHeight => isCompact ? 132 : 136;

  double get boardGap => (boardMaxSize * .035).clamp(8.0, 16.0);

  double get buttonHeight => isCompact ? 50 : 56;
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
      _currentPlayer = _currentPlayer == Player.team1
          ? Player.team2
          : Player.team1;
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
    final move =
        _findWinningMove(Player.team2) ??
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
      final playerCells = pattern
          .where((index) => _board[index] == player)
          .length;
      final emptyCells = pattern.where((index) => _board[index] == null);

      if (playerCells == 2 && emptyCells.length == 1) {
        return emptyCells.first;
      }
    }
    return null;
  }

  int? _findPreferredCornerMove() {
    const corners = [0, 2, 6, 8];
    final emptyCorners = corners
        .where((index) => _board[index] == null)
        .toList();
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
      _startingPlayer = result.player == Player.team1
          ? Player.team2
          : Player.team1;
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
      _startingPlayer = _startingPlayer == Player.team1
          ? Player.team2
          : Player.team1;
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
        pageBuilder: (_, animation, _) {
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = GameLayoutMetrics(
            screenWidth: constraints.maxWidth,
            screenHeight: constraints.maxHeight,
          );

          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.18,
                colors: [
                  TickCrossColors.backgroundTop,
                  TickCrossColors.backgroundMid,
                  TickCrossColors.backgroundBottom,
                ],
                stops: [0, .45, 1],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: metrics.maxContentWidth,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      metrics.horizontalPadding,
                      metrics.topPadding,
                      metrics.horizontalPadding,
                      metrics.bottomPadding,
                    ),
                    child: Column(
                      children: [
                        HeaderBar(
                          metrics: metrics,
                          soundEnabled: _soundEnabled,
                          onSoundPressed: _toggleSound,
                        ),
                        SizedBox(height: metrics.sectionGap),
                        Row(
                          children: [
                            Expanded(
                              child: PlayerScoreCard(
                                metrics: metrics,
                                name: _team1Name,
                                score: _team1Score,
                                color: TickCrossColors.tick,
                                symbol: Player.team1.symbol,
                                onDoubleTap: () => _editName(Player.team1),
                              ),
                            ),
                            SizedBox(width: metrics.isCompact ? 7 : 10),
                            Expanded(
                              child: PlayerScoreCard(
                                metrics: metrics,
                                name: 'Draw',
                                score: _drawScore,
                                color: TickCrossColors.draw,
                                symbol: '=',
                              ),
                            ),
                            SizedBox(width: metrics.isCompact ? 7 : 10),
                            Expanded(
                              child: PlayerScoreCard(
                                metrics: metrics,
                                name: _team2Name,
                                score: _team2Score,
                                color: TickCrossColors.cross,
                                symbol: Player.team2.symbol,
                                onDoubleTap: () => _editName(Player.team2),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: metrics.sectionGap),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: TurnLabel(
                            key: ValueKey('$_currentPlayerName-$_botThinking'),
                            metrics: metrics,
                            text: _botThinking
                                ? '$_team2Name Thinking...'
                                : '$_currentPlayerName Turn',
                            color: _currentPlayer.color,
                          ),
                        ),
                        SizedBox(height: metrics.smallGap),
                        Expanded(
                          child: Center(
                            child: GameBoard(
                              metrics: metrics,
                              board: _board,
                              winningCells: _winningCells,
                              lineAnimation: _lineController,
                              onCellTap: _onCellTap,
                            ),
                          ),
                        ),
                        SizedBox(height: metrics.smallGap),
                        NewMatchButton(
                          metrics: metrics,
                          onPressed: _onNewMatchPressed,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class HeaderBar extends StatelessWidget {
  const HeaderBar({
    required this.metrics,
    required this.soundEnabled,
    required this.onSoundPressed,
    super.key,
  });

  final GameLayoutMetrics metrics;
  final bool soundEnabled;
  final VoidCallback onSoundPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        NeonTitle(metrics: metrics),
        Align(
          alignment: Alignment.centerRight,
          child: NeonIconButton(
            icon: soundEnabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            tooltip: soundEnabled ? 'Sound on' : 'Sound off',
            onPressed: onSoundPressed,
          ),
        ),
      ],
    );
  }
}

class NeonTitle extends StatelessWidget {
  const NeonTitle({required this.metrics, super.key});

  final GameLayoutMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Text(
        'TICK CROSS',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: metrics.titleSize * .94,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: Colors.white.withValues(alpha: .96),
          shadows: const [Shadow(color: TickCrossColors.cross, blurRadius: 8)],
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
      child: GlassSurface(
        borderColor: Colors.white.withValues(alpha: .3),
        borderRadius: 28,
        shadowColor: TickCrossColors.purpleGlow.withValues(alpha: .12),
        child: SizedBox.square(
          dimension: 56,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: Colors.white.withValues(alpha: .92)),
          ),
        ),
      ),
    );
  }
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.borderColor,
    this.shadowColor,
    this.borderRadius = 18,
    this.padding,
    super.key,
  });

  final Widget child;
  final Color? borderColor;
  final Color? shadowColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: .26),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .24),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
              if (shadowColor != null)
                BoxShadow(
                  color: shadowColor!,
                  blurRadius: 30,
                  spreadRadius: -4,
                ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: .2),
                        Colors.white.withValues(alpha: .07),
                        Colors.white.withValues(alpha: .025),
                        Colors.black.withValues(alpha: .08),
                      ],
                      stops: const [0, .35, .68, 1],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-.78, -.86),
                      radius: 1.35,
                      colors: [
                        Colors.white.withValues(alpha: .3),
                        Colors.white.withValues(alpha: .06),
                        Colors.transparent,
                      ],
                      stops: const [0, .38, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 1,
                right: 1,
                top: 1,
                height: 1.4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: .58),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 1,
                top: 10,
                bottom: 12,
                width: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: .28),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(padding: padding ?? EdgeInsets.zero, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerScoreCard extends StatelessWidget {
  const PlayerScoreCard({
    required this.metrics,
    required this.name,
    required this.score,
    required this.color,
    required this.symbol,
    this.onDoubleTap,
    super.key,
  });

  final GameLayoutMetrics metrics;
  final String name;
  final int score;
  final Color color;
  final String symbol;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: SizedBox(
        width: double.infinity,
        height: metrics.scoreCardHeight,
        child: GlassSurface(
          borderColor: color.withValues(alpha: .42),
          borderRadius: 18,
          shadowColor: color.withValues(alpha: .12),
          padding: EdgeInsets.symmetric(
            horizontal: metrics.scoreCardHorizontalPadding,
            vertical: metrics.scoreCardVerticalPadding,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    symbol,
                    style: TextStyle(
                      color: color,
                      fontSize: metrics.scoreSymbolSize,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(color: color, blurRadius: 6)],
                    ),
                  ),
                  SizedBox(height: metrics.isCompact ? 2 : 4),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color.withValues(alpha: .92),
                      fontSize: metrics.scoreNameSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: metrics.isCompact ? 3 : 6),
                  Text(
                    '$score',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .96),
                      fontSize: metrics.scoreNumberSize,
                      fontWeight: FontWeight.w800,
                    ),
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

class TurnLabel extends StatelessWidget {
  const TurnLabel({
    required this.metrics,
    required this.text,
    required this.color,
    super.key,
  });

  final GameLayoutMetrics metrics;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderColor: color.withValues(alpha: .25),
      borderRadius: 24,
      shadowColor: color.withValues(alpha: .08),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: .94),
          fontSize: metrics.turnSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class GameBoard extends StatelessWidget {
  const GameBoard({
    required this.metrics,
    required this.board,
    required this.winningCells,
    required this.lineAnimation,
    required this.onCellTap,
    super.key,
  });

  final GameLayoutMetrics metrics;
  final List<Player?> board;
  final List<int> winningCells;
  final Animation<double> lineAnimation;
  final ValueChanged<int> onCellTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableSize = math.min(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final boardSize = math.min(availableSize, metrics.boardMaxSize);

        return SizedBox.square(
          dimension: boardSize,
          child: Stack(
            children: [
              GridView.builder(
                itemCount: 9,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: metrics.boardGap,
                  mainAxisSpacing: metrics.boardGap,
                ),
                itemBuilder: (_, index) {
                  return BoardCell(
                    boardSize: boardSize,
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
                      builder: (_, _) {
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
    required this.boardSize,
    required this.player,
    required this.isWinning,
    required this.onTap,
    super.key,
  });

  final double boardSize;
  final Player? player;
  final bool isWinning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final symbolColor = player?.color ?? TickCrossColors.purpleGlow;
    final borderColor = isWinning ? TickCrossColors.win : symbolColor;
    final isEmpty = player == null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        scale: isWinning ? .98 : 1,
        child: GlassSurface(
          borderColor: borderColor.withValues(
            alpha: isWinning ? .82 : (isEmpty ? .2 : .54),
          ),
          borderRadius: 20,
          shadowColor: borderColor.withValues(
            alpha: isWinning ? .22 : (isEmpty ? .04 : .12),
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
                  : BoardMark(
                      key: ValueKey(player),
                      player: player!,
                      color: symbolColor,
                      size: (boardSize * .24).clamp(66.0, 104.0),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class BoardMark extends StatelessWidget {
  const BoardMark({
    required this.player,
    required this.color,
    required this.size,
    super.key,
  });

  final Player player;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: BoardMarkPainter(player: player, color: color),
      ),
    );
  }
}

class BoardMarkPainter extends CustomPainter {
  const BoardMarkPainter({required this.player, required this.color});

  final Player player;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = player == Player.team1 ? _tickPath(size) : _crossPath(size);

    final glowPaint = Paint()
      ..color = color.withValues(alpha: .22)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * .13
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: .88),
          color,
          color.withValues(alpha: .78),
        ],
        stops: const [0, .42, 1],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * .105;

    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: .34)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.width * .035;

    canvas
      ..drawPath(path, glowPaint)
      ..drawPath(path, bodyPaint)
      ..save()
      ..translate(-size.width * .018, -size.height * .028)
      ..drawPath(path, highlightPaint)
      ..restore();
  }

  Path _tickPath(Size size) {
    return Path()
      ..moveTo(size.width * .2, size.height * .56)
      ..cubicTo(
        size.width * .3,
        size.height * .66,
        size.width * .34,
        size.height * .74,
        size.width * .42,
        size.height * .8,
      )
      ..cubicTo(
        size.width * .53,
        size.height * .52,
        size.width * .66,
        size.height * .3,
        size.width * .82,
        size.height * .16,
      );
  }

  Path _crossPath(Size size) {
    return Path()
      ..moveTo(size.width * .22, size.height * .22)
      ..lineTo(size.width * .78, size.height * .78)
      ..moveTo(size.width * .78, size.height * .22)
      ..lineTo(size.width * .22, size.height * .78);
  }

  @override
  bool shouldRepaint(covariant BoardMarkPainter oldDelegate) {
    return oldDelegate.player != player || oldDelegate.color != color;
  }
}

class WinningLinePainter extends CustomPainter {
  const WinningLinePainter({required this.cells, required this.progress});

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
      ..color = TickCrossColors.win.withValues(alpha: .38)
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);

    final linePaint = Paint()
      ..color = TickCrossColors.win
      ..strokeWidth = 6
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
    required this.metrics,
    required this.onPressed,
    super.key,
  });

  final GameLayoutMetrics metrics;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: metrics.buttonHeight,
      child: GestureDetector(
        onTap: onPressed,
        child: GlassSurface(
          borderColor: TickCrossColors.primaryButton.withValues(alpha: .58),
          borderRadius: 18,
          shadowColor: TickCrossColors.primaryButton.withValues(alpha: .16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.refresh_rounded,
                color: Colors.white.withValues(alpha: .88),
                size: metrics.isCompact ? 19 : 21,
              ),
              const SizedBox(width: 8),
              Text(
                'New Match',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .95),
                  fontSize: metrics.isCompact ? 16 : 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
    final dialogWidth = MediaQuery.sizeOf(context).width.clamp(280.0, 420.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogWidth,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        decoration: BoxDecoration(
          color: TickCrossColors.backgroundMid,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: TickCrossColors.purpleGlow, width: 2),
          boxShadow: [
            BoxShadow(
              color: TickCrossColors.purpleGlow.withValues(alpha: .34),
              blurRadius: 28,
            ),
            BoxShadow(
              color: TickCrossColors.cross.withValues(alpha: .12),
              blurRadius: 44,
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
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class ResultDialog extends StatelessWidget {
  const ResultDialog({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final dialogWidth = MediaQuery.sizeOf(context).width.clamp(280.0, 420.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogWidth,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
        decoration: BoxDecoration(
          color: TickCrossColors.backgroundMid,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: TickCrossColors.win, width: 2),
          boxShadow: [
            BoxShadow(
              color: TickCrossColors.win.withValues(alpha: .38),
              blurRadius: 30,
            ),
            BoxShadow(
              color: TickCrossColors.tick.withValues(alpha: .14),
              blurRadius: 50,
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
            shadows: [Shadow(color: TickCrossColors.win, blurRadius: 22)],
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
                TickCrossColors.backgroundBottom,
                TickCrossColors.backgroundTop,
                Color(0xff003650),
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
                color: Colors.black.withValues(alpha: .45),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: .35),
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
                color: Colors.black.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: TickCrossColors.purpleGlow),
                boxShadow: [
                  BoxShadow(
                    color: TickCrossColors.purpleGlow.withValues(alpha: .45),
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
    final size = MediaQuery.sizeOf(context);
    final artSize = math
        .min(size.width * .64, size.height * .34)
        .clamp(190.0, 330.0);

    return Center(
      child: Container(
        width: artSize,
        height: artSize,
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
              color: TickCrossColors.purpleGlow.withValues(alpha: .32),
              blurRadius: 54,
              spreadRadius: 4,
            ),
            BoxShadow(
              color: TickCrossColors.cross.withValues(alpha: .2),
              blurRadius: 78,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Center(
          child: Text(
            '\u2713 \u2715',
            style: TextStyle(
              color: Colors.white,
              fontSize: artSize * .28,
              fontWeight: FontWeight.w900,
              shadows: const [
                Shadow(color: TickCrossColors.win, blurRadius: 28),
                Shadow(color: TickCrossColors.cross, blurRadius: 48),
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
    final titleSize =
        MediaQuery.sizeOf(context).width.clamp(320.0, 560.0) * .07;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Premium Break',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: titleSize.clamp(28.0, 38.0),
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(color: TickCrossColors.purpleGlow, blurRadius: 24),
              Shadow(color: TickCrossColors.cross, blurRadius: 38),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
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
  const NameDialog({required this.initialName, super.key});

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
      backgroundColor: TickCrossColors.backgroundMid,
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

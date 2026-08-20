import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const WormVsSaltGame());
}

class WormVsSaltGame extends StatelessWidget {
  const WormVsSaltGame({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Worm vs Salt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A0A00),
      ),
      home: const GameScreen(),
    );
  }
}

// ───────────────────── Entities ─────────────────────

class Salt {
  Offset position;
  Offset velocity;
  final double radius;
  Salt({required this.position, required this.velocity, required this.radius});
}

class HealthItem {
  Offset position;
  final double radius;
  double lifeTime = 0;
  HealthItem({required this.position, required this.radius});
}

class FloatingText {
  String text;
  Offset position;
  double opacity;
  double age;
  Color color;
  FloatingText({
    required this.text,
    required this.position,
    this.opacity = 1.0,
    this.age = 0,
    this.color = Colors.redAccent,
  });
}

// ───────────────────── Game Screen ─────────────────────

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  late Ticker _ticker;
  final Random _random = Random();
  Size _screenSize = Size.zero;

  bool _isPlaying = false;
  bool _isGameOver = false;
  bool _showReward = false;

  // Stats
  double _health = 100.0;
  int _score = 0;

  // Worm
  List<Offset> _wormBody = [];
  final double _wormRadius = 14.0;
  final double _segmentSpacing = 17.0;
  final int _initialLength = 4;  // Worm starts short
  double _wormSpeed = 200.0;
  Offset? _dragTarget;

  // Enemies & Items
  List<Salt> _salts = [];
  List<HealthItem> _items = [];
  List<FloatingText> _floatingTexts = [];

  // Timing
  Duration _lastTick = Duration.zero;
  double _spawnTimer = 0;
  double _spawnRate = 1.5;
  double _itemSpawnTimer = 0;
  double _scoreTimer = 0;

  // Hit messages
  final List<String> _hitMessages = [
    'IT HURTS! 😱',
    'OUCH! 🤕',
    'NOT THE SALT! 😭',
    'AAAAHHH! 🔥',
    'THAT STINGS! 💀',
    'OH NO! 😖',
    'STOP IT! 😤',
    'THE BURN! 🌶️',
    'WHY?! 😩',
    'I\'M MELTING! 😰',
  ];

  // Reward animation controller
  late AnimationController _showerController;
  late Animation<double> _dropAnimation;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);

    _showerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
    _dropAnimation = Tween<double>(begin: 0, end: 1).animate(_showerController);
  }

  void _startGame() {
    setState(() {
      _isPlaying = true;
      _isGameOver = false;
      _showReward = false;
      _health = 100.0;
      _score = 0;
      _wormSpeed = 200.0;
      final cx = _screenSize.width / 2;
      final cy = _screenSize.height / 2;
      _wormBody = List.generate(
          _initialLength, (i) => Offset(cx - i * _segmentSpacing, cy));
      _dragTarget = Offset(cx, cy);
      _salts.clear();
      _items.clear();
      _floatingTexts.clear();
      _lastTick = Duration.zero;
      _spawnRate = 1.5;
    });
    _ticker.start();
  }

  void _gameOver() {
    _ticker.stop();
    setState(() {
      _isPlaying = false;
      _isGameOver = true;
    });
  }

  void _triggerReward() {
    _ticker.stop();
    setState(() {
      _isPlaying = false;
      _showReward = true;
    });
  }

  void _addFloatingText(Offset pos, String msg, Color color) {
    _floatingTexts.add(FloatingText(
      text: msg,
      position: pos + Offset(_random.nextDouble() * 40 - 20, -30),
      color: color,
    ));
  }

  void _tick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;

    setState(() {
      // Score increases over time
      _scoreTimer += dt;
      if (_scoreTimer >= 1.0) {
        _scoreTimer = 0;
        _score += 1;
        if (_score >= 100) {
          _triggerReward();
          return;
        }
      }

      // Difficulty every 15s
      final diffLevel = elapsed.inSeconds ~/ 15;
      _spawnRate = 1.5 + diffLevel * 0.8;

      // Move worm head toward drag target
      if (_dragTarget != null && _wormBody.isNotEmpty) {
        final head = _wormBody[0];
        final diff = _dragTarget! - head;
        final dist = diff.distance;
        if (dist > 5) {
          final dir = diff / dist;
          _wormBody[0] = head + dir * (_wormSpeed * dt);
        }
        // Clamp to screen
        _wormBody[0] = Offset(
          _wormBody[0].dx.clamp(_wormRadius, _screenSize.width - _wormRadius),
          _wormBody[0].dy.clamp(_wormRadius, _screenSize.height - _wormRadius),
        );
      }

      // Update body segments (inverse kinematics)
      for (int i = 1; i < _wormBody.length; i++) {
        final target = _wormBody[i - 1];
        final current = _wormBody[i];
        final dist = (target - current).distance;
        if (dist > _segmentSpacing) {
          final dir = (target - current) / dist;
          _wormBody[i] = target - dir * _segmentSpacing;
        }
      }

      // Spawn salt
      _spawnTimer += dt;
      if (_spawnTimer > 1.0 / _spawnRate) {
        _spawnTimer = 0;
        _spawnSalt();
      }

      // Spawn item
      _itemSpawnTimer += dt;
      if (_itemSpawnTimer > 7.0) {
        _itemSpawnTimer = 0;
        _spawnItem();
      }

      // Update salts
      for (int i = _salts.length - 1; i >= 0; i--) {
        final s = _salts[i];
        s.position += s.velocity * dt;

        bool hit = false;
        for (final seg in _wormBody) {
          if ((s.position - seg).distance < _wormRadius + s.radius - 2) {
            hit = true;
            break;
          }
        }

        if (hit) {
          _salts.removeAt(i);
          _health -= 15.0;
          HapticFeedback.heavyImpact();

          // Floating hurt text
          final msg = _hitMessages[_random.nextInt(_hitMessages.length)];
          _addFloatingText(_wormBody[0], msg, Colors.redAccent);

          if (_health <= 0) {
            _health = 0;
            _gameOver();
          }
          continue;
        }

        if (s.position.dx < -150 ||
            s.position.dx > _screenSize.width + 150 ||
            s.position.dy < -150 ||
            s.position.dy > _screenSize.height + 150) {
          _salts.removeAt(i);
        }
      }

      // Update items
      for (int i = _items.length - 1; i >= 0; i--) {
        final item = _items[i];
        item.lifeTime += dt;

        if ((_wormBody[0] - item.position).distance <
            _wormRadius + item.radius) {
          _items.removeAt(i);
          _health = (_health + 25).clamp(0, 100);
          // Speed boost!
          _wormSpeed += 15;
          _score += 5;
          // Grow worm — add 4 segments at the tail
          final tail = _wormBody.last;
          for (int g = 1; g <= 4; g++) {
            _wormBody.add(tail);
          }
          _addFloatingText(
              _wormBody[0], '🐛 WORM GROWS! +5 pts', Colors.greenAccent);
          HapticFeedback.lightImpact();
          continue;
        }

        if (item.lifeTime > 8.0) _items.removeAt(i);
      }

      // Update floating texts
      for (int i = _floatingTexts.length - 1; i >= 0; i--) {
        final ft = _floatingTexts[i];
        ft.age += dt;
        ft.opacity = (1.0 - ft.age / 1.8).clamp(0.0, 1.0);
        ft.position = ft.position.translate(0, -55 * dt);
        if (ft.age > 1.8) _floatingTexts.removeAt(i);
      }
    });
  }

  void _spawnSalt() {
    final side = _random.nextDouble();
    Offset spawnPos;
    if (side < 0.25) {
      spawnPos = Offset(-20, _random.nextDouble() * _screenSize.height);
    } else if (side < 0.5) {
      spawnPos =
          Offset(_screenSize.width + 20, _random.nextDouble() * _screenSize.height);
    } else if (side < 0.75) {
      spawnPos = Offset(_random.nextDouble() * _screenSize.width, -20);
    } else {
      spawnPos = Offset(
          _random.nextDouble() * _screenSize.width, _screenSize.height + 20);
    }

    final dir = (_wormBody[0] - spawnPos);
    final dist = dir.distance;
    final normDir = dist > 0 ? dir / dist : const Offset(1, 0);
    final speed = 150.0 + _spawnRate * 15;

    _salts.add(Salt(
        position: spawnPos, velocity: normDir * speed, radius: 8.0));
  }

  void _spawnItem() {
    _items.add(HealthItem(
      position: Offset(
        50 + _random.nextDouble() * (_screenSize.width - 100),
        100 + _random.nextDouble() * (_screenSize.height - 200),
      ),
      radius: 16.0,
    ));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _showerController.dispose();
    super.dispose();
  }

  // ─────────────── Build ───────────────

  @override
  Widget build(BuildContext context) {
    _screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // Background grid
          CustomPaint(
            size: _screenSize,
            painter: _DirtPainter(),
          ),

          // ── Reward Screen ──
          if (_showReward) _buildRewardScreen(),

          // ── Game Over Screen ──
          if (!_isPlaying && !_showReward) _buildMenuScreen(),

          // ── Gameplay ──
          if (_isPlaying)
            GestureDetector(
              onPanUpdate: (d) => setState(() => _dragTarget = d.localPosition),
              onPanStart: (d) => setState(() => _dragTarget = d.localPosition),
              behavior: HitTestBehavior.opaque,
              child: SizedBox.expand(
                child: Stack(
                  children: [
                    // Health items
                    ..._items.map((item) => Positioned(
                          left: item.position.dx - item.radius,
                          top: item.position.dy - item.radius,
                          child: _HealthItemWidget(radius: item.radius),
                        )),

                    // Salts
                    ..._salts.map((s) => Positioned(
                          left: s.position.dx - s.radius,
                          top: s.position.dy - s.radius,
                          child: _SaltWidget(radius: s.radius),
                        )),

                    // Worm segments (tail → head)
                    for (int i = _wormBody.length - 1; i >= 0; i--)
                      Positioned(
                        left: _wormBody[i].dx - _wormRadius,
                        top: _wormBody[i].dy - _wormRadius,
                        child: _WormSegment(
                          radius: _wormRadius,
                          isHead: i == 0,
                          segmentIndex: i,
                          totalSegments: _wormBody.length,
                        ),
                      ),

                    // Floating texts
                    ..._floatingTexts.map((ft) => Positioned(
                          left: ft.position.dx,
                          top: ft.position.dy,
                          child: Opacity(
                            opacity: ft.opacity,
                            child: Text(
                              ft.text,
                              style: TextStyle(
                                color: ft.color,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                shadows: const [
                                  Shadow(
                                      color: Colors.black,
                                      blurRadius: 6,
                                      offset: Offset(1, 1)),
                                ],
                              ),
                            ),
                          ),
                        )),

                    // HUD
                    _buildHUD(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHUD() {
    return Positioned(
      top: 40,
      left: 16,
      right: 16,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _HudBadge(
                  icon: Icons.favorite, label: '${_health.toInt()}%',
                  color: Colors.pinkAccent),
              _HudBadge(
                  icon: Icons.star, label: '$_score / 100',
                  color: Colors.amberAccent),
              _HudBadge(
                  icon: Icons.speed,
                  label: '${_wormSpeed.toInt()} px/s',
                  color: Colors.cyanAccent),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: _health / 100.0,
              backgroundColor: Colors.red[900],
              valueColor: AlwaysStoppedAnimation(
                  _health > 50 ? Colors.greenAccent : Colors.orangeAccent),
              minHeight: 14,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: _score / 100.0,
              backgroundColor: Colors.grey[800],
              valueColor:
                  const AlwaysStoppedAnimation(Colors.amberAccent),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuScreen() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.brown[400]!, width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.brown.withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 5),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isGameOver ? '💀 GAME OVER' : '🐛 WORM vs SALT 🧂',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: _isGameOver ? Colors.redAccent : Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            if (_isGameOver) ...[
              Text('Final Score: $_score',
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.amberAccent)),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📖 HOW TO PLAY',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.yellowAccent)),
                  SizedBox(height: 8),
                  Text(
                    '👆 DRAG your finger to guide the worm.',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  SizedBox(height: 5),
                  Text(
                    '🧂 AVOID the white salt particles — they constantly chase you and target ANY part of your body. The longer your worm, the harder to dodge!',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  SizedBox(height: 5),
                  Text(
                    '💚 COLLECT green health kits to restore HP AND get a speed boost — use it to outrun the salt!',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 13),
                  ),
                  SizedBox(height: 5),
                  Text(
                    '⭐ Score 1 point per second. Collect kits for +5 bonus. Reach 100 to unlock a SECRET reward! 🎉',
                    style: TextStyle(color: Colors.amberAccent, fontSize: 13),
                  ),
                  SizedBox(height: 5),
                  Text(
                    '⚡ Every 15 seconds the salts multiply and move FASTER. Stay sharp!',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 44, vertical: 14),
                backgroundColor: Colors.green[700],
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                elevation: 8,
              ),
              onPressed: _startGame,
              child: Text(
                _isGameOver ? '🔄 TRY AGAIN' : '🎮 START GAME',
                style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardScreen() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '🎊 SCORE 100! 🎊',
              style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.amberAccent),
            ),
            const SizedBox(height: 8),
            const Text(
              'The worm earned a shower! 🚿',
              style: TextStyle(fontSize: 20, color: Colors.white70),
            ),
            const SizedBox(height: 30),
            // Shower scene
            AnimatedBuilder(
              animation: _dropAnimation,
              builder: (context, _) {
                return CustomPaint(
                  size: const Size(260, 300),
                  painter: _ShowerPainter(_dropAnimation.value),
                );
              },
            ),
            const SizedBox(height: 30),
            const Text(
              '"No more salt... finally!" 😭✨',
              style: TextStyle(
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  color: Colors.cyanAccent),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              onPressed: _startGame,
              child: const Text('🎮 PLAY AGAIN',
                  style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────── Painters & Widgets ───────────────

class _DirtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF1A0A00);
    canvas.drawRect(Offset.zero & size, paint);
    // Subtle dirt texture dots
    final dotPaint = Paint()..color = const Color(0xFF2A1500);
    final r = Random(42);
    for (int i = 0; i < 120; i++) {
      canvas.drawCircle(
        Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
        r.nextDouble() * 3 + 1,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

class _WormSegment extends StatelessWidget {
  final double radius;
  final bool isHead;
  final int segmentIndex;
  final int totalSegments;
  const _WormSegment(
      {required this.radius,
      required this.isHead,
      required this.segmentIndex,
      required this.totalSegments});

  @override
  Widget build(BuildContext context) {
    final t = segmentIndex / totalSegments;
    final color =
        Color.lerp(const Color(0xFFE91E8C), const Color(0xFFAD1457), t)!;

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
            color: isHead ? Colors.white54 : Colors.pink[900]!,
            width: isHead ? 2.5 : 1),
        boxShadow: isHead
            ? [
                BoxShadow(
                    color: Colors.pinkAccent.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2)
              ]
            : [],
      ),
      child: isHead
          ? const Center(
              child: Text('🐛', style: TextStyle(fontSize: 16)),
            )
          : null,
    );
  }
}

class _SaltWidget extends StatelessWidget {
  final double radius;
  const _SaltWidget({required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: Colors.white.withOpacity(0.6),
              blurRadius: 6,
              spreadRadius: 2),
        ],
      ),
      child: const Center(
        child: Text('🧂', style: TextStyle(fontSize: 8)),
      ),
    );
  }
}

class _HealthItemWidget extends StatelessWidget {
  final double radius;
  const _HealthItemWidget({required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: Colors.green[800],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.greenAccent, width: 2),
        boxShadow: [
          BoxShadow(
              color: Colors.greenAccent.withOpacity(0.5),
              blurRadius: 12,
              spreadRadius: 3),
        ],
      ),
      child: const Center(
        child: Text('💊', style: TextStyle(fontSize: 14)),
      ),
    );
  }
}

class _HudBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _HudBadge(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ─────────────── Shower Reward Painter ───────────────

class _ShowerPainter extends CustomPainter {
  final double t;
  _ShowerPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final Random rng = Random(42);

    // Background circle
    canvas.drawCircle(
      Offset(cx, size.height * 0.55),
      100,
      Paint()
        ..color = const Color(0xFF1A3A6B)
        ..style = PaintingStyle.fill,
    );

    // Shower head
    final showerPaint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(cx - 30, 20), Offset(cx + 30, 20), showerPaint);
    canvas.drawLine(Offset(cx, 20), Offset(cx, 50), showerPaint);

    // Shower head nozzle plate
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset(cx, 55), width: 60, height: 12),
      Paint()..color = Colors.grey[300]!,
    );

    // Water drops
    final dropPaint = Paint()
      ..color = Colors.lightBlueAccent.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 14; i++) {
      final offsetX = (rng.nextDouble() - 0.5) * 55;
      final phase = rng.nextDouble();
      final drop = ((t + phase) % 1.0);
      final dy = 65 + drop * 150;
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx + offsetX, dy), width: 5, height: 9),
        dropPaint,
      );
    }

    // Worm body (wiggling)
    _drawWorm(canvas, Offset(cx, size.height * 0.65), t);

    // Steam/bubbles
    final bubblePaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 6; i++) {
      final bx = cx + (rng.nextDouble() - 0.5) * 80;
      final by =
          size.height * 0.55 - 30 - ((t * 40 + i * 18) % 60);
      canvas.drawCircle(Offset(bx, by), rng.nextDouble() * 5 + 3, bubblePaint);
    }

    // Happy face text
    const textStyle = TextStyle(fontSize: 30);
    final tp = TextPainter(
      text: const TextSpan(text: '😄', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - 15, size.height * 0.49));
  }

  void _drawWorm(Canvas canvas, Offset center, double t) {
    final segments = 10;
    final paint = Paint()
      ..color = const Color(0xFFE91E8C)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < segments; i++) {
      final angle = (i / segments) * pi + sin(t * pi * 2 + i * 0.5) * 0.4;
      final x = center.dx + cos(angle) * i * 8;
      final y = center.dy + sin(angle) * i * 4 + sin(t * 4 + i) * 5;
      canvas.drawCircle(Offset(x, y), 10.0 - i * 0.5, paint);
    }
  }

  @override
  bool shouldRepaint(_ShowerPainter old) => old.t != t;
}

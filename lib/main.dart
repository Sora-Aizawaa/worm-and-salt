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
        scaffoldBackgroundColor: Colors.brown[900], // Dark dirt color
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

enum Direction { up, down, left, right }

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  final Random _random = Random();

  bool _isPlaying = false;
  bool _isGameOver = false;
  Size _screenSize = Size.zero;

  // Game state
  double _health = 100.0;
  
  // Worm State (Multi-segment)
  List<Offset> _wormBody = [];
  final double _wormRadius = 15.0;
  final double _segmentSpacing = 18.0;
  final int _initialLength = 12;
  Direction _currentDirection = Direction.right;
  final double _wormSpeed = 220.0; // pixels per second
  
  List<Salt> _salts = [];
  List<HealthItem> _items = [];

  // Difficulty & Timing
  Duration _lastTick = Duration.zero;
  Duration _timeElapsed = Duration.zero;
  
  double _spawnTimer = 0;
  double _spawnRate = 1.5; 
  double _itemSpawnTimer = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  void _startGame() {
    setState(() {
      _isPlaying = true;
      _isGameOver = false;
      _health = 100.0;
      
      // Initialize worm body in the center
      double startX = _screenSize.width / 2;
      double startY = _screenSize.height / 2;
      _wormBody = List.generate(
        _initialLength, 
        (index) => Offset(startX - (index * _segmentSpacing), startY)
      );
      _currentDirection = Direction.right;

      _salts.clear();
      _items.clear();
      _lastTick = Duration.zero;
      _timeElapsed = Duration.zero;
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

  void _setDirection(Direction newDir) {
    // Prevent 180-degree instant turns to avoid head going into body
    if (_currentDirection == Direction.up && newDir == Direction.down) return;
    if (_currentDirection == Direction.down && newDir == Direction.up) return;
    if (_currentDirection == Direction.left && newDir == Direction.right) return;
    if (_currentDirection == Direction.right && newDir == Direction.left) return;
    
    _currentDirection = newDir;
  }

  void _tick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    double dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    _timeElapsed += (elapsed - _lastTick);

    setState(() {
      // 1. Move Worm Head
      Offset moveDelta;
      switch(_currentDirection) {
        case Direction.up: moveDelta = Offset(0, -_wormSpeed * dt); break;
        case Direction.down: moveDelta = Offset(0, _wormSpeed * dt); break;
        case Direction.left: moveDelta = Offset(-_wormSpeed * dt, 0); break;
        case Direction.right: moveDelta = Offset(_wormSpeed * dt, 0); break;
      }
      _wormBody[0] += moveDelta;

      // Clamp head to screen boundaries
      _wormBody[0] = Offset(
        _wormBody[0].dx.clamp(_wormRadius, _screenSize.width - _wormRadius),
        _wormBody[0].dy.clamp(_wormRadius, _screenSize.height - _wormRadius)
      );

      // 2. Update Worm Body using Inverse Kinematics
      for (int i = 1; i < _wormBody.length; i++) {
        Offset target = _wormBody[i - 1];
        Offset current = _wormBody[i];
        double dist = (target - current).distance;
        if (dist > _segmentSpacing) {
          Offset dir = (target - current) / dist;
          _wormBody[i] = target - dir * _segmentSpacing;
        }
      }

      // 3. Difficulty scaling (every 15 seconds)
      int difficultyLevel = _lastTick.inSeconds ~/ 15;
      _spawnRate = 1.5 + (difficultyLevel * 0.8);

      // 4. Spawn Salts
      _spawnTimer += dt;
      if (_spawnTimer > (1.0 / _spawnRate)) {
        _spawnTimer = 0;
        _spawnSalt();
      }

      // 5. Spawn Health Items
      _itemSpawnTimer += dt;
      if (_itemSpawnTimer > 8.0) {
        _itemSpawnTimer = 0;
        _spawnItem();
      }

      // 6. Update Salts and Check Collisions
      for (int i = _salts.length - 1; i >= 0; i--) {
        Salt s = _salts[i];
        s.position += s.velocity * dt;

        // Check collision with ANY part of the worm body
        bool hitWorm = false;
        for (Offset segment in _wormBody) {
          if ((s.position - segment).distance < _wormRadius + s.radius - 2) {
            hitWorm = true;
            break;
          }
        }

        if (hitWorm) {
          // Vibrate on mobile as hit feedback; no-op on web
          HapticFeedback.heavyImpact();
          _salts.removeAt(i);
          _health -= 15.0; // Damage
          if (_health <= 0) {
            _health = 0;
            _gameOver();
          }
          continue;
        }

        // Remove salt if out of bounds
        if (s.position.dx < -200 || s.position.dx > _screenSize.width + 200 || 
            s.position.dy < -200 || s.position.dy > _screenSize.height + 200) {
          _salts.removeAt(i);
        }
      }

      // 7. Update Items and Check Collisions (Head only for items)
      for (int i = _items.length - 1; i >= 0; i--) {
        HealthItem item = _items[i];
        item.lifeTime += dt;

        if ((item.position - _wormBody[0]).distance < _wormRadius + item.radius) {
          _items.removeAt(i);
          _health += 25.0;
          if (_health > 100) _health = 100;
          continue;
        }

        if (item.lifeTime > 8.0) { 
          _items.removeAt(i);
        }
      }
    });
  }

  void _spawnSalt() {
    double side = _random.nextDouble();
    Offset spawnPos;
    
    if (side < 0.25) {
      spawnPos = Offset(-20, _random.nextDouble() * _screenSize.height);
    } else if (side < 0.5) {
      spawnPos = Offset(_screenSize.width + 20, _random.nextDouble() * _screenSize.height);
    } else if (side < 0.75) {
      spawnPos = Offset(_random.nextDouble() * _screenSize.width, -20);
    } else {
      spawnPos = Offset(_random.nextDouble() * _screenSize.width, _screenSize.height + 20);
    }

    // Aim at the worm's HEAD
    Offset direction = _wormBody[0] - spawnPos;
    double dist = direction.distance;
    if (dist != 0) {
      direction = direction / dist;
    }
    
    double speed = 150.0 + (_spawnRate * 15);
    
    _salts.add(Salt(
      position: spawnPos,
      velocity: direction * speed,
      radius: 8.0,
    ));
  }

  void _spawnItem() {
    _items.add(HealthItem(
      position: Offset(
        50 + _random.nextDouble() * (_screenSize.width - 100), 
        100 + _random.nextDouble() * (_screenSize.height - 300) // Keep away from D-pad
      ),
      radius: 15.0,
    ));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Widget _buildDPadButton(IconData icon, Direction dir) {
    return GestureDetector(
      onTapDown: (_) => _setDirection(dir),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white54, width: 2),
        ),
        child: Icon(icon, color: Colors.white, size: 40),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _screenSize = MediaQuery.of(context).size;
    
    return Scaffold(
      body: Stack(
        children: [
          // Game Area
          if (_isPlaying) ...[
            // Draw Health Items
            ..._items.map((item) => Positioned(
              left: item.position.dx - item.radius,
              top: item.position.dy - item.radius,
              child: Icon(Icons.local_hospital, color: Colors.greenAccent, size: item.radius * 2),
            )),

            // Draw Salts
            ..._salts.map((s) => Positioned(
              left: s.position.dx - s.radius,
              top: s.position.dy - s.radius,
              child: Container(
                width: s.radius * 2,
                height: s.radius * 2,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.white.withOpacity(0.5), blurRadius: 4, spreadRadius: 2)
                  ]
                ),
              ),
            )),

            // Draw Worm Body (from tail to head so head is on top)
            for (int i = _wormBody.length - 1; i >= 0; i--)
              Positioned(
                left: _wormBody[i].dx - _wormRadius,
                top: _wormBody[i].dy - _wormRadius,
                child: Container(
                  width: _wormRadius * 2,
                  height: _wormRadius * 2,
                  decoration: BoxDecoration(
                    color: i == 0 ? Colors.pink[300] : Colors.pink[400], // Head is lighter
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.pink[800]!, width: i == 0 ? 3 : 1),
                  ),
                  child: i == 0 
                    ? const Center(child: Icon(Icons.sentiment_neutral, size: 20, color: Colors.black45))
                    : null,
                ),
              ),

            // Health Bar & Info
            Positioned(
              top: 40,
              left: 20,
              right: 20,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('HEALTH: ${_health.toInt()}%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('TIME: ${_lastTick.inSeconds}s', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _health / 100.0,
                      backgroundColor: Colors.red[900],
                      color: Colors.greenAccent,
                      minHeight: 18,
                    ),
                  ),
                ],
              ),
            ),

            // D-Pad Controls
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDPadButton(Icons.keyboard_arrow_up, Direction.up),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildDPadButton(Icons.keyboard_arrow_left, Direction.left),
                      const SizedBox(width: 80),
                      _buildDPadButton(Icons.keyboard_arrow_right, Direction.right),
                    ],
                  ),
                  _buildDPadButton(Icons.keyboard_arrow_down, Direction.down),
                ],
              ),
            )
          ],
          
          // Main Menu / Game Over
          if (!_isPlaying)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24, width: 2)
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isGameOver ? 'GAME OVER' : 'WORM vs SALT',
                      style: TextStyle(
                        fontSize: 32, 
                        fontWeight: FontWeight.bold,
                        color: _isGameOver ? Colors.redAccent : Colors.white
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_isGameOver) ...[
                      const Text('You survived for:', style: TextStyle(fontSize: 16, color: Colors.white70)),
                      Text('${_lastTick.inSeconds} seconds', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                      const SizedBox(height: 20),
                    ],
                    
                    // Detailed Instructions
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('HOW TO PLAY:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.yellowAccent)),
                          SizedBox(height: 8),
                          Text('🐛 You are a worm. You will constantly move forward.', style: TextStyle(fontSize: 14, color: Colors.white)),
                          SizedBox(height: 4),
                          Text('🎮 Use the D-PAD buttons to change your direction.', style: TextStyle(fontSize: 14, color: Colors.white)),
                          SizedBox(height: 4),
                          Text('🧂 AVOID THE SALT! White salt particles will constantly shoot at you. If they hit ANY part of your long body, you lose health.', style: TextStyle(fontSize: 14, color: Colors.white)),
                          SizedBox(height: 4),
                          Text('💚 Collect Health Kits (green crosses) to restore health.', style: TextStyle(fontSize: 14, color: Colors.white)),
                          SizedBox(height: 4),
                          Text('⏱️ The game gets harder and faster every 15 seconds!', style: TextStyle(fontSize: 14, color: Colors.orangeAccent)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: _startGame,
                      child: Text(_isGameOver ? 'TRY AGAIN' : 'START GAME', style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() {
  runApp(const CacingKenaGaramGame());
}

class CacingKenaGaramGame extends StatelessWidget {
  const CacingKenaGaramGame({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Game Cacing Kena Garam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.brown[800], // Warna tanah
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

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  final Random _random = Random();

  bool _isPlaying = false;
  bool _isGameOver = false;

  // Game state
  double _health = 100.0;
  Offset _wormPosition = const Offset(150, 300);
  final double _wormRadius = 25.0;
  
  List<Salt> _salts = [];
  List<HealthItem> _items = [];

  // Difficulty & Timing
  Duration _lastTick = Duration.zero;
  Duration _timeElapsed = Duration.zero;
  
  double _spawnTimer = 0;
  double _spawnRate = 1.5; // Jumlah garam per detik
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
      _wormPosition = Offset(MediaQuery.of(context).size.width / 2, MediaQuery.of(context).size.height / 2);
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

  void _tick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    double dt = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    _timeElapsed += (elapsed - _lastTick);

    setState(() {
      // Kesulitan bertambah setiap 15 detik (sesuai persetujuan)
      int difficultyLevel = _lastTick.inSeconds ~/ 15;
      _spawnRate = 1.5 + (difficultyLevel * 0.8);

      // Munculkan garam
      _spawnTimer += dt;
      if (_spawnTimer > (1.0 / _spawnRate)) {
        _spawnTimer = 0;
        _spawnSalt();
      }

      // Munculkan item penyembuh (rata-rata tiap 8 detik)
      _itemSpawnTimer += dt;
      if (_itemSpawnTimer > 8.0) {
        _itemSpawnTimer = 0;
        _spawnItem();
      }

      // Perbarui posisi garam
      for (int i = _salts.length - 1; i >= 0; i--) {
        Salt s = _salts[i];
        s.position += s.velocity * dt;

        // Deteksi tabrakan dengan cacing
        if ((s.position - _wormPosition).distance < _wormRadius + s.radius - 5) {
          _salts.removeAt(i);
          _health -= 15.0; // Damage dari garam
          if (_health <= 0) {
            _health = 0;
            _gameOver();
          }
          continue;
        }

        // Hapus garam jika jauh di luar layar
        if (s.position.dx < -200 || s.position.dx > 2000 || 
            s.position.dy < -200 || s.position.dy > 2000) {
          _salts.removeAt(i);
        }
      }

      // Perbarui item penyembuh
      for (int i = _items.length - 1; i >= 0; i--) {
        HealthItem item = _items[i];
        item.lifeTime += dt;

        // Deteksi cacing mengambil item
        if ((item.position - _wormPosition).distance < _wormRadius + item.radius) {
          _items.removeAt(i);
          _health += 25.0; // Tambah darah
          if (_health > 100) _health = 100;
          continue;
        }

        // Item hilang setelah 7 detik
        if (item.lifeTime > 7.0) { 
          _items.removeAt(i);
        }
      }
    });
  }

  void _spawnSalt() {
    Size size = MediaQuery.of(context).size;
    double side = _random.nextDouble();
    Offset spawnPos;
    
    // Muncul dari salah satu dari 4 sisi layar
    if (side < 0.25) {
      spawnPos = Offset(-20, _random.nextDouble() * size.height);
    } else if (side < 0.5) {
      spawnPos = Offset(size.width + 20, _random.nextDouble() * size.height);
    } else if (side < 0.75) {
      spawnPos = Offset(_random.nextDouble() * size.width, -20);
    } else {
      spawnPos = Offset(_random.nextDouble() * size.width, size.height + 20);
    }

    // Arahkan kecepatan ke posisi cacing saat ini
    Offset direction = _wormPosition - spawnPos;
    double dist = direction.distance;
    if (dist != 0) {
      direction = direction / dist;
    }
    
    // Kecepatan lemparan garam bertambah perlahan seiring level
    double speed = 150.0 + (_spawnRate * 15);
    
    _salts.add(Salt(
      position: spawnPos,
      velocity: direction * speed,
      radius: 8.0,
    ));
  }

  void _spawnItem() {
    Size size = MediaQuery.of(context).size;
    _items.add(HealthItem(
      position: Offset(
        50 + _random.nextDouble() * (size.width - 100), 
        100 + _random.nextDouble() * (size.height - 200)
      ),
      radius: 15.0,
    ));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Size screenSize = MediaQuery.of(context).size;
    
    return Scaffold(
      body: Stack(
        children: [
          // Area Bermain
          if (_isPlaying) ...[
            GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _wormPosition += details.delta;
                  // Cegah cacing keluar dari batas layar
                  _wormPosition = Offset(
                    _wormPosition.dx.clamp(_wormRadius, screenSize.width - _wormRadius),
                    _wormPosition.dy.clamp(_wormRadius, screenSize.height - _wormRadius)
                  );
                });
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: screenSize.width,
                height: screenSize.height,
                color: Colors.transparent,
              ),
            ),
            
            // Gambar Item Pemulih (Obat/Hati)
            ..._items.map((item) => Positioned(
              left: item.position.dx - item.radius,
              top: item.position.dy - item.radius,
              child: Icon(Icons.local_hospital, color: Colors.greenAccent, size: item.radius * 2),
            )),

            // Gambar Garam
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

            // Gambar Cacing
            Positioned(
              left: _wormPosition.dx - _wormRadius,
              top: _wormPosition.dy - _wormRadius,
              child: Container(
                width: _wormRadius * 2,
                height: _wormRadius * 2,
                decoration: BoxDecoration(
                  color: Colors.pink[300], 
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.pink[800]!, width: 3),
                ),
                child: const Center(
                  child: Icon(Icons.sentiment_neutral, size: 24, color: Colors.black45),
                ),
              ),
            ),

            // Health Bar & Informasi
            Positioned(
              top: 40,
              left: 20,
              right: 20,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('DARAH: ${_health.toInt()}%', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('WAKTU: ${_lastTick.inSeconds}s', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
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
          ],
          
          // Layar Menu / Game Over
          if (!_isPlaying)
            Center(
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24, width: 2)
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isGameOver ? 'GAME OVER' : 'CACING vs GARAM',
                      style: TextStyle(
                        fontSize: 32, 
                        fontWeight: FontWeight.bold,
                        color: _isGameOver ? Colors.redAccent : Colors.white
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_isGameOver) ...[
                      Text('Cacing bertahan selama:', style: const TextStyle(fontSize: 16, color: Colors.white70)),
                      Text('${_lastTick.inSeconds} detik', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                      const SizedBox(height: 20),
                    ],
                    const Text('Cara Bermain:\nSeret cacing untuk menghindari garam!\nAmbil tanda (+) untuk menambah darah.', 
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.white70)
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: _startGame,
                      child: Text(_isGameOver ? 'COBA LAGI' : 'MULAI MAIN', style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
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

// Entitas Garam
class Salt {
  Offset position;
  Offset velocity;
  final double radius;

  Salt({required this.position, required this.velocity, required this.radius});
}

// Entitas Item Penyembuh
class HealthItem {
  Offset position;
  final double radius;
  double lifeTime = 0;

  HealthItem({required this.position, required this.radius});
}

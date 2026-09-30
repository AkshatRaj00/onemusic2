import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'audio_handler.dart';
import 'audio_backend.dart';
import 'yt_headless_bridge.dart';

late MyAudioHandler audioHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.onemusic.channel.audio',
      androidNotificationChannelName: 'OneMusic Pro Stream',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  await Hive.initFlutter();
  await Hive.openBox<String>('liked_songs_box');
  runApp(const OneMusicApp());
}

class OneMusicApp extends StatelessWidget {
  const OneMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OneMusic',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF030712),
        primaryColor: const Color(0xFF06B6D4),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF06B6D4),
          secondary: Color(0xFF8B5CF6),
          surface: Color(0xFF0F172A),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _animCtrl.forward();

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (_, __, ___) => const MainShellScreen(),
            transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF06B6D4), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF06B6D4).withOpacity(0.35),
                      blurRadius: 36,
                      offset: const Offset(0, 12),
                    )
                  ],
                ),
                child: const Icon(Icons.graphic_eq_rounded, size: 52, color: Colors.white),
              ),
              const SizedBox(height: 24),
              const Text(
                'OneMusic',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'STUDIO FIDELITY • AD-FREE',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 4.0,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum RepeatMode { off, all, one }

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _selectedTab = 0;
  final AudioPlayer _player = AudioPlayer();
  final AudioBackend _backend = AudioBackend();
  late final Box<String> _likedBox;

  List<SongModel> _feedTracks = [];
  List<SongModel> _currentQueue = [];
  int _currentIndex = -1;

  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isFetchingMoreAutoQueue = false;

  RepeatMode _repeatMode = RepeatMode.off;
  bool _isShuffle = false;
  Timer? _sleepTimer;
  int _sleepMinutesRemaining = 0;

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _likedBox = Hive.box<String>('liked_songs_box');

    // 1. YouTube Headless Bridge Initialize
    YtHeadlessBridge.instance.init();
    YtHeadlessBridge.instance.onPlaybackStateChanged = (playing) {
      if (mounted) setState(() => _isPlaying = playing);
      audioHandler.updatePlaybackState(
        isPlaying: playing,
        processingState: AudioProcessingState.ready,
        position: _position,
        duration: _duration,
      );
    };
    YtHeadlessBridge.instance.onProgressUpdate = (pos, dur) {
      if (mounted) {
        setState(() {
          _position = pos;
          if (dur > Duration.zero) _duration = dur;
        });
      }
      audioHandler.updatePlaybackState(
        isPlaying: _isPlaying,
        position: pos,
        duration: dur,
      );
    };
    YtHeadlessBridge.instance.onVideoEnded = () {
      _handleSongCompletion();
    };

    _initAudioListeners();
    _loadCircadianFeed();
  }

  void _initAudioListeners() {
    audioHandler.onPlayCallback = () async => _togglePlayPause();
    audioHandler.onPauseCallback = () async => _togglePlayPause();
    audioHandler.onStopCallback = () async {
      await _player.stop();
      await YtHeadlessBridge.instance.pause();
    };
    audioHandler.onNextCallback = () async => _playNext();
    audioHandler.onPrevCallback = () async => _playPrevious();
    audioHandler.onSeekCallback = (pos) async {
      final activeSong = (_currentIndex >= 0 && _currentIndex < _currentQueue.length)
          ? _currentQueue[_currentIndex]
          : null;
      if (activeSong?.source == 'youtube') {
        await YtHeadlessBridge.instance.seekTo(pos);
      } else {
        await _player.seek(pos);
      }
    };

    _subs.add(_player.playerStateStream.listen((state) {
      final isPlaying = state.playing;
      AudioProcessingState pState = AudioProcessingState.ready;

      if (state.processingState == ProcessingState.buffering) {
        pState = AudioProcessingState.buffering;
      } else if (state.processingState == ProcessingState.loading) {
        pState = AudioProcessingState.loading;
      } else if (state.processingState == ProcessingState.completed) {
        pState = AudioProcessingState.completed;
        _handleSongCompletion();
      } else if (state.processingState == ProcessingState.idle) {
        pState = AudioProcessingState.idle;
      }

      final activeSong = (_currentIndex >= 0 && _currentIndex < _currentQueue.length)
          ? _currentQueue[_currentIndex]
          : null;

      if (activeSong?.source != 'youtube') {
        if (mounted) {
          setState(() {
            _isPlaying = isPlaying;
            _isBuffering = state.processingState == ProcessingState.buffering ||
                state.processingState == ProcessingState.loading;
          });
        }
        audioHandler.updatePlaybackState(
          isPlaying: isPlaying,
          processingState: pState,
          position: _player.position,
          bufferedPosition: _player.bufferedPosition,
          duration: _player.duration ?? _duration,
        );
      }
    }));

    _subs.add(_player.positionStream.listen((pos) {
      final activeSong = (_currentIndex >= 0 && _currentIndex < _currentQueue.length)
          ? _currentQueue[_currentIndex]
          : null;

      if (activeSong?.source != 'youtube') {
        if (mounted) {
          setState(() => _position = pos);

          if (_duration.inSeconds > 0 &&
              pos.inSeconds > (_duration.inSeconds * 0.8) &&
              !_isFetchingMoreAutoQueue &&
              (_currentIndex >= _currentQueue.length - 2)) {
            _expandQueueWithRadioHeuristics();
          }
        }
        audioHandler.updatePlaybackState(
          isPlaying: _player.playing,
          position: pos,
          bufferedPosition: _player.bufferedPosition,
          duration: _player.duration ?? _duration,
        );
      }
    }));

    _subs.add(_player.durationStream.listen((dur) {
      final activeSong = (_currentIndex >= 0 && _currentIndex < _currentQueue.length)
          ? _currentQueue[_currentIndex]
          : null;

      if (activeSong?.source != 'youtube' && dur != null && dur > Duration.zero) {
        if (mounted) setState(() => _duration = dur);
        audioHandler.updatePlaybackState(
          isPlaying: _player.playing,
          position: _player.position,
          duration: dur,
        );
      }
    }));
  }

  Future<void> _loadCircadianFeed() async {
    final hour = DateTime.now().hour;
    String query = 'Trending Indian Top Hits';
    if (hour < 11) {
      query = 'Morning Acoustic Vibes Hindi';
    } else if (hour >= 17 && hour < 22) {
      query = 'Bollywood Romantic Hits';
    } else if (hour >= 22 || hour < 4) {
      query = 'Late Night Lofi Hindi Beats';
    }

    try {
      final res = await _backend.searchTracks(query);
      if (mounted && res.isNotEmpty) {
        setState(() => _feedTracks = res);
      }
    } catch (_) {}
  }

  Future<void> _expandQueueWithRadioHeuristics() async {
    if (_currentIndex < 0 || _currentIndex >= _currentQueue.length || _isFetchingMoreAutoQueue) return;
    final currentSong = _currentQueue[_currentIndex];
    _isFetchingMoreAutoQueue = true;

    try {
      final recos = await _backend.getAlgorithmicRadio(currentSong);
      if (recos.isNotEmpty && mounted) {
        setState(() {
          final existingIds = _currentQueue.map((s) => s.id).toSet();
          for (final track in recos) {
            if (!existingIds.contains(track.id)) {
              _currentQueue.add(track);
              existingIds.add(track.id);
            }
          }
        });
      }
    } catch (_) {} finally {
      _isFetchingMoreAutoQueue = false;
    }
  }

  Future<void> _playSongFromQueue(List<SongModel> queue, int index) async {
    if (index < 0 || index >= queue.length) return;

    final song = queue[index];
    final initialDuration = song.durationInSeconds > 0
        ? Duration(seconds: song.durationInSeconds)
        : Duration.zero;

    setState(() {
      _currentQueue = List.from(queue);
      _currentIndex = index;
      _isBuffering = true;
      _position = Duration.zero;
      _duration = initialDuration;
    });

    audioHandler.setTrack(
      id: song.id,
      title: song.title.isNotEmpty ? song.title : 'Track',
      artist: song.artist.isNotEmpty ? song.artist : 'OneMusic',
      artUri: song.thumbnailUrl,
      duration: initialDuration,
    );

    // YouTube routing merged directly into just_audio pipeline

    // Native Exoplayer Audio Route (Saavn, Audius, Jamendo, Radio)
    try {
      await YtHeadlessBridge.instance.pause();
      final playableUrl = await _backend.resolveStreamUrl(song);

      if (playableUrl != null && playableUrl.isNotEmpty) {
        await _player.stop();
        final audioSource = AudioSource.uri(Uri.parse(playableUrl));
        await _player.setAudioSource(audioSource);
        await _player.seek(Duration.zero);
        await _player.play();

        if (_currentQueue.length <= index + 2 && !_isFetchingMoreAutoQueue) {
          _expandQueueWithRadioHeuristics();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF1E293B),
              content: Text("Could not resolve stream: ${song.title}"),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Playback Exception: $e");
    } finally {
      if (mounted) setState(() => _isBuffering = false);
    }
  }

  void _handleSongCompletion() async {
    if (_repeatMode == RepeatMode.one) {
      final activeSong = (_currentIndex >= 0 && _currentIndex < _currentQueue.length)
          ? _currentQueue[_currentIndex]
          : null;
      if (activeSong?.source == 'youtube') {
        await YtHeadlessBridge.instance.seekTo(Duration.zero);
        await YtHeadlessBridge.instance.play();
      } else {
        await _player.seek(Duration.zero);
        await _player.play();
      }
      return;
    }

    if (_currentIndex + 1 < _currentQueue.length) {
      _playSongFromQueue(_currentQueue, _currentIndex + 1);
      return;
    }

    if (_repeatMode == RepeatMode.all && _currentQueue.isNotEmpty) {
      _playSongFromQueue(_currentQueue, 0);
      return;
    }

    if (_currentQueue.isNotEmpty && !_isFetchingMoreAutoQueue) {
      final lastSong = _currentQueue[_currentIndex];
      _isFetchingMoreAutoQueue = true;
      try {
        final recos = await _backend.getAlgorithmicRadio(lastSong);
        if (recos.isNotEmpty && mounted) {
          final existingIds = _currentQueue.map((s) => s.id).toSet();
          final newTracks = recos.where((t) => !existingIds.contains(t.id)).toList();

          if (newTracks.isNotEmpty) {
            setState(() => _currentQueue.addAll(newTracks));
            _playSongFromQueue(_currentQueue, _currentIndex + 1);
            return;
          }
        }
      } catch (_) {} finally {
        _isFetchingMoreAutoQueue = false;
      }
    }

    if (_currentQueue.isNotEmpty) {
      _playSongFromQueue(_currentQueue, 0);
    }
  }

  void _playNext() {
    if (_currentQueue.isEmpty) return;

    if (_repeatMode == RepeatMode.one) {
      final activeSong = _currentQueue[_currentIndex];
      if (activeSong.source == 'youtube') {
        YtHeadlessBridge.instance.seekTo(Duration.zero);
        YtHeadlessBridge.instance.play();
      } else {
        _player.seek(Duration.zero);
        _player.play();
      }
      return;
    }

    if (_currentIndex + 1 < _currentQueue.length) {
      _playSongFromQueue(_currentQueue, _currentIndex + 1);
    } else if (_repeatMode == RepeatMode.all) {
      _playSongFromQueue(_currentQueue, 0);
    } else {
      _handleSongCompletion();
    }
  }

  void _playPrevious() {
    if (_currentQueue.isEmpty) return;
    if (_position.inSeconds > 3) {
      final activeSong = _currentQueue[_currentIndex];
      if (activeSong.source == 'youtube') {
        YtHeadlessBridge.instance.seekTo(Duration.zero);
      } else {
        _player.seek(Duration.zero);
      }
      return;
    }
    if (_currentIndex > 0) {
      _playSongFromQueue(_currentQueue, _currentIndex - 1);
    } else {
      _playSongFromQueue(_currentQueue, _currentQueue.length - 1);
    }
  }

  void _togglePlayPause() {
    final activeSong = (_currentIndex >= 0 && _currentIndex < _currentQueue.length)
        ? _currentQueue[_currentIndex]
        : null;

    if (activeSong?.source == 'youtube') {
      if (_isPlaying) {
        YtHeadlessBridge.instance.pause();
      } else {
        YtHeadlessBridge.instance.play();
      }
      return;
    }

    if (_player.playing) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  void _toggleFavorite(SongModel song) {
    setState(() {
      if (_likedBox.containsKey(song.id)) {
        _likedBox.delete(song.id);
      } else {
        _likedBox.put(song.id, jsonEncode(song.toMap()));
      }
    });
  }

  void _cycleRepeatMode() {
    setState(() {
      if (_repeatMode == RepeatMode.off) {
        _repeatMode = RepeatMode.all;
        _player.setLoopMode(LoopMode.all);
      } else if (_repeatMode == RepeatMode.all) {
        _repeatMode = RepeatMode.one;
        _player.setLoopMode(LoopMode.one);
      } else {
        _repeatMode = RepeatMode.off;
        _player.setLoopMode(LoopMode.off);
      }
    });
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffle = !_isShuffle;
      _player.setShuffleModeEnabled(_isShuffle);
    });
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    if (minutes <= 0) {
      setState(() => _sleepMinutesRemaining = 0);
      return;
    }

    setState(() => _sleepMinutesRemaining = minutes);
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_sleepMinutesRemaining <= 1) {
        final activeSong = (_currentIndex >= 0 && _currentIndex < _currentQueue.length)
            ? _currentQueue[_currentIndex]
            : null;
        if (activeSong?.source == 'youtube') {
          YtHeadlessBridge.instance.pause();
        } else {
          _player.pause();
        }
        timer.cancel();
        if (mounted) setState(() => _sleepMinutesRemaining = 0);
      } else {
        if (mounted) setState(() => _sleepMinutesRemaining--);
      }
    });
  }

  List<SongModel> _getPersistedFavorites() {
    final List<SongModel> list = [];
    for (final val in _likedBox.values) {
      try {
        final map = jsonDecode(val);
        list.add(SongModel.fromMap(map));
      } catch (_) {}
    }
    return list;
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good morning";
    if (hour < 17) return "Good afternoon";
    return "Good evening";
  }

  void _openFullPlayer() {
    if (_currentIndex == -1 || _currentQueue.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FullPlayerView(
        player: _player,
        song: _currentQueue[_currentIndex],
        queue: _currentQueue,
        currentIndex: _currentIndex,
        onNext: _playNext,
        onPrevious: _playPrevious,
        isFav: _likedBox.containsKey(_currentQueue[_currentIndex].id),
        onFavToggle: () => _toggleFavorite(_currentQueue[_currentIndex]),
        repeatMode: _repeatMode,
        onRepeatToggle: _cycleRepeatMode,
        isShuffle: _isShuffle,
        onShuffleToggle: _toggleShuffle,
        sleepMinutes: _sleepMinutesRemaining,
        onSleepTimerSelect: _setSleepTimer,
        onSelectQueueIndex: (idx) => _playSongFromQueue(_currentQueue, idx),
        isPlaying: _isPlaying,
        onPlayPauseToggle: _togglePlayPause,
      ),
    );
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    _player.dispose();
    _backend.dispose();
    YtHeadlessBridge.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeSong = (_currentIndex >= 0 && _currentIndex < _currentQueue.length)
        ? _currentQueue[_currentIndex]
        : null;

    final double totalSec = (_duration.inSeconds > 0)
        ? _duration.inSeconds.toDouble()
        : ((activeSong?.durationInSeconds ?? 0) > 0 ? activeSong!.durationInSeconds.toDouble() : 1.0);

    final double progress = (totalSec > 0)
        ? (_position.inSeconds.toDouble() / totalSec).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedTab,
          children: [
            _buildHomeTab(),
            _buildSearchTab(),
            _buildFavoritesTab(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0B0F19).withOpacity(0.92),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            indicatorColor: const Color(0xFF06B6D4).withOpacity(0.18),
            labelTextStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
            ),
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            selectedIndex: _selectedTab,
            onDestinationSelected: (idx) => setState(() => _selectedTab = idx),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined, color: Color(0xFF64748B)),
                selectedIcon: Icon(Icons.home_filled, color: Color(0xFF06B6D4)),
                label: 'Discover',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_rounded, color: Color(0xFF64748B)),
                selectedIcon: Icon(Icons.search_rounded, color: Color(0xFF06B6D4)),
                label: 'Search',
              ),
              NavigationDestination(
                icon: Icon(Icons.favorite_outline_rounded, color: Color(0xFF64748B)),
                selectedIcon: Icon(Icons.favorite_rounded, color: Color(0xFF06B6D4)),
                label: 'Library',
              ),
            ],
          ),
        ),
      ),
      bottomSheet: activeSong != null
          ? GestureDetector(
              onTap: _openFullPlayer,
              child: Container(
                height: 74,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withOpacity(0.92),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.65), blurRadius: 24, offset: const Offset(0, 10)),
                  ],
                  border: Border.all(color: Colors.white.withOpacity(0.09)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progress.isNaN ? 0.0 : progress,
                          minHeight: 2.5,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF06B6D4)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: activeSong.thumbnailUrl,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: const Color(0xFF1E293B)),
                                errorWidget: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white38),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    activeSong.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${activeSong.artist} • ${activeSong.source.toUpperCase()}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            if (_isPlaying) ...[
                              const LiveEqualizerIcon(),
                              const SizedBox(width: 10),
                            ],
                            IconButton(
                              icon: const Icon(Icons.skip_previous_rounded, color: Colors.white70, size: 28),
                              onPressed: _playPrevious,
                            ),
                            IconButton(
                              icon: Icon(_isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                                  color: const Color(0xFF06B6D4), size: 36),
                              onPressed: _togglePlayPause,
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 28),
                              onPressed: _playNext,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildHomeTab() {
    return RefreshIndicator(
      color: const Color(0xFF06B6D4),
      onRefresh: _loadCircadianFeed,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 95),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getGreeting(),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 3),
                  const Text('Intelligent Hybrid Soundscapes', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: const Icon(Icons.bolt_rounded, color: Color(0xFF06B6D4), size: 24),
              )
            ],
          ),
          const SizedBox(height: 24),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCategoryChip('Chill Lo-Fi', Icons.nightlight_round),
                _buildCategoryChip('Acoustic Hindi', Icons.spa_rounded),
                _buildCategoryChip('Bollywood Hits', Icons.star_rounded),
                _buildCategoryChip('Bass & Club', Icons.electric_bolt_rounded),
                _buildCategoryChip('Romantic', Icons.favorite_rounded),
              ],
            ),
          ),
          const SizedBox(height: 30),
          const Text('Recommended For You', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 14),
          _feedTracks.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: Color(0xFF06B6D4))))
              : ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _feedTracks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final song = _feedTracks[index];
                    final isCurrent = _currentQueue == _feedTracks && _currentIndex == index;
                    return _buildTrackListTile(song, isCurrent, () {
                      _playSongFromQueue(_feedTracks, index);
                    });
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String title, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: const Color(0xFF06B6D4)),
        label: Text(title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF0F172A),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onPressed: () async {
          final res = await _backend.searchTracks(title);
          if (mounted) setState(() => _feedTracks = res);
        },
      ),
    );
  }

  Widget _buildSearchTab() {
    return SearchSubView(
      backend: _backend,
      onSongSelect: (songs, idx) => _playSongFromQueue(songs, idx),
    );
  }

  Widget _buildFavoritesTab() {
    final favList = _getPersistedFavorites();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 95),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your Collection', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 4),
          Text('${favList.length} tracks pinned locally', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          const SizedBox(height: 20),
          Expanded(
            child: favList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.favorite_outline_rounded, size: 60, color: Colors.white.withOpacity(0.12)),
                        const SizedBox(height: 14),
                        const Text('No tracks saved to library', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: favList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final song = favList[index];
                      final isCurrent = _currentQueue == favList && _currentIndex == index;
                      return _buildTrackListTile(song, isCurrent, () {
                        _playSongFromQueue(favList, index);
                      });
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackListTile(SongModel song, bool isCurrent, VoidCallback onTap) {
    final isLiked = _likedBox.containsKey(song.id);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isCurrent ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent ? const Color(0xFF06B6D4).withOpacity(0.5) : Colors.white.withOpacity(0.04),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: song.thumbnailUrl,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: const Color(0xFF1E293B)),
                errorWidget: (_, __, ___) => Container(
                  width: 52,
                  height: 52,
                  color: const Color(0xFF1E293B),
                  child: const Icon(Icons.music_note, color: Colors.white38),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? const Color(0xFF38BDF8) : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF06B6D4).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          song.source.toUpperCase(),
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF06B6D4)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isCurrent && _isPlaying) ...[
              const LiveEqualizerIcon(),
              const SizedBox(width: 8),
            ],
            IconButton(
              icon: Icon(isLiked ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                  color: isLiked ? const Color(0xFFEC4899) : Colors.white30, size: 22),
              onPressed: () => _toggleFavorite(song),
            ),
          ],
        ),
      ),
    );
  }
}

class LiveEqualizerIcon extends StatefulWidget {
  const LiveEqualizerIcon({super.key});

  @override
  State<LiveEqualizerIcon> createState() => _LiveEqualizerIconState();
}

class _LiveEqualizerIconState extends State<LiveEqualizerIcon> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(width: 2.5, height: 8 + (12 * _ctrl.value), decoration: BoxDecoration(color: const Color(0xFF06B6D4), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 2.5),
            Container(width: 2.5, height: 20 - (12 * _ctrl.value), decoration: BoxDecoration(color: const Color(0xFF8B5CF6), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 2.5),
            Container(width: 2.5, height: 6 + (14 * _ctrl.value), decoration: BoxDecoration(color: const Color(0xFFEC4899), borderRadius: BorderRadius.circular(2))),
          ],
        );
      },
    );
  }
}

class SearchSubView extends StatefulWidget {
  final AudioBackend backend;
  final Function(List<SongModel> songs, int index) onSongSelect;

  const SearchSubView({super.key, required this.backend, required this.onSongSelect});

  @override
  State<SearchSubView> createState() => _SearchSubViewState();
}

class _SearchSubViewState extends State<SearchSubView> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;
  List<SongModel> _results = [];
  bool _isLoading = false;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _isLoading = true);
      final res = await widget.backend.searchTracks(query);
      if (mounted) {
        setState(() {
          _results = res;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 95),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: "Search songs, YouTube, artists...",
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF06B6D4), size: 22),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                        onPressed: () {
                          _ctrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF06B6D4)))
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          _ctrl.text.isEmpty ? 'Type to stream across all 5 engines' : 'No tracks found',
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final song = _results[index];
                          return ListTile(
                            tileColor: const Color(0xFF0F172A),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: song.thumbnailUrl,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: const Color(0xFF1E293B)),
                                errorWidget: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white),
                              ),
                            ),
                            title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text('${song.artist} • ${song.source.toUpperCase()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                            onTap: () => widget.onSongSelect(_results, index),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class FullPlayerView extends StatefulWidget {
  final AudioPlayer player;
  final SongModel song;
  final List<SongModel> queue;
  final int currentIndex;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool isFav;
  final VoidCallback onFavToggle;
  final RepeatMode repeatMode;
  final VoidCallback onRepeatToggle;
  final bool isShuffle;
  final VoidCallback onShuffleToggle;
  final int sleepMinutes;
  final Function(int) onSleepTimerSelect;
  final Function(int) onSelectQueueIndex;
  final bool isPlaying;
  final VoidCallback onPlayPauseToggle;

  const FullPlayerView({
    super.key,
    required this.player,
    required this.song,
    required this.queue,
    required this.currentIndex,
    required this.onNext,
    required this.onPrevious,
    required this.isFav,
    required this.onFavToggle,
    required this.repeatMode,
    required this.onRepeatToggle,
    required this.isShuffle,
    required this.onShuffleToggle,
    required this.sleepMinutes,
    required this.onSleepTimerSelect,
    required this.onSelectQueueIndex,
    required this.isPlaying,
    required this.onPlayPauseToggle,
  });

  @override
  State<FullPlayerView> createState() => _FullPlayerViewState();
}

class _FullPlayerViewState extends State<FullPlayerView> with SingleTickerProviderStateMixin {
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _isDragging = false;
  double _dragValue = 0.0;
  bool _ambientGlowActive = true;

  late AnimationController _glowController;
  final List<StreamSubscription> _localSubs = [];

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    if (widget.song.durationInSeconds > 0) {
      _dur = Duration(seconds: widget.song.durationInSeconds);
    }

    _localSubs.add(widget.player.positionStream.listen((p) {
      if (mounted && !_isDragging && widget.song.source != 'youtube') {
        setState(() => _pos = p);
      }
    }));

    _localSubs.add(widget.player.durationStream.listen((d) {
      if (mounted && d != null && d.inSeconds > 0 && widget.song.source != 'youtube') {
        setState(() => _dur = d);
      }
    }));
  }

  @override
  void dispose() {
    _glowController.dispose();
    for (final s in _localSubs) {
      s.cancel();
    }
    super.dispose();
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showSleepTimerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sleep Timer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Turn Off Timer', style: TextStyle(color: Color(0xFF94A3B8))),
                trailing: widget.sleepMinutes == 0 ? const Icon(Icons.check, color: Color(0xFF06B6D4)) : null,
                onTap: () {
                  widget.onSleepTimerSelect(0);
                  Navigator.pop(context);
                },
              ),
              ...[15, 30, 45, 60].map((mins) {
                return ListTile(
                  title: Text('$mins Minutes', style: const TextStyle(color: Colors.white)),
                  trailing: widget.sleepMinutes == mins ? const Icon(Icons.check, color: Color(0xFF06B6D4)) : null,
                  onTap: () {
                    widget.onSleepTimerSelect(mins);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showQueueModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0F19),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                  const SizedBox(height: 20),
                  const Text('Up Next', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollCtrl,
                      itemCount: widget.queue.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final song = widget.queue[idx];
                        final isNowPlaying = idx == widget.currentIndex;
                        return ListTile(
                          tileColor: isNowPlaying ? const Color(0xFF1E293B) : Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: song.thumbnailUrl,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                            ),
                          ),
                          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isNowPlaying ? const Color(0xFF38BDF8) : Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                          trailing: isNowPlaying ? const Icon(Icons.graphic_eq_rounded, color: Color(0xFF06B6D4), size: 20) : null,
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSelectQueueIndex(idx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTotalSeconds = _dur.inSeconds > 0
        ? _dur.inSeconds.toDouble()
        : (widget.song.durationInSeconds > 0 ? widget.song.durationInSeconds.toDouble() : 180.0);

    final curSec = _isDragging ? _dragValue : _pos.inSeconds.toDouble().clamp(0.0, effectiveTotalSeconds);

    return Container(
      height: MediaQuery.of(context).size.height * 0.94,
      decoration: const BoxDecoration(
        color: Color(0xFF030712),
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: Stack(
        children: [
          if (_ambientGlowActive)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _glowController,
                builder: (context, _) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.35),
                        radius: 0.95 + (_glowController.value * 0.2),
                        colors: [
                          const Color(0xFF06B6D4).withOpacity(0.28 + (_glowController.value * 0.12)),
                          const Color(0xFF8B5CF6).withOpacity(0.15),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Column(
                      children: [
                        Text(
                          widget.song.source.toUpperCase(),
                          style: const TextStyle(fontSize: 10, letterSpacing: 2.5, color: Color(0xFF06B6D4), fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text('${widget.currentIndex + 1} of ${widget.queue.length}', style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        _ambientGlowActive ? Icons.blur_on_rounded : Icons.blur_off_rounded,
                        color: _ambientGlowActive ? const Color(0xFF06B6D4) : Colors.white38,
                        size: 24,
                      ),
                      onPressed: () => setState(() => _ambientGlowActive = !_ambientGlowActive),
                    ),
                  ],
                ),
                const Spacer(),
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, child) {
                    return Container(
                      width: 290,
                      height: 290,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF06B6D4).withOpacity(_ambientGlowActive ? 0.45 + (_glowController.value * 0.15) : 0.15),
                            blurRadius: _ambientGlowActive ? 48 + (_glowController.value * 12) : 24,
                            spreadRadius: _ambientGlowActive ? 2 : 0,
                            offset: const Offset(0, 16),
                          )
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: CachedNetworkImage(
                      imageUrl: widget.song.thumbnailUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: const Color(0xFF0F172A)),
                      errorWidget: (_, __, ___) => Container(color: const Color(0xFF0F172A), child: const Icon(Icons.music_note, size: 84, color: Colors.white24)),
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 5),
                          Text(widget.song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8))),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(widget.isFav ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                          color: widget.isFav ? const Color(0xFFEC4899) : Colors.white38, size: 28),
                      onPressed: widget.onFavToggle,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: const Color(0xFF06B6D4),
                    inactiveTrackColor: Colors.white12,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    min: 0.0,
                    max: effectiveTotalSeconds,
                    value: curSec,
                    onChangeStart: (v) {
                      setState(() {
                        _isDragging = true;
                        _dragValue = v;
                      });
                    },
                    onChanged: (v) => setState(() => _dragValue = v),
                    onChangeEnd: (v) async {
                      final targetDuration = Duration(seconds: v.toInt());
                      if (widget.song.source == 'youtube') {
                        await YtHeadlessBridge.instance.seekTo(targetDuration);
                      } else {
                        await widget.player.seek(targetDuration);
                      }
                      setState(() {
                        _isDragging = false;
                        _pos = targetDuration;
                      });
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatTime(_isDragging ? Duration(seconds: _dragValue.toInt()) : _pos),
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(_formatTime(Duration(seconds: effectiveTotalSeconds.toInt())),
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.shuffle_rounded, color: widget.isShuffle ? const Color(0xFF06B6D4) : Colors.white38, size: 24),
                      onPressed: widget.onShuffleToggle,
                    ),
                    IconButton(icon: const Icon(Icons.skip_previous_rounded, size: 38, color: Colors.white), onPressed: widget.onPrevious),
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF06B6D4), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF06B6D4).withOpacity(0.4), blurRadius: 22, offset: const Offset(0, 8)),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 38, color: Colors.white),
                        onPressed: widget.onPlayPauseToggle,
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.skip_next_rounded, size: 38, color: Colors.white), onPressed: widget.onNext),
                    IconButton(
                      icon: Icon(
                        widget.repeatMode == RepeatMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        color: widget.repeatMode != RepeatMode.off ? const Color(0xFF06B6D4) : Colors.white38,
                        size: 24,
                      ),
                      onPressed: widget.onRepeatToggle,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      icon: Icon(Icons.timer_outlined, size: 18, color: widget.sleepMinutes > 0 ? const Color(0xFF06B6D4) : const Color(0xFF64748B)),
                      label: Text(
                        widget.sleepMinutes > 0 ? '${widget.sleepMinutes}m' : 'Sleep',
                        style: TextStyle(color: widget.sleepMinutes > 0 ? const Color(0xFF06B6D4) : const Color(0xFF64748B), fontSize: 12),
                      ),
                      onPressed: _showSleepTimerModal,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.queue_music_rounded, size: 18, color: Color(0xFF94A3B8)),
                      label: const Text('Queue', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                      onPressed: _showQueueModal,
                    ),
                  ],
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
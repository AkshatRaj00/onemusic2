import 'dart:async';
import 'package:audio_service/audio_service.dart';

class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  // कॉलबैक्स (main.dart के Player Engine से सीधे बाइंड होंगे)
  Future<void> Function()? onPlayCallback;
  Future<void> Function()? onPauseCallback;
  Future<void> Function()? onNextCallback;
  Future<void> Function()? onPrevCallback;
  Future<void> Function()? onStopCallback;
  Future<void> Function(Duration)? onSeekCallback;

  MyAudioHandler() {
    // इनिशियल स्टेट इनिशियलाइज़ेशन (Android 13+ OS क्रैश प्रिवेंशन)
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.playPause,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [0, 1, 2], // 3 क्लीन बटन: Prev, Play, Next
        processingState: AudioProcessingState.idle,
        playing: false,
        speed: 1.0,
      ),
    );
  }

  /// ट्रैक लोड होते ही मेटाडेटा और इनिशियल स्टेट एक साथ सिंक करने के लिए
  void setTrack({
    required String id,
    required String title,
    required String artist,
    String? artUri,
    Duration duration = Duration.zero,
    bool autoPlay = true,
  }) {
    // 1. Android MediaSession के लिए मेटाडेटा पुश
    final item = MediaItem(
      id: id,
      album: "OneMusic",
      title: title,
      artist: artist,
      artUri: (artUri != null && artUri.startsWith("http")) ? Uri.tryParse(artUri) : null,
      duration: duration > Duration.zero ? duration : null,
    );
    mediaItem.add(item);

    // 2. तुरंत लोडिंग/बफरिंग स्टेट ब्रॉडकास्ट करो ताकि लॉक-स्क्रीन सिंक रहे
    updatePlaybackState(
      isPlaying: autoPlay,
      processingState: AudioProcessingState.loading,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      duration: duration,
    );
  }

  /// प्लेयर के स्ट्रीम लिसनर्स (Position, State, Buffer) से यह कॉल होगा
  void updatePlaybackState({
    required bool isPlaying,
    AudioProcessingState processingState = AudioProcessingState.ready,
    Duration position = Duration.zero,
    Duration bufferedPosition = Duration.zero,
    Duration duration = Duration.zero,
  }) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.playPause,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [0, 1, 2], // Prev, Play/Pause, Next
        processingState: processingState,
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
        speed: 1.0, // Android 13/14+ सीक-बार और वेवफ़ॉर्म के लिए 1.0 ज़रूरी है
      ),
    );

    // अगर ड्यूरेशन बाद में लोड हो तो मेटाडेटा में अपडेट करो
    if (mediaItem.value != null && duration > Duration.zero && mediaItem.value!.duration != duration) {
      mediaItem.add(mediaItem.value!.copyWith(duration: duration));
    }
  }

  // ========================================================
  // ANDROID OS / AVRCP / HEADSET / BLUETOOTH WATCH DISPATCHER
  // ========================================================

  @override
  Future<void> play() async {
    playbackState.add(playbackState.value.copyWith(playing: true));
    if (onPlayCallback != null) {
      await onPlayCallback!();
    }
  }

  @override
  Future<void> pause() async {
    playbackState.add(playbackState.value.copyWith(playing: false));
    if (onPauseCallback != null) {
      await onPauseCallback!();
    }
  }

  @override
  Future<void> stop() async {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    if (onStopCallback != null) {
      await onStopCallback!();
    } else if (onPauseCallback != null) {
      await onPauseCallback!();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    // OS नोटिफिकेशन पर सीक बार तुरंत रिस्पॉन्ड करे
    playbackState.add(playbackState.value.copyWith(updatePosition: position));
    if (onSeekCallback != null) {
      await onSeekCallback!(position);
    }
  }

  @override
  Future<void> skipToNext() async {
    if (onNextCallback != null) {
      await onNextCallback!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (onPrevCallback != null) {
      await onPrevCallback!();
    }
  }

  // ईयरबड्स / हेडसेट के सिंगल-टैप और हार्डवेयर बटन के लिए
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    if (playbackState.value.playing) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    // जब यूजर रीसेंट ऐप्स से ऐप स्वाइप-किल कर दे
    await stop();
  }
}
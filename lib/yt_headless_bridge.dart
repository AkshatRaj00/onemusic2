import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class YtHeadlessBridge {
  static final YtHeadlessBridge instance = YtHeadlessBridge._internal();
  YtHeadlessBridge._internal();

  HeadlessInAppWebView? _headlessWebView;
  InAppWebViewController? _webViewController;
  bool _isInitialized = false;
  bool _isPlayerReady = false;
  String? _pendingVideoId;

  void Function(bool isPlaying)? onPlaybackStateChanged;
  void Function(Duration position, Duration duration)? onProgressUpdate;
  VoidCallback? onVideoEnded;
  void Function(int errorCode)? onErrorOccurred;

  Future<void> init() async {
    if (_isInitialized) return;

    _headlessWebView = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: _getBridgeHtml(),
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('https://www.youtube-nocookie.com'), // Bypasses Error 150/101
      ),
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptEnabled: true,
        cacheEnabled: true,
        transparentBackground: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        userAgent: 'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        _setupJavaScriptHandlers(controller);
      },
      onLoadStop: (controller, url) {
        _isInitialized = true;
      },
    );

    await _headlessWebView?.run();
  }

  void _setupJavaScriptHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'onPlayerReady',
      callback: (_) {
        _isPlayerReady = true;
        if (_pendingVideoId != null) {
          final id = _pendingVideoId!;
          _pendingVideoId = null;
          loadAndPlay(id);
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onStateChange',
      callback: (args) {
        if (args.isEmpty) return;
        final state = args[0] as int;
        if (state == 1) {
          onPlaybackStateChanged?.call(true);
        } else if (state == 2) {
          onPlaybackStateChanged?.call(false);
        } else if (state == 0) {
          onPlaybackStateChanged?.call(false);
          onVideoEnded?.call();
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onTimeUpdate',
      callback: (args) {
        if (args.length >= 2) {
          final curSec = (args[0] as num).toDouble();
          final totalSec = (args[1] as num).toDouble();
          onProgressUpdate?.call(
            Duration(milliseconds: (curSec * 1000).toInt()),
            Duration(milliseconds: (totalSec * 1000).toInt()),
          );
        }
      },
    );

    controller.addJavaScriptHandler(
      handlerName: 'onError',
      callback: (args) {
        final err = args.isNotEmpty ? (args[0] as int) : -1;
        onErrorOccurred?.call(err);
      },
    );
  }

  Future<void> loadAndPlay(String videoId) async {
    if (!_isInitialized || _webViewController == null) {
      _pendingVideoId = videoId;
      await init();
      return;
    }

    if (!_isPlayerReady) {
      _pendingVideoId = videoId;
      return;
    }

    await _webViewController?.evaluateJavascript(source: 'playVideo("$videoId");');
  }

  Future<void> play() async {
    await _webViewController?.evaluateJavascript(source: 'resumeVideo();');
  }

  Future<void> pause() async {
    await _webViewController?.evaluateJavascript(source: 'pauseVideo();');
  }

  Future<void> seekTo(Duration duration) async {
    final seconds = duration.inSeconds;
    await _webViewController?.evaluateJavascript(source: 'seekTo($seconds);');
  }

  void dispose() {
    _headlessWebView?.dispose();
    _headlessWebView = null;
    _webViewController = null;
    _isInitialized = false;
    _isPlayerReady = false;
    _pendingVideoId = null;
  }

  String _getBridgeHtml() {
    return '''
    <!DOCTYPE html>
    <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>body { margin: 0; background: black; overflow: hidden; }</style>
      </head>
      <body>
        <div id="player"></div>
        <script>
          var tag = document.createElement('script');
          tag.src = "https://www.youtube.com/iframe_api";
          var firstScriptTag = document.getElementsByTagName('script')[0];
          firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

          var player;
          var timeUpdater = null;

          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              height: '100%',
              width: '100%',
              playerVars: {
                'playsinline': 1,
                'autoplay': 1,
                'controls': 0,
                'disablekb': 1,
                'fs': 0,
                'rel': 0,
                'origin': 'https://www.youtube-nocookie.com'
              },
              events: {
                'onReady': onPlayerReady,
                'onStateChange': onPlayerStateChange,
                'onError': onPlayerError
              }
            });
          }

          function onPlayerReady(event) {
            window.flutter_inappwebview.callHandler('onPlayerReady');
          }

          function onPlayerError(event) {
            window.flutter_inappwebview.callHandler('onError', event.data);
          }

          function onPlayerStateChange(event) {
            window.flutter_inappwebview.callHandler('onStateChange', event.data);
            if (event.data == YT.PlayerState.PLAYING) {
              startTimeTracking();
            } else {
              stopTimeTracking();
            }
          }

          function startTimeTracking() {
            stopTimeTracking();
            timeUpdater = setInterval(function() {
              if (player && player.getCurrentTime) {
                var cur = player.getCurrentTime();
                var dur = player.getDuration();
                window.flutter_inappwebview.callHandler('onTimeUpdate', cur, dur);
              }
            }, 500);
          }

          function stopTimeTracking() {
            if (timeUpdater) clearInterval(timeUpdater);
          }

          function playVideo(id) {
            if (player && player.loadVideoById) {
              player.loadVideoById({'videoId': id, 'suggestedQuality': 'small'});
              player.playVideo();
            }
          }

          function pauseVideo() {
            if (player && player.pauseVideo) player.pauseVideo();
          }

          function resumeVideo() {
            if (player && player.playVideo) player.playVideo();
          }

          function seekTo(sec) {
            if (player && player.seekTo) player.seekTo(sec, true);
          }
        </script>
      </body>
    </html>
    ''';
  }
}
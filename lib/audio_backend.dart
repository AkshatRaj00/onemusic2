import 'dart:convert';
import 'package:dart_des/dart_des.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class SongModel {
  final String id;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final String encryptedMediaUrl;
  final int durationInSeconds;
  final String language;
  final String source; // 'saavn', 'youtube', 'audius', 'jamendo', 'radio'

  SongModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.encryptedMediaUrl,
    required this.durationInSeconds,
    this.language = 'hindi',
    this.source = 'saavn',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'thumbnailUrl': thumbnailUrl,
      'encryptedMediaUrl': encryptedMediaUrl,
      'durationInSeconds': durationInSeconds,
      'language': language,
      'source': source,
    };
  }

  factory SongModel.fromMap(Map<dynamic, dynamic> map) {
    return SongModel(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      artist: map['artist']?.toString() ?? '',
      thumbnailUrl: map['thumbnailUrl']?.toString() ?? '',
      encryptedMediaUrl: map['encryptedMediaUrl']?.toString() ?? '',
      durationInSeconds: int.tryParse(map['durationInSeconds']?.toString() ?? '0') ?? 0,
      language: map['language']?.toString() ?? 'hindi',
      source: map['source']?.toString() ?? 'saavn',
    );
  }
}

class AudioBackend {
  // 1. JioSaavn
  static const String _jioBaseUrl = 'https://www.jiosaavn.com/api.php';
  static const List<String> _desKeys = ['38346536', '38346591'];

  // 2. Jamendo API (Fixed Client ID & Parameters)
  static const String _jamendoClientId = '56d30c95';
  static const String _jamendoBaseUrl = 'https://api.jamendo.com/v3.0';

  // 3. Audius API (Dynamic Active Hosts Pool)
  static const String _audiusApp = 'OneMusicApp';
  static const List<String> _audiusHosts = [
    'https://discoveryprovider.audius.co/v1',
    'https://audius-dp.amsterdam.creatorseed.com/v1',
    'https://discovery-us-01.audius.openplayer.org/v1',
  ];

  // 4. Radio Browser Endpoint
  static const String _radioBaseUrl = 'https://de1.api.radio-browser.info/json/stations/byname';

  // 5. YouTube Client
  final YoutubeExplode _yt = YoutubeExplode();

  final Map<String, String> _networkHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9,hi;q=0.8',
  };

  String _cleanHtml(String text) {
    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  // --- JioSaavn 3DES Decryption ---
  String _decryptSaavnCdn(String encUrl) {
    if (encUrl.isEmpty) return '';

    for (final keyString in _desKeys) {
      try {
        final key = utf8.encode(keyString);
        final encryptedBytes = base64.decode(encUrl);
        final des = DES(key: key, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS7);
        final decrypted = des.decrypt(encryptedBytes);
        final url = utf8.decode(decrypted);

        if (url.startsWith('http://') || url.startsWith('https://')) {
          return url
              .replaceAll('.mp4', '_320.mp4')
              .replaceAll('preview.saavn.com', 'aac.saavn.com');
        }
      } catch (_) {
        continue;
      }
    }
    return '';
  }

  // --- SOURCE 1: JioSaavn ---
  Future<List<SongModel>> _searchSaavn(String query) async {
    final List<SongModel> list = [];
    try {
      final uri = Uri.parse(
        '$_jioBaseUrl?__call=search.getResults&_format=json&_marker=0&cc=in&p=1&n=15&q=${Uri.encodeComponent(query)}',
      );
      final res = await http.get(uri, headers: _networkHeaders).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body.trim());
        final dynamic results = data['results'];
        if (results is List) {
          for (final item in results) {
            final id = item['id']?.toString() ?? '';
            final rawTitle = item['song']?.toString() ?? item['title']?.toString() ?? '';
            final rawArtist = item['primary_artists']?.toString() ?? item['singers']?.toString() ?? 'Unknown Artist';
            final encUrl = item['more_info']?['encrypted_media_url']?.toString() ?? item['encrypted_media_url']?.toString();
            final duration = int.tryParse(item['more_info']?['duration']?.toString() ?? item['duration']?.toString() ?? '0') ?? 0;
            final lang = item['language']?.toString() ?? 'hindi';

            if (id.isNotEmpty && rawTitle.isNotEmpty && encUrl != null) {
              String thumb = item['image']?.toString() ?? '';
              thumb = thumb.replaceAll('150x150', '500x500');

              list.add(SongModel(
                id: id,
                title: _cleanHtml(rawTitle),
                artist: _cleanHtml(rawArtist),
                thumbnailUrl: thumb,
                encryptedMediaUrl: encUrl,
                durationInSeconds: duration,
                language: lang,
                source: 'saavn',
              ));
            }
          }
        }
      }
    } catch (_) {}
    return list;
  }

  // --- SOURCE 2: YouTube Search ---
  Future<List<SongModel>> _searchYouTube(String query) async {
    final List<SongModel> list = [];
    try {
      final searchResults = await _yt.search.search(query);
      for (final video in searchResults.take(10)) {
        list.add(SongModel(
          id: video.id.value,
          title: video.title,
          artist: video.author,
          thumbnailUrl: video.thumbnails.highResUrl,
          encryptedMediaUrl: '',
          durationInSeconds: video.duration?.inSeconds ?? 0,
          language: 'all',
          source: 'youtube',
        ));
      }
    } catch (_) {}
    return list;
  }

  // --- SOURCE 3: Audius (Working Node Pool & Fallback) ---
  Future<List<SongModel>> _searchAudius(String query) async {
    final List<SongModel> list = [];
    for (final host in _audiusHosts) {
      try {
        final uri = Uri.parse('$host/tracks/search?query=${Uri.encodeComponent(query)}&app_name=$_audiusApp');
        final res = await http.get(uri, headers: _networkHeaders).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final dynamic tracks = data['data'];
          if (tracks is List && tracks.isNotEmpty) {
            for (final item in tracks.take(8)) {
              final id = item['id']?.toString() ?? '';
              final title = item['title']?.toString() ?? '';
              final artist = item['user']?['name']?.toString() ?? 'Audius Artist';
              final thumb = item['artwork']?['480x480']?.toString() ?? item['artwork']?['150x150']?.toString() ?? '';
              final duration = int.tryParse(item['duration']?.toString() ?? '0') ?? 0;

              if (id.isNotEmpty && title.isNotEmpty) {
                list.add(SongModel(
                  id: 'aud_$id',
                  title: _cleanHtml(title),
                  artist: _cleanHtml(artist),
                  thumbnailUrl: thumb,
                  encryptedMediaUrl: '$host/tracks/$id/stream?app_name=$_audiusApp',
                  durationInSeconds: duration,
                  language: 'global',
                  source: 'audius',
                ));
              }
            }
            return list;
          }
        }
      } catch (_) {
        continue;
      }
    }
    return list;
  }

  // --- SOURCE 4: Jamendo (Fixed namesearch parameter) ---
  Future<List<SongModel>> _searchJamendo(String query) async {
    final List<SongModel> list = [];
    try {
      final uri = Uri.parse(
        '$_jamendoBaseUrl/tracks/?client_id=$_jamendoClientId&format=json&limit=10&namesearch=${Uri.encodeComponent(query)}&audioformat=mp32',
      );
      final res = await http.get(uri, headers: _networkHeaders).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final dynamic results = data['results'];
        if (results is List) {
          for (final item in results) {
            final id = item['id']?.toString() ?? '';
            final title = item['name']?.toString() ?? '';
            final artist = item['artist_name']?.toString() ?? 'Jamendo Artist';
            final audioUrl = item['audio']?.toString() ?? '';
            final image = item['image']?.toString() ?? '';
            final duration = int.tryParse(item['duration']?.toString() ?? '0') ?? 0;

            if (id.isNotEmpty && title.isNotEmpty && audioUrl.isNotEmpty) {
              list.add(SongModel(
                id: 'jam_$id',
                title: _cleanHtml(title),
                artist: _cleanHtml(artist),
                thumbnailUrl: image,
                encryptedMediaUrl: audioUrl,
                durationInSeconds: duration,
                language: 'global',
                source: 'jamendo',
              ));
            }
          }
        }
      }
    } catch (_) {}
    return list;
  }

  // --- SOURCE 5: Radio Browser (HTTPS Only Filter) ---
  Future<List<SongModel>> _searchRadio(String query) async {
    final List<SongModel> list = [];
    try {
      final uri = Uri.parse('$_radioBaseUrl/${Uri.encodeComponent(query)}?limit=8&hidebroken=true');
      final res = await http.get(uri, headers: _networkHeaders).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final dynamic stations = jsonDecode(res.body);
        if (stations is List) {
          for (final item in stations) {
            final name = item['name']?.toString() ?? '';
            final streamUrl = item['url_resolved']?.toString() ?? item['url']?.toString() ?? '';
            final favicon = item['favicon']?.toString() ?? '';

            // Android Cleartext blocking se bachne ke liye sirf https stream
            if (name.isNotEmpty && streamUrl.startsWith('https://')) {
              list.add(SongModel(
                id: 'radio_${item['stationuuid'] ?? name}',
                title: _cleanHtml(name),
                artist: 'Live Radio Station',
                thumbnailUrl: favicon,
                encryptedMediaUrl: streamUrl,
                durationInSeconds: 0,
                language: 'live',
                source: 'radio',
              ));
            }
          }
        }
      }
    } catch (_) {}
    return list;
  }

  // --- UNIFIED SEARCH ---
  Future<List<SongModel>> searchTracks(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final results = await Future.wait([
      _searchSaavn(cleanQuery),
      _searchYouTube(cleanQuery),
      _searchAudius(cleanQuery),
      _searchJamendo(cleanQuery),
      _searchRadio(cleanQuery),
    ]);

    final List<SongModel> aggregated = [];
    final Set<String> seen = {};

    for (final sourceList in results) {
      for (final song in sourceList) {
        final key = '${song.title.toLowerCase().trim()}_${song.artist.toLowerCase().trim()}';
        if (!seen.contains(key) && !seen.contains(song.id)) {
          seen.add(key);
          seen.add(song.id);
          aggregated.add(song);
        }
      }
    }

    return aggregated;
  }

  // --- STREAM RESOLVER (AAC / MP4 Android Hardware Compatible) ---
  Future<String?> resolveStreamUrl(SongModel song) async {
    // 1. Direct Playable Streams
    if (song.source == 'jamendo' || song.source == 'radio') {
      return song.encryptedMediaUrl;
    }

    // 2. Audius Redirect Resolution
    if (song.source == 'audius') {
      try {
        final client = http.Client();
        final request = http.Request('GET', Uri.parse(song.encryptedMediaUrl))..followRedirects = false;
        final response = await client.send(request).timeout(const Duration(seconds: 4));
        if (response.isRedirect && response.headers.containsKey('location')) {
          return response.headers['location'];
        }
        return song.encryptedMediaUrl;
      } catch (_) {
        return song.encryptedMediaUrl;
      }
    }

                        // 3. YouTube Bulletproof IOS_MUSIC & ANDROID_VR Direct Client
    if (song.source == 'youtube' || song.encryptedMediaUrl.isEmpty) {
      final videoId = song.id;

      // Tier 1: IOS_MUSIC Official InnerTube API (Zero PoToken, Direct Playable M4A)
      try {
        final uri = Uri.parse('https://music.youtube.com/youtubei/v1/player');
        final payload = {
          "context": {
            "client": {
              "clientName": "IOS_MUSIC",
              "clientVersion": "6.42.1",
              "deviceMake": "Apple",
              "deviceModel": "iPhone16,2",
              "hl": "en",
              "gl": "IN"
            }
          },
          "videoId": videoId,
          "contentCheckOk": true,
          "racyCheckOk": true
        };

        final res = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'YouTubeMusic/6.42.1 (iPhone16,2; iOS 17_5; Scale/3.00)',
            'X-YouTube-Client-Name': '26',
            'X-YouTube-Client-Version': '6.42.1',
          },
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final streamingData = data['streamingData'];
          if (streamingData != null) {
            final adaptive = (streamingData['adaptiveFormats'] as List?) ?? [];
            for (final f in adaptive) {
              final mime = f['mimeType']?.toString().toLowerCase() ?? '';
              final url = f['url']?.toString() ?? '';
              if (mime.contains('audio/mp4') && url.isNotEmpty) {
                return url;
              }
            }
            for (final f in adaptive) {
              final mime = f['mimeType']?.toString().toLowerCase() ?? '';
              final url = f['url']?.toString() ?? '';
              if (mime.contains('audio') && url.isNotEmpty) {
                return url;
              }
            }
          }
        }
      } catch (_) {}

      // Tier 2: ANDROID_VR InnerTube Client (Google BotGuard Exempt)
      try {
        final vrUri = Uri.parse('https://www.youtube.com/youtubei/v1/player');
        final vrPayload = {
          "context": {
            "client": {
              "clientName": "ANDROID_VR",
              "clientVersion": "1.61.48",
              "deviceMake": "Oculus",
              "deviceModel": "Quest 3",
              "hl": "en",
              "gl": "IN"
            }
          },
          "videoId": videoId
        };

        final vrRes = await http.post(
          vrUri,
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Quest 3) AppleWebKit/537.36',
          },
          body: jsonEncode(vrPayload),
        ).timeout(const Duration(seconds: 4));

        if (vrRes.statusCode == 200) {
          final vrData = jsonDecode(vrRes.body);
          final streamingData = vrData['streamingData'];
          if (streamingData != null) {
            final adaptive = (streamingData['adaptiveFormats'] as List?) ?? [];
            for (final f in adaptive) {
              final mime = f['mimeType']?.toString().toLowerCase() ?? '';
              final url = f['url']?.toString() ?? '';
              if (mime.contains('audio/mp4') && url.isNotEmpty) {
                return url;
              }
            }
          }
        }
      } catch (_) {}

      // Tier 3: JioSaavn Instant Fallback
      try {
        final cleanTitle = song.title
            .replaceAll(RegExp(r'\(.*?\)|\[.*?\]|Official|Video|Audio|Song|Lyric|Lyrical|Remix', caseSensitive: false), '')
            .split('|')[0]
            .split('-')[0]
            .trim();
        final saavnMatches = await _searchSaavn('$cleanTitle ${song.artist}');
        if (saavnMatches.isNotEmpty) {
          final saavnStream = await resolveStreamUrl(saavnMatches.first);
          if (saavnStream != null && saavnStream.isNotEmpty) {
            return saavnStream;
          }
        }
      } catch (_) {}
    }
// 4. JioSaavn Resolution
    if (song.source == 'saavn' && song.encryptedMediaUrl.isNotEmpty) {
      try {
        final authUri = Uri.parse(
          '$_jioBaseUrl?__call=song.generateAuthToken&_format=json&bitrate=320&url=${Uri.encodeComponent(song.encryptedMediaUrl)}',
        );
        final res = await http.get(authUri, headers: _networkHeaders).timeout(const Duration(seconds: 3));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body.trim());
          final authUrl = data['auth_url']?.toString();
          if (authUrl != null && authUrl.isNotEmpty) return authUrl;
        }
      } catch (_) {}

      final cdnUrl = _decryptSaavnCdn(song.encryptedMediaUrl);
      if (cdnUrl.isNotEmpty) return cdnUrl;

      // Saavn fail hone par YouTube MP4 Fallback
      try {
        final sRes = await _yt.search.search('${song.title} ${song.artist} audio');
        if (sRes.isNotEmpty) {
          final fManifest = await _yt.videos.streamsClient.getManifest(sRes.first.id);
          final aacStreams = fManifest.audioOnly.where((s) => s.container == StreamContainer.mp4);
          if (aacStreams.isNotEmpty) {
            return aacStreams.withHighestBitrate().url.toString();
          }
          return fManifest.audioOnly.withHighestBitrate().url.toString();
        }
      } catch (_) {}
    }

    return null;
  }

  // --- ALGORITHMIC RADIO ---
  Future<List<SongModel>> getAlgorithmicRadio(SongModel currentSong) async {
    if (currentSong.source == 'saavn') {
      try {
        final uri = Uri.parse(
          '$_jioBaseUrl?__call=reco.getrecos&_format=json&_marker=0&cc=in&pid=${currentSong.id}',
        );
        final res = await http.get(uri, headers: _networkHeaders).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final dynamic data = jsonDecode(res.body.trim());
          if (data is List && data.isNotEmpty) {
            final List<SongModel> list = [];
            for (final item in data) {
              final id = item['id']?.toString() ?? '';
              final rawTitle = item['song']?.toString() ?? item['title']?.toString() ?? '';
              final rawArtist = item['primary_artists']?.toString() ?? item['singers']?.toString() ?? 'Unknown Artist';
              final encUrl = item['more_info']?['encrypted_media_url']?.toString() ?? item['encrypted_media_url']?.toString();
              final duration = int.tryParse(item['more_info']?['duration']?.toString() ?? item['duration']?.toString() ?? '0') ?? 0;

              if (id.isNotEmpty && rawTitle.isNotEmpty && encUrl != null && id != currentSong.id) {
                String thumb = item['image']?.toString() ?? '';
                thumb = thumb.replaceAll('150x150', '500x500');

                list.add(SongModel(
                  id: id,
                  title: _cleanHtml(rawTitle),
                  artist: _cleanHtml(rawArtist),
                  thumbnailUrl: thumb,
                  encryptedMediaUrl: encUrl,
                  durationInSeconds: duration,
                  language: currentSong.language,
                  source: 'saavn',
                ));
              }
            }
            if (list.isNotEmpty) return list;
          }
        }
      } catch (_) {}
    }

    final cleanArtist = currentSong.artist.split(',')[0].split('&')[0].trim();
    final results = await searchTracks('$cleanArtist hits');
    return results.where((s) => s.id != currentSong.id).toList();
  }

  void dispose() {
    _yt.close();
  }
}
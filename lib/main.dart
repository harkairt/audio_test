import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_test/10_s_delay.dart';
import 'package:audio_service_test/audio_player_task.dart';
import 'package:audio_service_test/download_task_notifier.dart';
import 'package:audio_service_test/downloader_main.dart';
import 'package:audio_service_test/player_service.dart';
import 'package:audio_service_test/seeker.dart';
import 'package:audio_service_test/text_to_speeck_task.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:rxdart/rxdart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterDownloader.initialize(debug: debug);

  runApp(new MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Service Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AudioServiceWidget(child: MainScreen()),
    );
  }
}

class MainScreen extends StatelessWidget {
  final playerService = PlayerService();
  final downloadService = DownloadService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Service Demo'),
      ),
      body: Center(
        child: StreamBuilder<bool>(
          stream: playerService.isServiceRunningStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.active) {
              // Don't show anything until we've ascertained whether or not the
              // service is running, since we want to show a different UI in
              // each case.
              return SizedBox();
            }
            final running = snapshot.data ?? false;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!running) ...[
                  // UI to show when we're not running, i.e. a menu.
                  audioPlayerButton(),
                  if (kIsWeb || !Platform.isMacOS) textToSpeechButton(),
                  downloadFileButton(),
                  betterDownloadFileButton(),
                  dioDownloadFileButton(),
                  With10SecondDelay(),
                ] else ...[
                  // UI to show when we're running, i.e. player state/controls.

                  // Queue display/controls.
                  StreamBuilder<PlayerQueueState>(
                    stream: _queueStateStream,
                    builder: (context, snapshot) {
                      debugPrint('_queueStateStream builder');
                      final queueState = snapshot.data;
                      final queue = queueState?.queue ?? [];
                      final currentlyPlayingItem = queueState?.currentlyPlayingItem;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (queue != null && queue.isNotEmpty)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.skip_previous),
                                  iconSize: 64.0,
                                  onPressed: currentlyPlayingItem == queue.first ? null : playerService.skipToPrevious,
                                ),
                                IconButton(
                                  icon: Icon(Icons.skip_next),
                                  iconSize: 64.0,
                                  onPressed: currentlyPlayingItem == queue.last ? null : playerService.skipToNext,
                                ),
                              ],
                            ),
                          if (currentlyPlayingItem?.title != null) Text(currentlyPlayingItem.title),
                        ],
                      );
                    },
                  ),
                  // Play/pause/stop buttons.
                  StreamBuilder<bool>(
                    stream: playerService.playerPlaybackStateStream.map((state) {
                      debugPrint(state.toString());
                      return state.playing;
                    }).distinct(),
                    builder: (context, snapshot) {
                      final playing = snapshot.data ?? false;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (playing) pauseButton() else playButton(),
                          stopButton(),
                          IconButton(
                            icon: Icon(Icons.ac_unit),
                            iconSize: 64.0,
                            onPressed: () async {
                              debugPrint('onPressed setSpeed to 2.5');
                              playerService.setSpeed(2.5);
                            },
                          )
                        ],
                      );
                    },
                  ),
                  // A seek bar.
                  StreamBuilder<MediaState>(
                    stream: _mediaStateStream,
                    builder: (context, snapshot) {
                      final mediaState = snapshot.data;
                      return SeekBar(
                        duration: mediaState?.mediaItem?.duration ?? Duration.zero,
                        position: mediaState?.position ?? Duration.zero,
                        onChangeEnd: (newPosition) {
                          playerService.seekTo(newPosition);
                        },
                      );
                    },
                  ),
                  StreamBuilder<bool>(
                    stream: playerService.notificationClickEventStream,
                    builder: (context, snapshot) {
                      return Text(
                        'Notification Click Status: ${snapshot.data}',
                      );
                    },
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Stream<MediaState> get _mediaStateStream => Rx.combineLatest2<PlayerItem, Duration, MediaState>(
      playerService.currentMediaItemStream,
      playerService.positionStream,
      (mediaItem, position) => MediaState(mediaItem, position));

  Stream<PlayerQueueState> get _queueStateStream => Rx.combineLatest2<List<PlayerItem>, PlayerItem, PlayerQueueState>(
        playerService.queueStream,
        playerService.currentMediaItemStream,
        (queue, mediaItem) {
          return PlayerQueueState(queue, mediaItem);
        },
      );

  RaisedButton audioPlayerButton() => startButton(
        'AudioPlayer',
        () {
          playerService.init(audioPlayerTaskEntrypoint);
        },
      );

  RaisedButton textToSpeechButton() => startButton(
        'TextToSpeech',
        () {
          playerService.init(textToSpeechTaskEntrypoint);
        },
      );

  RaisedButton downloadFileButton() => RaisedButton(
        child: Text('Downloadz'),
        onPressed: () async {
          WidgetsFlutterBinding.ensureInitialized();
          Directory documents = await getApplicationDocumentsDirectory();

          final saveDirPath = documents.path + Platform.pathSeparator;

          final taskId = await FlutterDownloader.enqueue(
            url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
            savedDir: saveDirPath,
          );

          await Future<void>.delayed(Duration(milliseconds: 4000));

          final tasks = await FlutterDownloader.loadTasksWithRawQuery(query: 'SELECT * FROM task');
          final lastTask = tasks.last;
          final filePath = '${lastTask.savedDir}${Platform.pathSeparator}${lastTask.filename}';
          debugPrint('saveTask has downloaded the file into: ' + filePath);

          final saveDir = Directory(saveDirPath);
          final downloadedFilePath = File('${saveDir.path}SoundHelix-Song-3.mp3');

          debugPrint('constructed file path: $downloadedFilePath');

          // playerService.start(
          //   backgroundTaskEntrypoint: audioPlayerTaskEntrypoint,
          //   androidNotificationChannelName: 'Audio Service Demo',
          //   // Enable this if you want the Android service to exit the foreground state on pause.
          //   //androidStopForegroundOnPause: true,
          //   androidNotificationColor: 0xFF2196f3,
          //   androidNotificationIcon: 'mipmap/ic_launcher',
          //   androidEnableQueue: true,
          // );
        },
      );

  RaisedButton betterDownloadFileButton() => RaisedButton(
        child: Text('DownloadService.enqueue'),
        onPressed: () async {
          debugPrint('flutter_downloader started');
          final stopwatch = Stopwatch()..start();

          final stateStream =
              await downloadService.enqueue('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3');
          StreamSubscription subscription;
          subscription = stateStream.listen((event) async {
            debugPrint('${event.status} - ${event.progress} - ${event.filePath} - ${event.id}');
            if (event.status == DownloadTaskStatus.complete) {
              subscription.cancel();
              print('flutter_downloader -> ${stopwatch.elapsed}');
            }
          });
        },
      );

  RaisedButton dioDownloadFileButton() => RaisedButton(
        child: Text('Dio.download'),
        onPressed: () async {
          // final stateStream =
          //     await downloadService.enqueue('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3');

          final Dio _dio = Dio();
          // final isGranted = await _requestPermissions();
          final isGranted = true;
          if (isGranted) {
            final documentsDir = await getApplicationDocumentsDirectory();
            final savePath = documentsDir.path + Platform.pathSeparator + 'helix2.mp3';

            dioDownload([
              'https://redirector.googlevideo.com/videoplayback?expire=1611762303&ei=HzYRYPiGB8zo8wS1np6IDQ&ip=3.81.43.104&id=o-AMSlA6ItFTxhk1gcSlh0b2MO3t4TJ1M1Jwe5JQT1nKpL&itag=22&source=youtube&requiressl=yes&mh=nf&mm=31%2C26&mn=sn-p5qlsnsy%2Csn-t0a7ln7d&ms=au%2Conr&mv=u&mvi=1&pl=23&vprv=1&mime=video%2Fmp4&ns=byQgelbFN7NJoVPZtm8tWLcF&ratebypass=yes&dur=1545.589&lmt=1575960043200799&mt=1611740156&fvip=1&c=WEB&txp=5431432&n=wohtNFAAqefcp0QL4eRn&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRAIgd_whG9-aSnNDvAJaOnFuUVlmx7y8k2MteIpe04JwcnsCIGyu8mKZBYEKT1G7Z78hIRh-RP9qhN1pbuxgQ-0hAT3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl&lsig=AG3C_xAwRAIgHttI31i1GCuetm_UqgDId_G93B5PT_QBekZYEkzouN8CICVKSBvUqM4HVOc0XYdBmZlWUuVw5gw-co0wtC_GIF2i&title=Interj%C3%BA+Alf%C3%B6ldi+R%C3%B3berttel',
              savePath
            ]);

            // compute(dioDownload, [
            //   'https://redirector.googlevideo.com/videoplayback?expire=1611762303&ei=HzYRYPiGB8zo8wS1np6IDQ&ip=3.81.43.104&id=o-AMSlA6ItFTxhk1gcSlh0b2MO3t4TJ1M1Jwe5JQT1nKpL&itag=22&source=youtube&requiressl=yes&mh=nf&mm=31%2C26&mn=sn-p5qlsnsy%2Csn-t0a7ln7d&ms=au%2Conr&mv=u&mvi=1&pl=23&vprv=1&mime=video%2Fmp4&ns=byQgelbFN7NJoVPZtm8tWLcF&ratebypass=yes&dur=1545.589&lmt=1575960043200799&mt=1611740156&fvip=1&c=WEB&txp=5431432&n=wohtNFAAqefcp0QL4eRn&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cvprv%2Cmime%2Cns%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRAIgd_whG9-aSnNDvAJaOnFuUVlmx7y8k2MteIpe04JwcnsCIGyu8mKZBYEKT1G7Z78hIRh-RP9qhN1pbuxgQ-0hAT3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl&lsig=AG3C_xAwRAIgHttI31i1GCuetm_UqgDId_G93B5PT_QBekZYEkzouN8CICVKSBvUqM4HVOc0XYdBmZlWUuVw5gw-co0wtC_GIF2i&title=Interj%C3%BA+Alf%C3%B6ldi+R%C3%B3berttel',
            //   savePath
            // ]);
          } else {
            debugPrint('storage permission not granted');
          }
        },
      );

  Future<bool> _requestPermissions() async {
    var isStoragePermissionGranted = await Permission.storage.isGranted;

    if (isStoragePermissionGranted) {
      await Permission.storage.request();
    }

    return Permission.storage.isGranted;
  }

  RaisedButton startButton(String label, VoidCallback onPressed) => RaisedButton(
        child: Text(label),
        onPressed: onPressed,
      );

  IconButton playButton() => IconButton(
        icon: Icon(Icons.play_arrow),
        iconSize: 64.0,
        onPressed: playerService.play,
      );

  IconButton pauseButton() => IconButton(
        icon: Icon(Icons.pause),
        iconSize: 64.0,
        onPressed: playerService.pause,
      );

  IconButton stopButton() => IconButton(
        icon: Icon(Icons.stop),
        iconSize: 64.0,
        onPressed: playerService.stop,
      );
}

Future dioDownload(List<String> args) async {
  debugPrint('dio.download started');
  final Dio _dio = Dio();
  final stopwatch = Stopwatch()..start();

  final resp = await _dio.download(
    args[0],
    args[1],
    onReceiveProgress: (received, total) {
      debugPrint('${(received / total * 100).toStringAsFixed(1)} %');
      // if (received == total) {}
    },
  );
  print('dio.download -> ${stopwatch.elapsed}');
  debugPrint(resp.toString());
}

class PlayerQueueState {
  final List<PlayerItem> queue;
  final PlayerItem currentlyPlayingItem;

  PlayerQueueState(this.queue, this.currentlyPlayingItem);
}

class MediaState {
  final PlayerItem mediaItem;
  final Duration position;

  MediaState(this.mediaItem, this.position);
}

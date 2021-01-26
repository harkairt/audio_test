import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_test/audio_player_task.dart';
import 'package:audio_service_test/downloader_main.dart';
import 'package:audio_service_test/player_service.dart';
import 'package:audio_service_test/seeker.dart';
import 'package:audio_service_test/text_to_speeck_task.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:rxdart/rxdart.dart';
import 'package:path_provider/path_provider.dart';

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

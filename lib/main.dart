import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_test/audio_player_task.dart';
import 'package:audio_service_test/downloader_main.dart';
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Service Demo'),
      ),
      body: Center(
        child: StreamBuilder<bool>(
          stream: AudioService.runningStream,
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
                  StreamBuilder<QueueState>(
                    stream: _queueStateStream,
                    builder: (context, snapshot) {
                      final queueState = snapshot.data;
                      final queue = queueState?.queue ?? [];
                      final mediaItem = queueState?.mediaItem;
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
                                  onPressed: mediaItem == queue.first ? null : AudioService.skipToPrevious,
                                ),
                                IconButton(
                                  icon: Icon(Icons.skip_next),
                                  iconSize: 64.0,
                                  onPressed: mediaItem == queue.last ? null : AudioService.skipToNext,
                                ),
                              ],
                            ),
                          if (mediaItem?.title != null) Text(mediaItem.title),
                        ],
                      );
                    },
                  ),
                  // Play/pause/stop buttons.
                  StreamBuilder<bool>(
                    stream: AudioService.playbackStateStream.map((state) => state.playing).distinct(),
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
                              AudioService.setSpeed(2.5);
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
                          AudioService.seekTo(newPosition);
                        },
                      );
                    },
                  ),
                  // Display the processing state.
                  StreamBuilder<AudioProcessingState>(
                    stream: AudioService.playbackStateStream.map((state) => state.processingState).distinct(),
                    builder: (context, snapshot) {
                      final processingState = snapshot.data ?? AudioProcessingState.none;
                      return Text("Processing state: ${describeEnum(processingState)}");
                    },
                  ),
                  // Display the latest custom event.
                  StreamBuilder(
                    stream: AudioService.customEventStream,
                    builder: (context, snapshot) {
                      return Text("custom event: ${snapshot.data}");
                    },
                  ),
                  // Display the notification click status.
                  StreamBuilder<bool>(
                    stream: AudioService.notificationClickEventStream,
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

  /// A stream reporting the combined state of the current media item and its
  /// current position.
  Stream<MediaState> get _mediaStateStream => Rx.combineLatest2<MediaItem, Duration, MediaState>(
      AudioService.currentMediaItemStream,
      AudioService.positionStream,
      (mediaItem, position) => MediaState(mediaItem, position));

  /// A stream reporting the combined state of the current queue and the current
  /// media item within that queue.
  Stream<QueueState> get _queueStateStream => Rx.combineLatest2<List<MediaItem>, MediaItem, QueueState>(
      AudioService.queueStream,
      AudioService.currentMediaItemStream,
      (queue, mediaItem) => QueueState(queue, mediaItem));

  RaisedButton audioPlayerButton() => startButton(
        'AudioPlayer',
        () {
          AudioService.start(
            backgroundTaskEntrypoint: audioPlayerTaskEntrypoint,
            androidNotificationChannelName: 'Audio Service Demo',
            // Enable this if you want the Android service to exit the foreground state on pause.
            //androidStopForegroundOnPause: true,
            androidNotificationColor: 0xFF2196f3,
            androidNotificationIcon: 'mipmap/ic_launcher',
            androidEnableQueue: true,
          );
        },
      );

  RaisedButton textToSpeechButton() => startButton(
        'TextToSpeech',
        () {
          AudioService.start(
            backgroundTaskEntrypoint: textToSpeechTaskEntrypoint,
            androidNotificationChannelName: 'Audio Service Demo',
            androidNotificationColor: 0xFF2196f3,
            androidNotificationIcon: 'mipmap/ic_launcher',
          );
        },
      );

  RaisedButton downloadFileButton() => RaisedButton(
        child: Text('Downloadz'),
        onPressed: () async {
          WidgetsFlutterBinding.ensureInitialized();
          Directory documents = await getApplicationDocumentsDirectory();

          debugPrint('documents.path ${documents.path}');
          final saveDirPath = Directory(documents.path + Platform.pathSeparator + 'DL');
          bool hasExisted = await saveDirPath.exists();
          if (!hasExisted) {
            await saveDirPath.create();
          }

          final taskId = await FlutterDownloader.enqueue(
            url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3',
            savedDir: saveDirPath.path,
            showNotification: false, // show download progress in status bar (for Android)
            openFileFromNotification: false, // click on notification to open downloaded file (for Android)
          );

          debugPrint(taskId);

          await Future<void>.delayed(Duration(milliseconds: 5000));

          final tasks = await FlutterDownloader.loadTasksWithRawQuery(query: 'SELECT * FROM task');
          // debugPrint('${tasks.last.toString()}');
          final lastTask = tasks.last;
          final filePath = '${lastTask.savedDir}${Platform.pathSeparator}${lastTask.filename}';
          debugPrint(filePath);
          // debugPrint('${tasks[0].savedDir}  -  ${tasks[0].filename}');
          // FlutterDownloader.open(taskId: taskId);

          // FlutterDownloader.registerCallback((String id, DownloadTaskStatus status, int progress) {
          //   final SendPort send = IsolateNameServer.lookupPortByName('downloader_send_port');
          //   send.send([id, status, progress]);
          // });
          AudioService.start(
            backgroundTaskEntrypoint: audioPlayerTaskEntrypoint,
            androidNotificationChannelName: 'Audio Service Demo',
            // Enable this if you want the Android service to exit the foreground state on pause.
            //androidStopForegroundOnPause: true,
            androidNotificationColor: 0xFF2196f3,
            androidNotificationIcon: 'mipmap/ic_launcher',
            androidEnableQueue: true,
          );
        },
      );

  RaisedButton startButton(String label, VoidCallback onPressed) => RaisedButton(
        child: Text(label),
        onPressed: onPressed,
      );

  IconButton playButton() => IconButton(
        icon: Icon(Icons.play_arrow),
        iconSize: 64.0,
        onPressed: AudioService.play,
      );

  IconButton pauseButton() => IconButton(
        icon: Icon(Icons.pause),
        iconSize: 64.0,
        onPressed: AudioService.pause,
      );

  IconButton stopButton() => IconButton(
        icon: Icon(Icons.stop),
        iconSize: 64.0,
        onPressed: AudioService.stop,
      );
}

class QueueState {
  final List<MediaItem> queue;
  final MediaItem mediaItem;

  QueueState(this.queue, this.mediaItem);
}

class MediaState {
  final MediaItem mediaItem;
  final Duration position;

  MediaState(this.mediaItem, this.position);
}

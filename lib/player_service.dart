import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PlayerService {
  PlayerService() {
    // init();
  }

  Future<void> init(Function entryPoint) {
    return AudioService.start(
      backgroundTaskEntrypoint: entryPoint,
      androidNotificationChannelName: 'Audio Service Demo',
      androidNotificationColor: 0xFF2196f3,
      androidNotificationIcon: 'mipmap/ic_launcher',
      androidEnableQueue: true,
    );
  }

  Future<void> skipToPrevious() {
    return AudioService.skipToPrevious();
  }

  Future<void> skipToNext() {
    return AudioService.skipToNext();
  }

  Future<void> setSpeed(double speed) {
    return AudioService.setSpeed(speed);
  }

  Future<void> seekTo(Duration position) {
    return AudioService.seekTo(position);
  }

  Future<void> play() {
    return AudioService.play();
  }

  Future<void> pause() {
    return AudioService.pause();
  }

  Future<void> stop() {
    return AudioService.stop();
  }

  Stream<Duration> get positionStream => AudioService.positionStream;
  Stream<bool> get isServiceRunningStream => AudioService.runningStream;
  Stream<bool> get notificationClickEventStream => AudioService.notificationClickEventStream;

  Stream<PlayerPlaybackState> get playerPlaybackStateStream =>
      AudioService.playbackStateStream.map(toPlayerPlaybackState);
  Stream<PlayerItem> get currentMediaItemStream {
    return AudioService.currentMediaItemStream.map(toPlayerItem);
  }

  Stream<List<PlayerItem>> get queueStream =>
      AudioService.queueStream.map((itemList) => itemList.map(toPlayerItem).toList());
}

class PlayerItem {
  PlayerItem({@required this.title, @required this.duration});

  final String title;
  final Duration duration;
}

class PlayerPlaybackState {
  PlayerPlaybackState({@required this.playing});

  final bool playing;
}

PlayerItem toPlayerItem(MediaItem item) {
  return PlayerItem(
    title: item.title,
    duration: item.duration,
  );
}

PlayerPlaybackState toPlayerPlaybackState(PlaybackState state) {
  return PlayerPlaybackState(playing: state.playing);
}

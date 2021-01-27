import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';



class DownloadService {
  DownloadService() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
    _port.listen((dynamic data) async {
      String id = data[0];
      DownloadTaskStatus status = data[1];
      int progress = data[2];
      String filePath = await _getFilePath(status, id);

      subject.add(DownloadState(id: id, status: status, progress: progress, filePath: filePath));
    });

    FlutterDownloader.registerCallback(downloadCallback);

    WidgetsFlutterBinding.ensureInitialized();

    taskInitialized = getApplicationDocumentsDirectory().then((value) {
      saveDirPath = value.path + Platform.pathSeparator;
    });
  }

  final BehaviorSubject<DownloadState> subject = BehaviorSubject<DownloadState>();
  final ReceivePort _port = ReceivePort();
  Future taskInitialized;
  String saveDirPath;

  Stream<DownloadState> get _stateStream => subject.stream;

  Future<Stream<DownloadState>> enqueue(String url) async {
    await taskInitialized;

    final taskId = await FlutterDownloader.enqueue(
      url: url,
      savedDir: saveDirPath,
    );

    return _stateStream.where((element) {
      return element.id == taskId;
    });
  }

  Future<String> _getFilePath(DownloadTaskStatus status, String taskId) async {
    if (status == DownloadTaskStatus.complete) {
      final tasks = await FlutterDownloader.loadTasksWithRawQuery(query: "SELECT * FROM task WHERE task_id='$taskId'");
      if (tasks.isNotEmpty) {
        return '$saveDirPath${tasks.last.filename}';
      }
    }

    return "BAJ VAN";
  }
}

void downloadCallback(String id, DownloadTaskStatus status, int progress) {
  final SendPort send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send.send([id, status, progress]);
}

class DownloadState {
  DownloadState({this.id, this.status, this.progress, this.filePath});

  final String id;
  final String filePath;
  final DownloadTaskStatus status;
  final int progress;
}

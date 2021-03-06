import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_uploader/flutter_uploader.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String title = "FileUpload Sample app";
const String uploadURL =
    "https://us-central1-flutteruploader.cloudfunctions.net/upload";

void main() => runApp(App());

class App extends StatefulWidget {
  final Widget child;

  App({Key key, this.child}) : super(key: key);

  _AppState createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: UploadScreen(),
    );
  }
}

class UploadItem {
  final String id;
  final String tag;
  final String path;
  final MediaType type;
  final String remoteHash;
  final int remoteSize;
  final int progress;
  final UploadTaskStatus status;

  UploadItem({
    this.id,
    this.tag,
    this.path,
    this.type,
    this.remoteHash,
    this.remoteSize,
    this.progress = 0,
    this.status = UploadTaskStatus.undefined,
  });

  UploadItem copyWith({
    UploadTaskStatus status,
    int progress,
    String remoteHash,
    int remoteSize,
  }) =>
      UploadItem(
        id: this.id,
        tag: this.tag,
        path: this.path,
        type: this.type,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        remoteHash: remoteHash ?? this.remoteHash,
        remoteSize: remoteSize ?? this.remoteSize,
      );

  bool isCompleted() =>
      this.status == UploadTaskStatus.canceled ||
      this.status == UploadTaskStatus.complete ||
      this.status == UploadTaskStatus.failed;
}

enum MediaType { Image, Video }

class UploadScreen extends StatefulWidget {
  UploadScreen({Key key}) : super(key: key);

  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  ImagePicker imagePicker = ImagePicker();
  FlutterUploader uploader = FlutterUploader();
  StreamSubscription _progressSubscription;
  StreamSubscription _resultSubscription;
  Map<String, UploadItem> _tasks = {};

  @override
  void initState() {
    super.initState();

    _progressSubscription = uploader.progress.listen((progress) {
      final task = _tasks[progress.tag];
      print("progress: ${progress.progress} , tag: ${progress.tag}");
      if (task == null) return;
      if (task.isCompleted()) return;
      setState(() {
        _tasks[progress.tag] =
            task.copyWith(progress: progress.progress, status: progress.status);
      });
    }, onError: (ex, stacktrace) {
      print("exception: $ex");
      print("stacktrace: $stacktrace" ?? "no stacktrace");
    });
    _resultSubscription = uploader.result.listen((result) {
      print(
          "id: ${result.taskId}, status: ${result.status}, response: ${result.response}, statusCode: ${result.statusCode}, tag: ${result.tag}, headers: ${result.headers}");

      final task = _tasks[result.tag];

      if (task == null) return;

      final responseJson = jsonDecode(result.response);

      setState(() {
        _tasks[result.tag] = task.copyWith(
          status: result.status,
          remoteHash: responseJson['md5'],
          remoteSize: responseJson['length'],
        );
      });
    }, onError: (ex, stacktrace) {
      print("exception: $ex");
      print("stacktrace: $stacktrace" ?? "no stacktrace");
      final exp = ex as UploadException;
      final task = _tasks[exp.tag];
      if (task == null) return;

      setState(() {
        _tasks[exp.tag] = task.copyWith(status: exp.status);
      });
    });

    imagePicker.getLostData().then((lostData) {
      if (lostData == null) {
        return;
      }

      if (lostData.type == RetrieveType.image) {
        _handleFileUpload(lostData.file, MediaType.Image);
      }
      if (lostData.type == RetrieveType.video) {
        _handleFileUpload(lostData.file, MediaType.Video);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _progressSubscription?.cancel();
    _resultSubscription?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugin example app'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Container(height: 20.0),
            Text(
              'multipart/form-data uploads',
              style: Theme.of(context).textTheme.subtitle1,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                RaisedButton(
                  onPressed: () => getImage(binary: false),
                  child: Text("upload image"),
                ),
                Container(width: 20.0),
                RaisedButton(
                  onPressed: () => getVideo(binary: false),
                  child: Text("upload video"),
                )
              ],
            ),
            Container(height: 20.0),
            Text(
              'binary uploads',
              style: Theme.of(context).textTheme.subtitle1,
            ),
            Text('this will upload selected files as binary'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                RaisedButton(
                  onPressed: () => getImage(binary: true),
                  child: Text("upload image"),
                ),
                Container(width: 20.0),
                RaisedButton(
                  onPressed: () => getVideo(binary: true),
                  child: Text("upload video"),
                )
              ],
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.all(20.0),
                itemCount: _tasks.length,
                itemBuilder: (context, index) {
                  final item = _tasks.values.elementAt(index);
                  print("${item.tag} - ${item.status}");
                  return UploadItemView(
                    item: item,
                    onCancel: cancelUpload,
                  );
                },
                separatorBuilder: (context, index) {
                  return Divider(
                    color: Colors.black,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future getImage({@required bool binary}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('binary', binary);

    var image = await imagePicker.getImage(source: ImageSource.gallery);

    if (image != null) {
      _handleFileUpload(image, MediaType.Image);
    }
  }

  Future getVideo({@required bool binary}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('binary', binary);

    var video = await imagePicker.getVideo(source: ImageSource.gallery);

    if (video != null) {
      _handleFileUpload(video, MediaType.Video);
    }
  }

  Future cancelUpload(String id) async {
    await uploader.cancel(taskId: id);
  }

  void _handleFileUpload(PickedFile file, MediaType mediaType) async {
    final prefs = await SharedPreferences.getInstance();
    final binary = prefs.getBool('binary') ?? false;

    final String filename = basename(file.path);
    final String savedDir = dirname(file.path);
    final tag = "image upload ${_tasks.length + 1}";

    final url = uploadURL + (binary ? '/binary' : '');
    var fileItem = FileItem(
      filename: filename,
      savedDir: savedDir,
      fieldname: "file",
    );

    var taskId = binary
        ? await uploader.enqueueBinary(
            url: url,
            file: fileItem,
            method: UploadMethod.POST,
            tag: tag,
            showNotification: true,
          )
        : await uploader.enqueue(
            url: url,
            data: {"name": "john"},
            files: [fileItem],
            method: UploadMethod.POST,
            tag: tag,
            showNotification: true,
          );

    setState(() {
      _tasks.putIfAbsent(
          tag,
          () => UploadItem(
                id: taskId,
                tag: tag,
                path: file.path,
                type: mediaType,
                status: UploadTaskStatus.enqueued,
              ));
    });
  }
}

typedef CancelUploadCallback = Future<void> Function(String id);

class UploadItemView extends StatelessWidget {
  final UploadItem item;
  final CancelUploadCallback onCancel;

  UploadItemView({
    Key key,
    this.item,
    this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final progress = item.progress.toDouble() / 100;
    final widget = item.status == UploadTaskStatus.running
        ? LinearProgressIndicator(value: progress)
        : Container();
    final buttonWidget = item.status == UploadTaskStatus.running
        ? Container(
            height: 50,
            width: 50,
            child: IconButton(
              icon: Icon(Icons.cancel),
              onPressed: () => onCancel(item.id),
            ),
          )
        : Container();
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(item.tag),
              Container(
                height: 5.0,
              ),
              Text(item.status.description),
              if (item.status == UploadTaskStatus.complete &&
                  item.remoteHash != null)
                Builder(builder: (context) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _compareMd5(item.path, item.remoteHash),
                      _compareSize(item.path, item.remoteSize),
                    ],
                  );
                }),
              Container(
                height: 5.0,
              ),
              widget
            ],
          ),
        ),
        buttonWidget
      ],
    );
  }

  Text _compareMd5(String localPath, String remoteHash) {
    var digest = md5.convert(File(localPath).readAsBytesSync());
    if (digest.toString().toLowerCase() == remoteHash) {
      return Text(
        'Hash $digest √',
        style: TextStyle(color: Colors.green),
      );
    } else {
      return Text(
        'Hash $digest vs $remoteHash ƒ',
        style: TextStyle(color: Colors.red),
      );
    }
  }

  Text _compareSize(String localPath, int remoteSize) {
    final length = File(localPath).lengthSync();
    if (length == remoteSize) {
      return Text(
        'Length $length √',
        style: TextStyle(color: Colors.green),
      );
    } else {
      return Text(
        'Length $length vs $remoteSize ƒ',
        style: TextStyle(color: Colors.red),
      );
    }
  }
}

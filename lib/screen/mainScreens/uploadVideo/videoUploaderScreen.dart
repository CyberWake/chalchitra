import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wowtalent/auth/auth_api.dart';
import 'package:wowtalent/database/firebase_provider.dart';
import 'package:path/path.dart' as p;
import 'package:wowtalent/screen/authentication/helpers/formFiledFormatting.dart';
import 'package:wowtalent/screen/mainScreens/uploadVideo/video_uploader_widget/encoding_provider.dart';
import '../../../model/video_info.dart';

class VideoUploader extends StatefulWidget {
  VideoUploader({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _VideoUploaderState createState() => _VideoUploaderState();
}

class _VideoUploaderState extends State<VideoUploader> {
  List<VideoInfo> _videos = <VideoInfo>[];
  bool _imagePickerActive = false;
  bool _processing = false;
  bool _canceled = false;
  double _progress = 0.0;
  int _videoDuration = 0;
  String _processPhase = '';
  double _fontOne;
  double _widthOne;
  Size _size;
  String videoName = "";
  final _formKey = GlobalKey<FormState>();
  UserAuth _userAuth = UserAuth();
  @override
  void initState() {
    UserVideoStore.listenToVideos((newVideos) {
      setState(() {
        _videos = newVideos;
      });
    });

    EncodingProvider.enableStatisticsCallback((int time,
        int size,
        double bitrate,
        double speed,
        int videoFrameNumber,
        double videoQuality,
        double videoFps) {
      if (_canceled) return;

      setState(() {
        _progress = time / _videoDuration;
      });
    });

    super.initState();
  }

  void _onUploadProgress(event) {
    if (event.type == StorageTaskEventType.progress) {
      final double progress =
          event.snapshot.bytesTransferred / event.snapshot.totalByteCount;
      setState(() {
        _progress = progress;
      });
    }
  }

  Future<String> _uploadFile(filePath, folderName, timestamp) async {
    final file = new File(filePath);
    final basename = p.basename(filePath);

    final StorageReference ref =
    FirebaseStorage.instance.ref().child(folderName).child(timestamp + basename);
    StorageUploadTask uploadTask = ref.putFile(file);
    uploadTask.events.listen(_onUploadProgress);
    StorageTaskSnapshot taskSnapshot = await uploadTask.onComplete;
    String videoUrl = await taskSnapshot.ref.getDownloadURL();
    return videoUrl;
  }

  String getFileExtension(String fileName) {
    final exploded = fileName.split('.');
    return exploded[exploded.length - 1];
  }

  void _updatePlaylistUrls(File file, String videoName) {
    final lines = file.readAsLinesSync();
    var updatedLines = List<String>();

    for (final String line in lines) {
      var updatedLine = line;
      if (line.contains('.ts') || line.contains('.m3u8')) {
        updatedLine = '$videoName%2F$line?alt=media';
      }
      updatedLines.add(updatedLine);
    }
    final updatedContents =
    updatedLines.reduce((value, element) => value + '\n' + element);

    file.writeAsStringSync(updatedContents);
  }

  Future<String> _uploadHLSFiles(dirPath, videoName, timestamp) async {
    final videosDir = Directory(dirPath);

    var playlistUrl = '';

    final files = videosDir.listSync();
    int i = 1;
    for (FileSystemEntity file in files) {
      final fileName = p.basename(file.path);
      final fileExtension = getFileExtension(fileName);
      if (fileExtension == 'm3u8') _updatePlaylistUrls(file, videoName + timestamp);

      setState(() {
        _processPhase = 'Uploading video file $i out of ${files.length}';
        _progress = 0.0;
      });

      final downloadUrl = await _uploadFile(file.path, videoName + timestamp, "");

      if (fileName == 'master.m3u8') {
        playlistUrl = downloadUrl;
      }
      i++;
    }

    return playlistUrl;
  }

  createAlertDialogue(BuildContext context, String message) {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text("Warning"),
            content: Text(message),
            actions: [
              FlatButton(
                child: Text("Ok"),
                onPressed: () {
                  Navigator.pop(context);
                },
              )
            ],
          );
        });
  }

  Future<void> _processVideo(File rawVideoFile) async {
    print("processing");
    final Directory extDir = await getApplicationDocumentsDirectory();
    final outDirPath = '${extDir.path}/Videos/$videoName';
    final videosDir = new Directory(outDirPath);
    videosDir.createSync(recursive: true);

    final rawVideoPath = rawVideoFile.path;
    final copyPath = '$outDirPath/copy.mp4';
    File(rawVideoPath).copySync(copyPath);
    final info = await EncodingProvider.getMediaInformation(rawVideoPath);
    final aspectRatio = EncodingProvider.getAspectRatio(info);
    print("printing Information ==================================>");
    print(info['streams'][0]['width']);
    print(info['streams'][0]['height']);
    final thumbWidth = info['streams'][0]['width'];
    final thumbHeight = info['streams'][0]['height'];

    setState(() {
      _processPhase = 'Generating thumbnail';
      _videoDuration = EncodingProvider.getDuration(info);
      print(_videoDuration);
      _progress = 0.0;
    });

    if (_videoDuration < 90000) {
      createAlertDialogue(context, "Video Can't be less than 90 seconds");
      print("video duration exceed");
      return null;
    }

    if ( _videoDuration > 300000) {
      createAlertDialogue(context, "Video Can't be more than 300 seconds");
      print("video duration exceed");
      return null;
    }

    final thumbFilePath = await EncodingProvider.getThumb(
        copyPath, outDirPath, thumbWidth, thumbHeight);

    setState(() {
      _processPhase = 'Encoding video';
      _progress = 0.0;
    });

    final encodedFilesDir =
    await EncodingProvider.encodeHLS(rawVideoPath, outDirPath);

    setState(() {
      _processPhase = 'Uploading thumbnail to firebase storage';
      _progress = 0.0;
    });
    int timestamp = DateTime.now().millisecondsSinceEpoch;
    final thumbUrl = await _uploadFile(thumbFilePath, 'thumbnail/' + _userAuth.user.uid, timestamp.toString());
    final videoUrl = await _uploadHLSFiles(encodedFilesDir, videoName, timestamp.toString());

    final videoInfo = VideoInfo(
      uploaderUid: UserAuth().user.uid,
      videoUrl: videoUrl,
      thumbUrl: thumbUrl,
      coverUrl: thumbUrl,
      aspectRatio: aspectRatio,
      uploadedAt: timestamp,
      videoName: videoName,
      likes: 0,
      views: 0,
      rating: 0,
      comments: 0,
    );

    setState(() {
      _processPhase = 'Saving video metadata to cloud firestore';
      _progress = 0.0;
    });

    await UserVideoStore.saveVideo(videoInfo);

    setState(() {
      _processPhase = '';
      _progress = 0.0;
      _processing = false;
    });
  }

  void _takeVideo(context, source) async {
    var videoFile;
    if (_imagePickerActive) return;

    _imagePickerActive = true;
    videoFile = await ImagePicker.pickVideo(
        source: source, maxDuration: const Duration(seconds: 300));
    _imagePickerActive = false;

    if (videoFile == null) return;
    setState(() {
      _processing = true;
    });

    try {
      await _processVideo(videoFile);
    } catch (e) {
      print("error" + '${e.toString()}');
    } finally {
      setState(() {
        _processing = false;
      });
    }
  }

  _getProgressBar() {
    return Container(
      padding: EdgeInsets.all(30.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            margin: EdgeInsets.only(bottom: 30.0),
            child: Text(_processPhase),
          ),
          LinearProgressIndicator(
            value: _progress,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _size = MediaQuery.of(context).size;
    _fontOne = (_size.height * 0.015) / 11;
    _widthOne = _size.width * 0.0008;
    return Scaffold(
        body: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Center(
            child: _processing
                ? _getProgressBar()
                : Container(
              padding: EdgeInsets.all(50),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.15),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    )
                  ]),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    authFormFieldContainer(
                      child: TextFormField(
                        keyboardType: TextInputType.emailAddress,
                        validator: (val) => val.isEmpty || val.replaceAll(" ", '').isEmpty
                        ? "Video Title can't be Empty"
                            : null,
                        onChanged: (val) {
                          videoName = val;
                        },
                        decoration: authFormFieldFormatting(
                            hintText: "Enter Title",
                            fontSize: _fontOne * 15
                        ),
                        style: TextStyle(
                          fontSize: _fontOne * 15,
                        ),
                      ),
                      leftPadding: _widthOne * 20,
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).size.width/10,
                    ),
                    Text(
                      "Pick your Video",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(
                      height: 10.0,
                    ),
                    FlatButton(
                        onPressed: () {
                          if(_formKey.currentState.validate()){
                            _takeVideo(context, ImageSource.camera);
                          }
                        },
                        //minWidth: MediaQuery.of(context).size.width * 0.5,
                        shape: RoundedRectangleBorder(
                            side:
                            BorderSide(color: Colors.purple.withOpacity(0.5)),
                            borderRadius: BorderRadius.circular(5)),
                        child: _processing
                            ? CircularProgressIndicator(
                          valueColor: new AlwaysStoppedAnimation<Color>(
                              Colors.white),
                        )
                            : Text("Camera")),
                    FlatButton(
                        onPressed: () {
                          if(_formKey.currentState.validate()){
                            _takeVideo(context, ImageSource.gallery);
                          }
                        },
                        //minWidth: MediaQuery.of(context).size.width * 0.5,
                        shape: RoundedRectangleBorder(
                            side:
                            BorderSide(color: Colors.purple.withOpacity(0.5)),
                            borderRadius: BorderRadius.circular(5)),
                        child: _processing
                            ? CircularProgressIndicator(
                          valueColor: new AlwaysStoppedAnimation<Color>(
                              Colors.white),
                        )
                            : Text("Gallery")),
                  ],
                ),
              ),
            ),
          ),
        ));
  }
}
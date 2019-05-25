// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:multi_media_picker/multi_media_picker.dart';

import 'countdown_timer.dart';
import 'models.dart';
import 'storage.dart';
import 'user_model.dart';

List<CameraDescription> cameras;

String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

void logError(String code, String message) =>
    print('Error: $code\nError Message: $message');

class Camera extends StatefulWidget {
  final Dataset dataset;
  final String label;
  final String labelKey;
  final UserModel userModel;
  final bool isUploading;
  List<File> resultList;
  Camera(this.dataset, this.label, this.labelKey, this.userModel,
      this.isUploading);

  Future init() async {
    if (!isUploading) {
      try {
        cameras = await availableCameras();
      } on CameraException catch (e) {
        logError(e.code, e.description);
      }
    } else {
      resultList =
          await MultiMediaPicker.pickImages(source: ImageSource.gallery);
    }
  }

  @override
  _CameraState createState() {
    return _CameraState();
  }
}

class _CameraState extends State<Camera> {
  CameraController controller;
  String imagePath;
  String videoPath;
  VoidCallback videoPlayerListener;
  CountdownTimer timer;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    if (!widget.isUploading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (CameraDescription cameraDescription in cameras) {
          if (cameraDescription.lensDirection == CameraLensDirection.back)
            onNewCameraSelected(cameraDescription);
        }
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isUploading && widget.resultList != null) {
      widget.resultList
          .forEach((eachImage) => {uploadImageToStorage(eachImage.path)});
    }
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: Theme.of(context).accentColor,
        title: Text('Capture sample for ${widget.label}'),
      ),
      body: widget.isUploading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Text('Uploading Images in the background'),
                  MaterialButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text('OK'),
                  )
                ],
              ),
            )
          : Container(
              decoration: new BoxDecoration(color: Colors.black),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: Container(
                      child: Padding(
                        padding: const EdgeInsets.all(1.0),
                        child: Center(
                          child: _cameraPreviewWidget(),
                        ),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(
                          color: controller != null &&
                                  controller.value.isRecordingVideo
                              ? Colors.redAccent
                              : Colors.black45,
                          width: 2.0,
                        ),
                      ),
                    ),
                  ),
                  new CameraControlWidget(
                    controller: controller,
                    onRecordingStart: onVideoRecordButtonPressed,
                    onRecordingStop: onStopButtonPressed,
                    onPictureTaken: onTakePictureButtonPressed,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: <Widget>[
                        _thumbnailWidget(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    if (controller == null || !controller.value.isInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: CameraPreview(controller),
      );
    }
  }

  /// Display the thumbnail of the captured image or video.
  Widget _thumbnailWidget() {
    return Expanded(
      child: Align(
        alignment: Alignment.centerRight,
        child: imagePath == null
            ? null
            : SizedBox(
                child: Image.file(File(imagePath)),
                width: 64.0,
                height: 64.0,
              ),
      ),
    );
  }

  void showInSnackBar(String message) {
    _scaffoldKey.currentState.showSnackBar(SnackBar(content: Text(message)));
  }

  void onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller.dispose();
    }
    controller = CameraController(cameraDescription, ResolutionPreset.low);

    // If the controller is updated then update the UI.
    controller.addListener(() {
      if (mounted) setState(() {});
      if (controller.value.hasError) {
        showInSnackBar('Camera error ${controller.value.errorDescription}');
      }
    });

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      _showCameraException(e);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void onTakePictureButtonPressed() async {
    final filePath = await takePicture();
    uploadImageToStorage(filePath);
  }

  void onVideoRecordButtonPressed() {
    startVideoRecording().then((String filePath) {
      if (filePath == null) {
        logError("camera", "filepath is null. unable to save video");
        return;
      }
    });
  }

  // Saves the video and uploads it to firebase storage
  void onStopButtonPressed() {
    final storage = InheritedStorage.of(context).storage;

    stopVideoRecording().then((_) async {
      final File file = File(videoPath).absolute;
      final filename =
          new DateTime.now().millisecondsSinceEpoch.toString() + ".mp4";

      // build the path in storage: videos/dataset_name>/<dataset_label>/filename
      final StorageReference ref = storage
          .ref()
          .child('videos')
          .child(widget.dataset.name)
          .child(widget.label)
          .child(filename);

      // upload the file
      StorageUploadTask uploadTask = ref.putFile(
        file,
        StorageMetadata(
          customMetadata: <String, String>{
            'activity': 'videoUpload',
            'parent_key': widget.labelKey,
            'dataset_parent_key': widget.dataset.id,
            'uploader': widget.userModel.user.email,
          },
        ),
      );

      await uploadTask.onComplete;
    });

    showDialog<bool>(
            context: context,
            builder: (BuildContext context) => VideoProcessingDialog())
        .then((goBack) {
      if (goBack) {
        Navigator.pop(context);
      }
    });
  }

  Future<String> startVideoRecording() async {
    if (!controller.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    final Directory extDir = await getApplicationDocumentsDirectory();
    final String dirPath = '${extDir.path}/Movies/customimageclassifier';
    await Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.mp4';

    if (controller.value.isRecordingVideo) {
      // A recording is already started, do nothing.
      return null;
    }

    try {
      videoPath = filePath;
      await controller.startVideoRecording(filePath);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return filePath;
  }

  Future<void> stopVideoRecording() async {
    if (!controller.value.isRecordingVideo) {
      return null;
    }

    try {
      await controller.stopVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  Future<String> takePicture() async {
    if (!controller.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }
    final Directory extDir = await getApplicationDocumentsDirectory();
    final String dirPath = '${extDir.path}/Pictures/customimageclassifier';
    await Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.jpg';

    if (controller.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      await controller.takePicture(filePath);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return filePath;
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }

  void uploadImageToStorage(String filePath) async {
    final automlStorage = InheritedStorage.of(context).autoMlStorage;

    if (mounted) {
      setState(() {
        imagePath = filePath;
      });

      final filename =
          new DateTime.now().millisecondsSinceEpoch.toString() + '.jpg';

      // upload to storage and firestore
      final StorageReference ref = automlStorage
          .ref()
          .child('datasets')
          .child(widget.dataset.name)
          .child(widget.label)
          .child(filename);

      final File file = File(filePath).absolute;
      // upload the file
      StorageUploadTask uploadTask = ref.putFile(
        file,
        StorageMetadata(
          contentType: 'image/jpeg',
          customMetadata: <String, String>{'activity': 'imgUpload'},
        ),
      );

      final snapshot = await uploadTask.onComplete;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      Firestore.instance.collection('images').add({
        'parent_key': widget.labelKey,
        'dataset_parent_key': widget.dataset.id,
        'type': toString(SampleType
            .TRAIN), // newly created images are categorized as training.
        'filename': filename,
        'uploadPath':
            'datasets/${widget.dataset.name}/${widget.label}/$filename',
        'gcsURI': downloadUrl,
        'uploader': widget.userModel.user.email,
      });

      final labelRef =
          Firestore.instance.collection('labels').document(widget.labelKey);

      // increment count for the label
      await Firestore.instance.runTransaction((Transaction tx) async {
        DocumentSnapshot snapshot = await tx.get(labelRef);
        await tx.update(labelRef, <String, dynamic>{
          'total_images': snapshot.data['total_images'] + 1
        });
      });
    }
  }
}

/// Widget to control start / stop of camera
class CameraControlWidget extends StatefulWidget {
  final CameraController controller;
  final Function onRecordingStart;
  final Function onRecordingStop;
  final Function onPictureTaken;

  const CameraControlWidget(
      {Key key,
      this.controller,
      this.onRecordingStart,
      this.onRecordingStop,
      this.onPictureTaken})
      : super(key: key);

  @override
  _CameraControlWidgetState createState() => _CameraControlWidgetState();
}

class _CameraControlWidgetState extends State<CameraControlWidget> {
  CountdownTimer timer;

  bool isRecording() {
    return widget.controller != null &&
        widget.controller.value.isInitialized &&
        widget.controller.value.isRecordingVideo;
  }

  @override
  Widget build(BuildContext context) {
    final recordVideoButton = IconButton(
      icon: Icon(Icons.videocam),
      color: Theme.of(context).accentColor,
      iconSize: 40,
      onPressed: () {
        widget.onRecordingStart();

        setState(() {
          timer = CountdownTimer(Duration(seconds: 7), widget.onRecordingStop);
        });
      },
    );

    final takePictureButton = IconButton(
      icon: Icon(Icons.camera_alt),
      iconSize: 40,
      color: Theme.of(context).accentColor,
      onPressed: widget.onPictureTaken,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: MainAxisSize.max,
      children: isRecording()
          ? [
              new StreamBuilder(
                stream: timer,
                builder: (context, AsyncSnapshot<CountdownTimer> snapshot) {
                  if (snapshot.hasData) {
                    return Column(
                      children: <Widget>[
                        FlatButton(
                          child: Text("${snapshot.data.remaining.inSeconds}"),
                          color: Colors.red,
                          textColor: Colors.white,
                          onPressed: () {
                            widget.onRecordingStop();
                            timer.cancel();
                          },
                        ),
                        Text(
                          "For best results, make sure to capture from varying angles",
                          style: TextStyle(
                            color: Colors.white70,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      ],
                    );
                  }
                  return Container();
                },
              ),
            ]
          : [
              recordVideoButton,
              takePictureButton,
            ],
    );
  }
}

class VideoProcessingDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text('Processing Video'),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            "Your video is being processed and can be viewed in the samples page shortly",
          ),
        ),
        SimpleDialogOption(
          child: Center(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: FlatButton(
                    onPressed: () {
                      Navigator.pop(context, true);
                    },
                    child: Text(
                      "VIEW IMAGES",
                      style: TextStyle(
                        color: Theme.of(context).accentColor,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: RaisedButton(
                    onPressed: () {
                      Navigator.pop(context, false);
                    },
                    color: Theme.of(context).accentColor,
                    elevation: 4.0,
                    child: Text(
                      "TAKE ANOTHER",
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

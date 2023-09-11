
// This class manages the available cameras (back, front, and UVC) and handles the camera selection and video track retrieval.
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CameraManager {
  // A map to hold the names of the available cameras
  static const _cameraNames = {
    'back': 'Back camera',
    'front': 'Front camera',
    'uvc': 'UVC camera'
  };

  // A map to hold the available camera capturers
  final _cameras = <String, WebRTCVideoCapturer>{};
  String _selectedCamera = 'back';

  CameraManager() {
    _init();
  }

  // Initialization method to get the list of available cameras and store them in the _cameras map
  void _init() async {
    final availableCameras = await WebRTC.getCameras();
    for (final camera in availableCameras) {
      _cameras[camera.label] = camera;
    }
  }

  // Method to select a camera
  void selectCamera(String camera) {
    _selectedCamera = camera;
  }

  // Method to get the video track of the selected UVC camera
  Future<WebRTCVideoTrack> getUVCVideoTrack() async {
    if (_selectedCamera != 'uvc') {
      throw Exception("UVC camera is not selected");
    }
    final capturer = _cameras[_selectedCamera];
    return capturer.getTrack();
  }
}

// app_constants.dart
class AppConstants {
  // Bitrate constants
  static const int DEFAULT_BITRATE_720P = 6000;
  static const int DEFAULT_BITRATE_1080P = 10000;
  static const int MIN_BITRATE = 100;
  static const int MAX_BITRATE = 50000;
  
  // Video quality constants
  static const int VIDEO_WIDTH_720P = 1280;
  static const int VIDEO_HEIGHT_720P = 720;
  static const int VIDEO_WIDTH_1080P = 1920;
  static const int VIDEO_HEIGHT_1080P = 1080;
  static const int DEFAULT_FRAMERATE = 30;
  
  // Camera constants
  static const double MAX_ZOOM = 10.0;
  static const double MIN_ZOOM = 1.0;
  static const double ZOOM_SENSITIVITY = 0.1;
  
  // Connection constants
  static const int CONNECTION_TIMEOUT_MS = 30000;
  static const int RETRY_DELAY_MS = 2000;
  static const int MAX_CONNECTION_RETRIES = 3;
  
  // UI constants
  static const double BUTTON_MIN_WIDTH = 51.0;
  static const double BUTTON_PADDING = 15.0;
  static const double BUTTON_MIN_WIDTH_MIC = 60.0;
  
  // Performance constants
  static const int FPS_CHECK_INTERVAL_MS = 1000;
  static const int LOW_FPS_THRESHOLD = 20;
  static const int QUALITY_CHECK_INTERVAL_SECONDS = 2;
  
  // Default server addresses
  static const String DEFAULT_WSS_ADDRESS = 'wss://wss.vdo.ninja:443';
  static const String DEFAULT_TURN_SERVER = 'un;pw;turn:turn.x.co:3478';
  static const String DEFAULT_SALT = 'vdo.ninja';
  
  // Permissions
  static const List<String> REQUIRED_PERMISSIONS_ANDROID = [
    'android.permission.CAMERA',
    'android.permission.RECORD_AUDIO',
    'android.permission.INTERNET',
  ];
  
  static const List<String> SCREEN_SHARE_PERMISSIONS_ANDROID = [
    'android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION',
  ];
}
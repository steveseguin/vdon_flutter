// obs_state.dart
class OBSState {
  bool? visibility;
  bool? sourceActive;
  bool? recording;
  bool? streaming;
  bool? virtualcam;
  OBSDetails? details;
  
  OBSState({
    this.visibility,
    this.sourceActive,
    this.recording,
    this.streaming,
    this.virtualcam,
    this.details,
  });
  
  factory OBSState.fromMap(Map<String, dynamic> map) {
    return OBSState(
      visibility: map['visibility'],
      sourceActive: map['sourceActive'],
      recording: map['recording'],
      streaming: map['streaming'],
      virtualcam: map['virtualcam'],
      details: map['details'] != null ? OBSDetails.fromMap(map['details']) : null,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      if (visibility != null) 'visibility': visibility,
      if (sourceActive != null) 'sourceActive': sourceActive,
      if (recording != null) 'recording': recording,
      if (streaming != null) 'streaming': streaming,
      if (virtualcam != null) 'virtualcam': virtualcam,
      if (details != null) 'details': details!.toMap(),
    };
  }
}

class OBSDetails {
  int? controlLevel;
  String? currentSceneName;
  List<String>? scenes;
  
  OBSDetails({
    this.controlLevel,
    this.currentSceneName,
    this.scenes,
  });
  
  factory OBSDetails.fromMap(Map<String, dynamic> map) {
    String? sceneName;
    if (map['currentScene'] is Map && map['currentScene']['name'] != null) {
      sceneName = map['currentScene']['name'];
    }
    
    return OBSDetails(
      controlLevel: map['controlLevel'],
      currentSceneName: sceneName,
      scenes: map['scenes'] != null ? List<String>.from(map['scenes']) : null,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      if (controlLevel != null) 'controlLevel': controlLevel,
      if (currentSceneName != null) 'currentScene': {'name': currentSceneName},
      if (scenes != null) 'scenes': scenes,
    };
  }
}
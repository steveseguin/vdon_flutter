# Social Stream "dock" Label Configuration

## Changes Made

1. **Seed Message** - Added `'label': 'dock'` to identify ourselves correctly:
```dart
final seedMessage = {
  'request': 'seed',
  'streamID': _uuid,
  'room': config.sessionId,
  'view': true,
  'noaudio': true,
  'novideo': true,
  'label': 'dock',  // Important: Social Stream expects 'dock' label
};
```

2. **Video Added Announcement** - Added `'label': 'dock'` to the announcement:
```dart
final videoAddedMsg = {
  'request': 'videoaddedtoroom',
  'UUID': _uuid,
  'streamID': _uuid,
  'room': config.sessionId,
  'label': 'dock',  // Include dock label in announcement
};
```

3. **Info Message** - Changed app identifier from 'flutter_social_stream' to 'dock':
```dart
final infoMessage = {
  'info': {
    'label': 'dock',  // Must be 'dock' for Social Stream compatibility
    'version': '1.0.0',
    'platform': 'flutter',
    'flutter': true,
    'type': 'viewer',
    'uuid': _uuid,
  }
};
```

## Why "dock"?

Social Stream Ninja expects specific label values to identify different types of clients:
- `'dock'` - Chat overlay/dock clients that receive chat messages
- Other labels are used for different purposes (camera feeds, etc.)

The browser iframe code shows:
```javascript
const filename = "dock";
iframe.src = "https://vdo.socialstream.ninja/?...&label="+filename+"...";
```

## Message Format

Based on the browser code, chat messages come through in this format:
```javascript
{
  "dataReceived": {
    "overlayNinja": {
      "chatname": "Username",
      "chatmessage": "Message text",
      "type": "platform",
      // Optional fields:
      "chatimg": "avatar URL",
      "contentimg": "media URL",
      "hasDonation": "donation info"
    }
  }
}
```

## Current Support

The Flutter app now properly:
1. ✅ Identifies itself as 'dock' in all communications
2. ✅ Handles the dataReceived.overlayNinja message format
3. ✅ Creates data channels with label 'dock'
4. ✅ Sends heartbeat messages to keep connection alive
5. ✅ Responds to miniInfo status messages

## Testing

1. Connect to Social Stream session
2. Watch for successful WebRTC connection
3. Chat messages should now be received with format:
   - Wrapped in `dataReceived.overlayNinja`
   - Contains `chatname`, `chatmessage`, `type` fields
4. Messages should appear in the Flutter chat overlay
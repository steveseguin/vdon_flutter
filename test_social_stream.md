# Testing Social Stream WebRTC Integration

## Setup

1. **Browser Side (Publisher)**:
   - Open: https://socialstream.ninja/session/test123
   - This will be the chat publisher that sends messages

2. **Flutter App (Viewer)**:
   - Enable Social Stream in settings
   - Set mode to WebRTC
   - Set session ID to: test123
   - Start streaming

## Debug Steps

### 1. Initial Connection
Watch for these log messages in Flutter console:
```
[SocialStream-WebRTC] === JOINED ROOM SUCCESSFULLY ===
[SocialStream-WebRTC] === ROOM LISTING RECEIVED ===
[SocialStream-WebRTC] Our UUID: [generated UUID]
[SocialStream-WebRTC] Seeding as viewer
```

### 2. WebRTC Handshake
Look for:
```
[SocialStream-WebRTC] === OFFER RECEIVED ===
[SocialStream-WebRTC] Sending answer
[SocialStream-WebRTC] PCS WINS ICE (in browser)
[SocialStream-WebRTC] === PEER CONNECTION ESTABLISHED ===
```

### 3. Data Channel
Confirm data channel opens:
```
[SocialStream-WebRTC] === DATA CHANNEL OPENED ===
[SocialStream-WebRTC] Sent initial info message
[SocialStream-WebRTC] Started heartbeat timer
```

### 4. Message Flow
When sending chat messages from browser:
```
[SocialStream-WebRTC] === RAW DATA CHANNEL MESSAGE ===
[SocialStream-WebRTC] Message type: text
[SocialStream-WebRTC] Raw text: [message content]
```

## Keyboard Shortcuts (in Flutter app)

- **Ctrl+D**: Log all data channel states
- **Ctrl+T**: Send test message via data channel
- **Ctrl+S**: Show Social Stream connection status

## Troubleshooting

### "ICE DID NOT FIND A PC OPTION" Error
- Fixed by using `type: 'remote'` in ICE candidates
- Browser looks in `session.pcs[UUID]` for remote connections

### "RTC Connection seems to be dead" Error
- Fixed by sending heartbeat messages every 10 seconds
- Browser needs bidirectional communication to consider connection alive

### No Chat Messages Received
1. Check browser console for:
   - "successfully sent message via WebRTC"
   - NOT "sending message via WSS as WebRTC failed"

2. Check Flutter console for:
   - Raw data channel messages being logged
   - Message parsing attempts

### Connection Drops
- Heartbeat should keep connection alive
- Check for "Connection state: failed" messages
- Verify both sides are using same session ID

## Expected Message Formats

VDO.Ninja may send chat messages in these formats:

1. **Direct format**:
```json
{
  "chatname": "Username",
  "chatmessage": "Message text",
  "type": "platform"
}
```

2. **Wrapped in msg**:
```json
{
  "msg": {
    "chatname": "Username",
    "chatmessage": "Message text"
  }
}
```

3. **OverlayNinja format**:
```json
{
  "overlayNinja": {
    "chatname": "Username",
    "chatmessage": "Message text"
  }
}
```

4. **With session info**:
```json
{
  "msg": {...},
  "session": "sessionId",
  "UUID": "senderUUID"
}
```
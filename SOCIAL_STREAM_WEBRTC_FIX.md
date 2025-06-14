# Social Stream WebRTC Fix - Full VDO.Ninja Protocol

## Key Discovery
From the Social Stream Ninja source code, we discovered that it uses VDO.Ninja with specific parameters:

```javascript
iframe.src = "https://vdo.socialstream.ninja/?ln&salt=vdo.ninja&password=false&solo&view=SESSION&novideo&noaudio&label=dock&cleanoutput&room=SESSION"
```

## Changes Made

1. **Correct Server URL**: 
   - Changed from `wss://wss.socialstream.ninja:443` 
   - To: `wss://wss.vdo.socialstream.ninja:443`

2. **Proper Initial Seed Message**:
   ```json
   {
     "request": "seed",
     "streamID": "OUR_UUID",
     "room": "SESSION_ID",
     "salt": "vdo.ninja",
     "ln": true,
     "solo": true,
     "view": "SESSION_ID",
     "novideo": true,
     "noaudio": true,
     "label": "dock",
     "cleanoutput": true,
     "password": "false"
   }
   ```

3. **Fixed Message Format**:
   - Use `room` instead of `session` in all messages
   - Use `streamID` for our ID and `UUID` for target peer
   - Proper ICE candidate format

4. **Enhanced Message Handling**:
   - Handle seed confirmation
   - Support different peer list formats
   - Properly request to view peers

## Testing Steps

1. Make sure you're using the same session ID in both:
   - Flutter app: Set session ID to "stever"
   - Browser: https://socialstream.ninja/session/stever

2. Enable WebRTC mode in the Flutter app

3. Check the logs for:
   - "SEED CONFIRMED" - Shows we connected successfully
   - "PEER LIST RECEIVED" - Shows we got the room info
   - "Data channel opened" - Shows WebRTC connection established

## Expected Flow

1. Connect to `wss://wss.vdo.socialstream.ninja:443`
2. Send seed request with all parameters
3. Receive seed confirmation
4. Request room list
5. For each peer, request to view their stream
6. Receive WebRTC offer from peer
7. Create answer and establish data channel
8. Receive chat messages via data channel

## Debug Tips

If still not working:
- Check browser console for any errors on the Social Stream side
- Verify the session ID matches exactly
- Try refreshing both the browser and restarting the app
- Check firewall settings for WebRTC connections
# Social Stream WebRTC Debug Guide

## Current Issue
The Social Stream WebRTC connection is not receiving any messages from the server. The WebSocket connects but no signaling messages are received.

## Debug Steps Added

1. **Enhanced WebSocket Logging**:
   - Added WebSocket state logging
   - Added message type detection
   - Added close code/reason logging
   - Set cancelOnError to false

2. **Multiple Join Formats**:
   - First tries Social Stream format: `{'join': sessionId, 'out': 3, 'in': 4}`
   - Then tries VDO.Ninja format: `{'UUID': uuid, 'session': sessionId, 'request': 'joinroom'}`

3. **Response Handling**:
   - Checks for 'joined' field (Social Stream format)
   - Checks for 'joinedRoom' request (VDO.Ninja format)
   - Logs unknown message formats

## Things to Check

1. **Server Compatibility**:
   - Is `wss://wss.socialstream.ninja:443` the correct WebRTC server?
   - Does it expect a different protocol than VDO.Ninja?

2. **Authentication**:
   - Does the server require authentication?
   - Is the password field being used correctly?

3. **Protocol Version**:
   - The server might expect a specific protocol version
   - Try adding a version field to the join message

## Alternative Approaches

If WebRTC mode continues to fail:

1. **Use WebSocket Mode**: 
   - Already working in the app
   - Simpler but higher latency

2. **Check Browser Implementation**:
   - Open https://socialstream.ninja/session/stever in a browser
   - Check the network tab for WebSocket messages
   - Compare the message format

3. **Server-Side Logs**:
   - Check if the Social Stream server has logs
   - See if connections are being rejected

## Test Procedure

1. Enable Social Stream with WebRTC mode
2. Set session ID to "stever"
3. Run the app and check logs for:
   - "Raw WebSocket message received"
   - "JOINED ROOM" confirmation
   - Any error messages

4. If no messages are received:
   - The server might not support the WebRTC protocol
   - Try WebSocket mode instead
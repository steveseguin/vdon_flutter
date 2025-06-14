# Social Stream WebRTC Mode - VDO.Ninja Protocol Compliance

## Summary of Changes

I've updated the Social Stream WebRTC implementation to be fully compliant with the VDO.Ninja protocol. Here are the key changes:

### 1. UUID-based Identification
- Added `_uuid` field to identify our viewer connection (VDO.Ninja uses UUID for viewers, not streamID)
- Generate a proper 32-character hex UUID when connecting
- Use UUID in all signaling messages

### 2. Updated Connection Flow
The WebRTC connection now follows VDO.Ninja's viewer protocol:

1. **Join Room**: Send `joinroom` request with UUID and session
2. **Wait for Confirmation**: Handle `joinedRoom` response
3. **Request Peer List**: Send `list` request to get active peers
4. **Connect to Peers**: For each peer, send `play` request to view their stream
5. **Handle New Peers**: When `seed` messages arrive, request to view new peers

### 3. Proper Message Formatting
All signaling messages now include the correct fields:
- `UUID`: Our viewer UUID
- `session`: The room/session ID
- `streamID`: Target peer UUID (when applicable)
- `director`: false (we're not a director)

### 4. Data Channel Protocol
- Data channels use the label "dock" as required by Social Stream
- Added proper handling for VDO.Ninja's "msg" wrapper format
- Enhanced message parsing to handle various chat formats

### 5. ICE Candidate Handling
- ICE candidates now include session and streamID fields
- Improved pending ICE candidate management
- Better error handling for connection states

### 6. Removed Unused Code
- Commented out `_createOffer` method (viewers don't create offers)
- Removed unused imports and fields
- Cleaned up signaling message handling

## Testing Instructions

1. Enable Social Stream in the app settings
2. Set mode to "WebRTC" 
3. Enter the same session ID used in OBS/Browser source
4. The app should now properly connect and receive chat messages

## Debug Output

The implementation includes comprehensive debug logging:
- Connection steps are clearly labeled
- All signaling messages are logged
- Data channel messages show full parsing details
- Connection states and errors are tracked

## Next Steps if Issues Persist

If the WebRTC connection still shows errors:

1. Check the browser console for the Social Stream sender
2. Verify both sides are using the same session ID
3. Ensure firewall/NAT allows WebRTC connections
4. Try WebSocket mode as a fallback

The implementation now properly identifies as a viewer and follows the exact protocol used by VDO.Ninja web clients.
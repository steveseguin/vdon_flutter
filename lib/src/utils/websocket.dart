import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:async';
typedef void OnMessageCallback(dynamic msg);
typedef void OnCloseCallback(int code, String reason);
typedef void OnOpenCallback();
class SimpleWebSocket {
    var _socket;
    late OnOpenCallback onOpen;
    late OnMessageCallback onMessage;
    late OnCloseCallback onClose;
    SimpleWebSocket();
    JsonEncoder _encoder = JsonEncoder();
    
    connect(streamID, WSSADDRESS, UUID) async {
        print("CONNECTING");
        try {
            if (WSSADDRESS.startsWith("wss://")) {
                _socket = await WebSocket.connect(WSSADDRESS);
            } else {
                _socket = await WebSocket.connect("wss://"+WSSADDRESS);
            }
            
            var request = <String, dynamic>{};
            request["request"] = "seed";
            request["streamID"] = streamID;
            
            if (UUID.isNotEmpty) {
              request["from"] = UUID;
            }
            
            _socket.add(_encoder.convert(request));
            
            onOpen.call();
            _socket.listen((data) {
                onMessage.call(data);
            }, onDone: () {
                // Properly handle iOS background mode transitions
                if (Platform.isIOS) {
                  print('WebSocket closed, handling iOS background transition');
                  // Add a small delay to avoid immediate reconnection attempts
                  // that might occur during iOS app state transitions
                  Future.delayed(Duration(milliseconds: 500), () {
                    onClose.call(_socket.closeCode ?? 1000, _socket.closeReason ?? "Connection closed");
                  });
                } else {
                  onClose.call(_socket.closeCode ?? 1000, _socket.closeReason ?? "Connection closed");
                }
            });
        } on SocketException catch (e) {
            // Handle socket-related errors, e.g., network issues
            print('WebSocket connection failed (SocketException): ${e.toString()}');
            onClose.call(500, 'Network error');
        } on WebSocketException catch (e) {
            // Handle WebSocket-specific errors
            print('WebSocket connection failed (WebSocketException): ${e.toString()}');
            if (e.message.contains('(401)')) { 
              onClose.call(401, 'Unauthorized');
            } else {
              onClose.call(500, 'WebSocket error');
            }
        } on TimeoutException catch (e) {
            // Handle connection timeouts
            print('WebSocket connection timed out: ${e.toString()}');
            onClose.call(504, 'Connection timeout');
        } catch (e) {
            // Handle other unexpected errors
            print('WebSocket connection failed: ${e.toString()}');
            onClose.call(500, 'Unknown error');
        }
    }
    
    send(data) {
        if (_socket != null) {
            _socket.add(data);
            //print('send: $data');
        }
    }
    
    close([int code = 1000, String reason = 'Client closed']) {
        if (_socket != null) {
            try {
                _socket.close(code, reason);
            } catch (e) {
                print('Error closing WebSocket: $e');
            }
        }
    }
    
    Future<WebSocket> _connectForSelfSignedCert(url) async {
        try {
            Random r = new Random();
            String key = base64.encode(List<int>.generate(8, (_) => r.nextInt(255)));
            HttpClient client = HttpClient(context: SecurityContext());
            client.badCertificateCallback =
                    (X509Certificate cert, String host, int port) {
               // print('SimpleWebSocket: Allow self-signed certificate => $host:$port. ');
                return true;
            };
            HttpClientRequest request = await client.getUrl(Uri.parse(url)); // form the correct url here
            request.headers.add('Connection', 'Upgrade');
            request.headers.add('Upgrade', 'websocket');
            request.headers.add('Sec-WebSocket-Version', '13'); // insert the correct version here
            request.headers.add('Sec-WebSocket-Key', key.toLowerCase());
            HttpClientResponse response = await request.close();
            // ignore: close_sinks
            Socket socket = await response.detachSocket();
            var webSocket = WebSocket.fromUpgradedSocket(
                socket,
                protocol: 'signaling',
                serverSide: false,
            );
            return webSocket;
        } catch (e) {
            throw e;
        }
    }
}
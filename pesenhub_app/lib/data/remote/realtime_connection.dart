import 'package:web_socket_channel/web_socket_channel.dart';

abstract class RealtimeConnection {
  Stream<dynamic> get messages;
  Future<void> get ready;
  Future<void> close();
}

abstract class RealtimeConnectionFactory {
  RealtimeConnection connect(Uri uri);
}

class WebSocketRealtimeConnectionFactory implements RealtimeConnectionFactory {
  const WebSocketRealtimeConnectionFactory();

  @override
  RealtimeConnection connect(Uri uri) {
    return _WebSocketRealtimeConnection(WebSocketChannel.connect(uri));
  }
}

class _WebSocketRealtimeConnection implements RealtimeConnection {
  final WebSocketChannel _channel;

  _WebSocketRealtimeConnection(this._channel);

  @override
  Stream<dynamic> get messages => _channel.stream;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}

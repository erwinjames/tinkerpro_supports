import 'dart:typed_data';
import 'package:mysql_client_patched/mysql_protocol.dart';

class MySQLPacketEmptyPayload extends MySQLPacketPayload {
  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}

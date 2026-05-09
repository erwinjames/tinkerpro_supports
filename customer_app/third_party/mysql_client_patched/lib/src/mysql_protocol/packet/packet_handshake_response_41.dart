import 'dart:convert';
import 'dart:typed_data';
import 'package:buffer/buffer.dart';
import 'package:mysql_client_patched/mysql_protocol.dart';
import 'package:mysql_client_patched/mysql_protocol_extension.dart';

const _supportedCapabitilies = mysqlCapFlagClientProtocol41 |
    mysqlCapFlagClientSecureConnection |
    mysqlCapFlagClientPluginAuth |
    mysqlCapFlagClientPluginAuthLenEncClientData |
    mysqlCapFlagClientMultiStatements |
    mysqlCapFlagClientMultiResults;

class MySQLPacketHandshakeResponse41 extends MySQLPacketPayload {
  int capabilityFlags;
  int maxPacketSize;
  int characterSet;
  Uint8List authResponse;
  String authPluginName;
  String username;
  String? database;

  MySQLPacketHandshakeResponse41({
    required this.capabilityFlags,
    required this.maxPacketSize,
    required this.characterSet,
    required this.authResponse,
    required this.authPluginName,
    required this.username,
    this.database,
  });

  factory MySQLPacketHandshakeResponse41.createWithNativePassword({
    required String username,
    required String password,
    required MySQLPacketInitialHandshake initialHandshakePayload,
  }) {
    assert(initialHandshakePayload.authPluginDataPart2 != null);
    assert(initialHandshakePayload.authPluginName != null);

    final challenge = initialHandshakePayload.authPluginDataPart1 +
        initialHandshakePayload.authPluginDataPart2!.sublist(0, 12);

    assert(challenge.length == 20);

    final passwordBytes = utf8.encode(password);

    // [tinkerpro patch] Empty password → zero-length authResponse.
    // The MySQL/MariaDB native_password protocol says when the user
    // has no password, the client sends a zero-length string as the
    // auth response. Upstream mysql_client 0.0.27 instead sends
    // SHA1(empty) XORed with the challenge — a 20-byte non-empty
    // blob — and MariaDB rejects it as "Access denied … (using
    // password: YES)" because the server sees a non-empty response
    // and treats it as a wrong password. XAMPP / TinkerPro POS
    // installs ship with empty root password by default, so we need
    // this path to actually work.
    final Uint8List authData = passwordBytes.isEmpty
        ? Uint8List(0)
        : xor(
            sha1(passwordBytes),
            sha1(challenge + sha1(sha1(passwordBytes))),
          );

    return MySQLPacketHandshakeResponse41(
      capabilityFlags: _supportedCapabitilies,
      maxPacketSize: 50 * 1024 * 1024,
      authPluginName: initialHandshakePayload.authPluginName!,
      characterSet: initialHandshakePayload.charset,
      authResponse: authData,
      username: username,
    );
  }

  factory MySQLPacketHandshakeResponse41.createWithCachingSha2Password({
    required String username,
    required String password,
    required MySQLPacketInitialHandshake initialHandshakePayload,
  }) {
    final challenge = initialHandshakePayload.authPluginDataPart1 +
        initialHandshakePayload.authPluginDataPart2!.sublist(0, 12);

    assert(challenge.length == 20);

    final passwordBytes = utf8.encode(password);

    // [tinkerpro patch] Empty password → zero-length authResponse.
    // Same reasoning as the native_password path above.
    final Uint8List authData = passwordBytes.isEmpty
        ? Uint8List(0)
        : xor(
            sha256(passwordBytes),
            sha256(sha256(sha256(passwordBytes)) + challenge),
          );

    return MySQLPacketHandshakeResponse41(
      capabilityFlags: _supportedCapabitilies,
      maxPacketSize: 50 * 1024 * 1024,
      authPluginName: initialHandshakePayload.authPluginName!,
      characterSet: initialHandshakePayload.charset,
      authResponse: authData,
      username: username,
    );
  }

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);

    if (database != null) {
      capabilityFlags = capabilityFlags | mysqlCapFlagClientConnectWithDB;
    }

    buffer.writeUint32(capabilityFlags);
    buffer.writeUint32(maxPacketSize);
    buffer.writeUint8(characterSet);
    buffer.write(List.filled(23, 0));
    buffer.write(utf8.encode(username));
    buffer.writeUint8(0);

    if (capabilityFlags & mysqlCapFlagClientSecureConnection != 0) {
      buffer.writeVariableEncInt(authResponse.lengthInBytes);
      buffer.write(authResponse);
    }

    if (database != null &&
        capabilityFlags & mysqlCapFlagClientConnectWithDB != 0) {
      buffer.write(utf8.encode(database!));
      buffer.writeUint8(0);
    }

    if (capabilityFlags & mysqlCapFlagClientPluginAuth != 0) {
      buffer.write(utf8.encode(authPluginName));
      buffer.writeUint8(0);
    }

    return buffer.toBytes();
  }
}

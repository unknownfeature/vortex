import 'dart:typed_data';

import 'package:vortex/net/abstraction/message/types.dart';

abstract class Spec<MessageType, MessageId> {
  Function(Message<MessageType, MessageId>) get receiveSink;

  Function(Uint8List) get sendSink;

  int get messageWindowSeconds;

  MessagePart<MessageType, MessageId> Function(Uint8List packet) get partReader;

  Function(Message msg, Function(Uint8List) partConsumer) get messageWriter;
}



abstract class PacketSpec {
  (MessageType, int) type(Uint8List packet, int offset);

  (int, int) total(Uint8List packet, int offset);

  (int, int) index(Uint8List packet, int offset);

  (Uint8List, int) data(Uint8List packet, int offset);

  bool checksumMatched(Uint8List packet, Uint8List data, int offset);

  int maxParts();

  int maxDataLength();

  int checksumLength();
}

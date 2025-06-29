import 'dart:typed_data';

import 'package:vortex/net/abstraction/message/types.dart';

abstract class Spec<MessageType, MessageId> {
  Function(Message<MessageType, MessageId>) get receiveSink;

  Function(Uint8List) get sendSink;

  int get messageWindowSeconds;

  MessagePart<MessageType, MessageId> Function(Uint8List packet) get partReader;

  Function(Message msg, Function(Uint8List) partConsumer) get messageWriter;
}



import 'dart:collection';
import 'dart:core';
import 'dart:typed_data';
import 'package:vortex/net/abstraction/handler.dart';
import 'package:lru_memory_cache/lru_memory_cache.dart';
import 'dart:math';


int extractInt(Length length, ByteData data, int offset) {
  switch (numOfBytes) {
    case 8:
      return ByteData.sublistView(data, offset).getUint8(0);
    case 16:
      return ByteData.sublistView(data, offset).getUint16(0);
    case 32:
      return ByteData.sublistView(data, offset).getUint16(0);
  }
}

enum Size {
  _8,
  _16,
  _32,
  _64
}

extension SizeExtension on Size{
  int get bytes {
    return pow(2, this.index) as int;
  }

  int get bits {
    return 8 * this.bytes;
  }
  int extract(Uint8List data, int offset) {
    if (data.lengthInBytes < this.bytes) {
      throw Exception("not enough bytes to extract number");
    }
    switch (this) {
      case Size._8:
        return ByteData.sublistView(data).getUint8(offset);
      case Size._16:
        return ByteData.sublistView(data).getUint16(offset);
      case Size._32:
        return ByteData.sublistView(data).getUint32(offset);
      case Size._64:
        return ByteData.sublistView(data).getUint64(offset);
    }
  }

}

abstract class PacketSpec {
  Size sizeForLength();

  Size sizeForType();

  Size sizeForIndex();

  int maxMessageLength();

  int maxDataLength();
}


abstract class Message {
}

typedef MessageType = int;

class _PendingMessage {
  final Map<int, Uint8List> _parts = new HashMap();
  final int _totalSize;
  int _currentSize;
  final MessageType _type;

  static _PendingMessage? fromPacket(Uint8List packet, PacketSpec spec) {
    // if the packet is just header or less than header don't bother to read it
    if (packet.length <=
        spec.sizeForLength().bytes + spec.sizeForType().bytes + spec.sizeForIndex().bytes) {
      return null;
    }

    int length = spec.sizeForLength().extract(packet, 0);
    if (length < 0 || length > spec.maxMessageLength()) {
      return null; // should we throw an error? todo
    }

    int total = spec.si().extract(packet, 0);
    MessageType type = ByteData.sublistView(packet).getUint32(0);
  }
}

class MessageHandler implements Handler<Uint8List, Message> {

  final Handler<dynamic, Uint8List> _inner;
  bool _connected = false;
  final LRUMemoryCache<String, Set<Uint8List>> _cache

  @override
  Future<void> connect() {
    // TODO: implement connect
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> receive(In) {
    // TODO: implement receive
    throw UnimplementedError();
  }

  @override
  Future<void> send(Message out) {
    // TODO: implement send
    throw UnimplementedError();
  }

}
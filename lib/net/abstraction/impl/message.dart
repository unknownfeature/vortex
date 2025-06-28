import 'dart:collection';
import 'dart:core';
import 'dart:typed_data';
import 'package:vortex/net/abstraction/handler.dart';
import 'package:lru_memory_cache/lru_memory_cache.dart';
import 'dart:math';

enum Size { _8, _16, _32, _64 }

extension SizeExtension on Size {
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
  (MessageType, int) type(Uint8List packet, int offset);

  (int, int) total(Uint8List packet, int offset);

  (int, int) index(Uint8List packet, int offset);

  (Uint8List, int) data(Uint8List packet, int offset);

  bool checksumMatched(Uint8List packet, Uint8List data, int offset);

  int maxParts();

  int maxDataLength();

  int checksumLength();
}

class Message {
  final MessageType _type;
  final Uint8List _body;

  Message(this._type, this._body);

  MessageType get type => _type;

  Uint8List get body => _body;
}

typedef MessageType = int;

class _PendingMessage {
  final Map<int, Uint8List> _parts;
  final int _total;
  final MessageType _type;

  _PendingMessage(this._parts, this._total, this._type);

  static _PendingMessage fromPacket(
    Uint8List packet,
    PacketSpec spec,
    int currentOffset,
  ) {
    final MessageType type;
    final int total;
    final int index;
    final Uint8List data;

    int offset = currentOffset;
    (type, offset) = spec.type(packet, offset);
    if (type < 0) {
      throw Exception("invalid type $type");
    }

    (total, offset) = spec.total(packet, offset);

    if (total <= 0) {
      throw Exception("non positive total $total");
    }

    if (total > spec.maxParts()) {
      throw Exception("total $total greater than spec ${spec.maxParts()}");
    }
    (index, offset) = spec.index(packet, offset);
    if (index < 0) {
      throw Exception("negative index $index");
    }

    (data, offset) = spec.data(packet, offset);

    if (data.isEmpty || data.length > spec.maxDataLength()) {
      throw Exception("invalid data with length  ${data.length}");
    }
    if (!spec.checksumMatched(packet, data, offset)) {
      throw Exception("checksum didn't match");
    }

    final Map<int, Uint8List> parts = new HashMap();
    parts[index] = data;

    return new _PendingMessage(parts, total, type);
  }

  Message toMessage(){
    if (this._total != this._parts.length){
      throw Exception("message can't be assembled");
    }
    List<MapEntry<int, Uint8List>> sortedParts = _parts.entries.toList();
    sortedParts.sort((first, second) => first.key.compareTo(second.key));
    return Message(_type,sortedParts.map((me) => me.value).fold(Uint8List(), (prev, current) => prev..addAll(current)))
  }
}

class MessageHandler implements Handler<Uint8List, Message> {
  final PacketSpec _spec;
  final Handler<dynamic, Uint8List> _inner;
  bool _connected = false;
  final LRUMemoryCache<String, Set<Uint8List>> _cache;

  @override
  Future<void> connect() {
    // TODO: implement connect
    throw UnimplementedError();
  }

  @override
  Future<Message> receive(Uint8List received) {
    throw UnimplementedError();
  }

  @override
  Future<void> send(Message out) {
    // TODO: implement send
    throw UnimplementedError();
  }
}

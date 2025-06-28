import 'dart:collection';
import 'dart:core';
import 'dart:nativewrappers/_internal/vm/lib/internal_patch.dart';
import 'dart:typed_data';
import 'package:vortex/net/abstraction/handler.dart';
import 'dart:math';
import 'package:synchronized/synchronized.dart';
import '../../../utils/cache.dart';
import '../message/types.dart';

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

class _PendingMessage {
  final Map<int, Uint8List> _parts;
  final int _total;

  _PendingMessage._inner(this._parts, this._total);

  factory _PendingMessage.fromPart(Uint8List partBody, int index, int total) {
    if (index < 0 || total < 0) {
      throw Exception("invalid total or index: $total $index");
    }
    final Map<int, Uint8List> parts = new HashMap();
    parts[index] = partBody;
    return _PendingMessage._inner(parts, total);
  }

  bool addPart(Uint8List partBody, int index, int total) {
    if (total != this._total) {
      throw Exception("totals don't match $total ${this._total}");
    }
    if (index < 0) {
      throw Exception("invalid index $index");
    }

    if (partBody.isEmpty) {
      throw Exception("empty part");
    }
    Uint8List? currentPart = this._parts[index];
    if (currentPart != null && currentPart == partBody) {
      return false;
    }
    if (currentPart != null && currentPart != partBody) {
      throw Exception("got another part for the same message and index");
    }
    this._parts[index] = partBody;
    return true;
  }

  bool get canAssembleMessage => this._total == this._parts.length;

  Uint8List toMessageBody() {
    if (this._total != this._parts.length) {
      throw Exception(
        "not redy to construct the message, missing ${this._total - this._parts.length}",
      );
    }
    List<MapEntry<int, Uint8List>> sortedParts = _parts.entries.toList();
    sortedParts.sort((first, second) => first.key.compareTo(second.key));
    return sortedParts
        .map((me) => me.value)
        .fold(
      List.empty(growable: true) as Uint8List,
          (prev, current) => prev + current as Uint8List,
    );
  }
}

class MessageHandler<MessageType extends Comparable<MessageType>, MessageId extends Comparable<MessageId>>
    implements Handler<Uint8List, Message<MessageType, MessageId>> {
  final PacketSpec _spec;
  final Function(Message<MessageType, MessageId>) _receiveSink;
  final Function(Uint8List) _sendSink;
  final LRUCache<MessageKey<MessageType, MessageId>, _PendingMessage> _cache; // todo add expiry
  final MessagePart<MessageType, MessageId> Function(Uint8List packet)  _partReader;
  final void Function(Message msg, Function(Uint8List) partConsumer) _messageWriter;
  final Lock _lock = new Lock(reentrant: true);

  // bool _connected = false;

  @override
  Future<void> connect() async {
    // TODO: do we need anything here on this level?
  }

  @override
  Future<void> receive(Uint8List received) async {
    MessagePart<MessageType, MessageId> part = this._partReader(received);
    await this._lock.synchronized(() async {
      _PendingMessage pendingMessage = await this._cache.compute(part.key,  (k, v) {
        if (v == null) {
          v = _PendingMessage.fromPart(
            part.body,
            part.index,
            part.total,
          );
        } else {
          v.addPart(part.body, part.index, part.total);
        }
        return v;
      });

      if (pendingMessage.canAssembleMessage) {
        // todo make sure this operation is atomic
        Message<MessageType, MessageId> assembled = Message(
          part.key,
          pendingMessage.toMessageBody(),
        );
        this._receiveSink(assembled);
        this._cache.remove(part.key);
      }
    });
  }

  @override
  Future<void> send(Message<MessageType, MessageId> out) async {
    this._messageWriter(out, this._sendSink);
  }
}

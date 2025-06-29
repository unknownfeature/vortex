import 'dart:collection';
import 'dart:core';
import 'dart:typed_data';

import 'package:retry/retry.dart';
import 'package:vortex/net/abstraction/handler.dart';

import '../../../utils/cache.dart';
import 'types.dart';

class _PendingMessage {
  final Map<int, Uint8List> _parts;
  final int _total;

  _PendingMessage._inner(this._parts, this._total);

  factory _PendingMessage.fromPart(Uint8List partBody, int index, int total) {
    if (index < 0 || total < 0) {
      throw Exception("invalid total or index: $total $index");
    }
    final Map<int, Uint8List> parts = HashMap();
    parts[index] = partBody;
    return _PendingMessage._inner(parts, total);
  }

  _PendingMessage addPart(Uint8List partBody, int index, int total) {
    if (total != _total) {
      throw Exception("totals don't match $total $_total");
    }
    if (index < 0) {
      throw Exception("invalid index $index");
    }

    if (partBody.isEmpty) {
      throw Exception("empty part");
    }
    Uint8List? currentPart = _parts[index];
    if (currentPart != null && currentPart == partBody) {
      return this;
    }
    if (currentPart != null && currentPart != partBody) {
      throw Exception("got another part for the same message and index");
    }
    _parts[index] = partBody;
    return this;
  }

  bool get canAssembleMessage => _total == _parts.length;

  Uint8List assemble() {
    if (_total != _parts.length) {
      throw Exception("not ready to construct the message, missing ${_total - _parts.length}");
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

class MessageHandler<MessageType, MessageId>
    implements Handler<Uint8List, Message<MessageType, MessageId>> {
  final Function(Message<MessageType, MessageId>) _receiveSink;
  final Function(Uint8List) _sendSink;
  final LRUCache<MessageKey<MessageType, MessageId>, _PendingMessage> _cache;
  final  PartReader<MessageType, MessageId>  _partReader;
  final void Function(Message msg, Function(Uint8List) partConsumer) _messageWriter;

  MessageHandler._inner(
    this._receiveSink,
    this._sendSink,
    this._cache,
    this._partReader,
    this._messageWriter,
  );

  factory(HandlerSpec<MessageType, MessageId> spec) {
    return (
      spec.receiveSink,
      spec.sendSink,
      LRUCache(spec.messageWindowSeconds),
      spec.partReader,
      spec.messageWriter,
    );
  }

  @override
  Future<void> connect() async {
    // TODO: do we need anything here on this level?
  }

  @override
  Future<void> receive(Uint8List received) async {
    MessagePart<MessageType, MessageId> part = _partReader.read(received);

    _PendingMessage pendingMessage = await _cache.compute(
      part.messageKey,
      (k, v) => v == null
          ? _PendingMessage.fromPart(part.body, part.index, part.total)
          : v.addPart(part.body, part.index, part.total),
    );

    if (pendingMessage.canAssembleMessage) {
      await retry(() {
        Message<MessageType, MessageId> assembled = Message(
          part.messageKey,
          pendingMessage.assemble(),
        );
        _receiveSink(assembled);
        return _cache.remove(part.messageKey);
      }); // todo retry options
    }
  }

  @override
  Future<void> send(Message<MessageType, MessageId> out) async {
    _messageWriter(out, _sendSink);
  }
}

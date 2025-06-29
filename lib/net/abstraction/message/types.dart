import 'dart:typed_data';
import '../common/types.dart';


class Message<MessageType, MessageId> {
  final MessageKey<MessageType, MessageId> key;
  final Uint8List body;

  Message(this.key, this.body);
}

class MessageKey<MessageType, MessageId> {
  final MessageType type;
  final MessageId id;

  MessageKey(this.type, this.id);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MessageKey && other.type == this.type && other.id == this.id;
  }

  @override
  int get hashCode => Object.hash(this.type, this.id);
}

class MessagePart<MessageType, MessageId> {
  final int index;
  final int total;

  final MessageKey<MessageType, MessageId> messageKey;
  final Uint8List body;

  MessagePart(this.index, this.total, this.messageKey, this.body);
}

abstract class Checksum {
  int get length;

  Uint8List compute(Uint8List);
}

abstract class Converter<T> {
  T Function(Uint8List) get to;

  Uint8List Function(T) get from;

  Num get length;
}

abstract class Spec<MessageType, MessageId> {
  Num get total;

  Num get index;

  Checksum get checksum;

  int maxParts(MessageType);

  int get partSize;

  Converter<MessageId> get messageIdConverter;

  Converter<MessageType> get messageTypeConverter;
}

class PartReader<MessageType, MessageId> {
  final Spec _spec;

  PartReader(this._spec);

  Future<MessagePart<MessageType, MessageId>> read(Uint8List packet) async {
    int minLength =
        _spec.messageIdConverter.length.bytes +
        _spec.messageTypeConverter.length.bytes +
        _spec.total.bytes +
        _spec.index.bytes +
        _spec.checksum.length;
    if (minLength >= packet.length) {
      throw Exception("packet is too short");
    }
    int offset = 0;

    final int messageIdLength = _spec.messageIdConverter.length.read(packet.sublist(offset));
    offset += _spec.messageIdConverter.length.bytes;
    if (minLength + messageIdLength >= packet.length) {
      throw Exception("packet is too short");
    }

    final MessageId messageId = _spec.messageIdConverter.to(
      packet.sublist(offset, messageIdLength),
    );

    offset += messageIdLength;

    final int messageTypeLength = _spec.messageTypeConverter.length.read(
      packet.sublist(offset),
    );
    if (minLength + messageIdLength + messageTypeLength >= packet.length) {
      throw Exception("packet is too short");
    }
    offset += _spec.messageTypeConverter.length.bytes;

    final MessageType type = _spec.messageTypeConverter.to(
      packet.sublist(offset, messageTypeLength),
    );
    offset += messageTypeLength;

    final int total = _spec.total.read(packet.sublist(offset));
    offset += _spec.total.bytes;
    if (total > _spec.maxParts(type)) {
      throw Exception("too many parts");
    }
    if (total < 0) {
      throw Exception("total is negative");
    }
    final int index = _spec.index.read(packet.sublist(offset));
    offset += _spec.index.bytes;
    if (index < 0) {
      throw Exception("total is negative");
    }
    if (index >= total) {
      throw Exception("index should be less than total");
    }


    final Uint8List checksum = packet.sublist(offset, _spec.checksum.length);
    offset +=  _spec.checksum.length;
    final Uint8List data = packet.sublist(
      offset
    );
    if (_spec.checksum.compute(data) != checksum) {
      throw Exception("checksum doesn't match");
    }

    return MessagePart<MessageType, MessageId>(
      index,
      total,
      MessageKey<MessageType, MessageId>(type, messageId),
      data,
    );
  }
}

class MessageWriter<MessageType, MessageId> {
  final Spec _spec;

  MessageWriter(this._spec);

  Future<void> write(Message msg, Future<void> Function(Uint8List) partConsumer) async {
    Uint8List bytes = msg.body;
    if (bytes.isEmpty) {
      throw Exception("can't send empty message");
    }
    final int totalParts = (bytes.length / _spec.partSize).ceil();
    if (totalParts > _spec.maxParts(msg.key.type)) {
      throw Exception("message is too large");
    }
    int offset = 0;

    final List<Future<void>> futures = [];
    int counter = 0;
    while (offset < bytes.length) {
      int end = offset + _spec.partSize;
      if (end > bytes.length) {
        end = bytes.length;
      }
      Uint8List part = bytes.sublist(offset, end);
      futures.add(
        _assembleAndSubmitPart(
          MessagePart<MessageType, MessageId>(
            counter++,
            totalParts,
            MessageKey<MessageType, MessageId>(msg.key.type, msg.key.id),
            part,
          ),
          partConsumer,
        ),
      );
      offset = end;
    }
  }

  Future<void> _assembleAndSubmitPart(
    MessagePart<MessageType, MessageId> part,
      Future<void> Function(Uint8List) marshalledPartConsumer,
  ) async {
    final Uint8List marshalledId = _spec.messageIdConverter.from(part.messageKey.id);
    final int marshalledIdLength = marshalledId.length;
    final Uint8List marshalledType = _spec.messageTypeConverter.from(part.messageKey.type);
    final int marshalledTypeLength = marshalledType.length;
    final Uint8List partChecksum = _spec.checksum.compute(part.body);
    if (partChecksum.length != _spec.checksum.length){
      throw Exception("can't compute checksum");
    }

    List<int> result = _spec.messageIdConverter.length.write(marshalledIdLength);
    result += marshalledId;
    result += _spec.messageIdConverter.length.write(marshalledTypeLength);
    result += marshalledType;
    result += _spec.total.write(part.total);
    result += _spec.index.write(part.index);
    result += partChecksum;
    result += part.body;
    await marshalledPartConsumer(Uint8List.fromList(result));
  }
}

abstract class HandlerSpec<MessageType, MessageId> {
  int get messageWindowSeconds;

  PartReader<MessageType, MessageId> get partReader;

  MessageWriter<MessageType, MessageId> get messageWriter;
}

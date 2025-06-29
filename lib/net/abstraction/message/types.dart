import 'dart:math';
import 'dart:typed_data';

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

enum Size { _8, _16, _32, _64 }

extension SizeExtension on Size {
  int get bytes {
    return pow(2, index) as int;
  }

  int get bits {
    return 8 * bytes;
  }

  Uint8List writeUint(int number, [Endian endian = Endian.big]) {
    final byteData = ByteData(bytes);

    switch (this) {
      case Size._8:
        byteData.setUint8(0, number);
      case Size._16:
        byteData.setUint16(0, number, endian);
      case Size._32:
        byteData.setUint32(0, number, endian);
      case Size._64:
        byteData.setUint64(0, number, endian);
    }
    return byteData.buffer.asUint8List();
  }

  int readUint(Uint8List data, [Endian endian = Endian.big]) {
    if (data.lengthInBytes < bytes) {
      throw Exception("not enough bytes to extract number");
    }
    switch (this) {
      case Size._8:
        return ByteData.sublistView(data).getUint8(0);
      case Size._16:
        return ByteData.sublistView(data).getUint16(0, endian);
      case Size._32:
        return ByteData.sublistView(data).getUint32(0, endian);
      case Size._64:
        return ByteData.sublistView(data).getUint64(0, endian);
    }
  }
}

abstract class Converter<T> {
  T Function(Uint8List) get to;

  Uint8List Function(T) get from;

  Size get length;
}

abstract class PartReaderSpec<MessageType, MessageId> {
  Size get total;

  Size get index;

  int get checksumSize;

  int maxParts(MessageType);

  Function(Uint8List) get checksum;

  Converter<MessageId> get messageIdConverter;

  Converter<MessageType> get messageTypeConverter;
}

class PartReader<MessageType, MessageId> {
  final PartReaderSpec _spec;

  PartReader(this._spec);

  MessagePart<MessageType, MessageId> read(Uint8List packet) {
    int minLength =
        _spec.messageIdConverter.length.bytes +
        _spec.messageTypeConverter.length.bytes +
        _spec.total.bytes +
        _spec.index.bytes +
        _spec.checksumSize;
    if (minLength >= packet.length) {
      throw Exception("packet is too short");
    }
    int offset = 0;

    final int messageIdLength = _spec.messageIdConverter.length.readUint(
      packet.sublist(offset),
    );
    offset += _spec.messageIdConverter.length.bytes;
    if (minLength + messageIdLength >= packet.length) {
      throw Exception("packet is too short");
    }

    final MessageId messageId = _spec.messageIdConverter.to(
      packet.sublist(offset, messageIdLength),
    );

    offset += messageIdLength;

    final int messageTypeLength = _spec.messageTypeConverter.length.readUint(
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

    final int total = _spec.total.readUint(packet.sublist(offset));
    offset += _spec.total.bytes;
    if (total > _spec.maxParts(type)) {
      throw Exception("too many parts");
    }
    if (total < 0) {
      throw Exception("total is negative");
    }
    final int index = _spec.index.readUint(packet.sublist(offset));
    offset += _spec.index.bytes;
    if (index < 0) {
      throw Exception("total is negative");
    }
    if (index >= total) {
      throw Exception("index should be less than total");
    }

    final Uint8List dataWithChecksum = packet.sublist(offset);
    final Uint8List data = dataWithChecksum.sublist(
      0,
      dataWithChecksum.length - _spec.checksumSize,
    );
    final Uint8List checksum = dataWithChecksum.sublist(data.length);
    if (_spec.checksum(data) != checksum) {
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

abstract class HandlerSpec<MessageType, MessageId> {
  Function(Message<MessageType, MessageId>) get receiveSink;

  Function(Uint8List) get sendSink;

  int get messageWindowSeconds;

  PartReader<MessageType, MessageId> get partReader;

  Function(Message msg, Function(Uint8List) partConsumer) get messageWriter;
}

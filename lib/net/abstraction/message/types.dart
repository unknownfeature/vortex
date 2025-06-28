import 'dart:typed_data';

class Message<
  MessageType extends Comparable<MessageType>,
  MessageId extends Comparable<MessageId>
> {
  final MessageKey<MessageType, MessageId> key;
  final Uint8List body;

  Message(this.key, this.body);
}

class MessageKey<
  MessageType extends Comparable<MessageType>,
  MessageId extends Comparable<MessageId>
> {
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

class MessagePart<
  MessageType extends Comparable<MessageType>,
  MessageId extends Comparable<MessageId>
> {
  final int index;
  final int total;

  final MessageKey<MessageType, MessageId> key;
  final Uint8List body;

  MessagePart._internal(this.index, this.total, this.key, this.body);
}


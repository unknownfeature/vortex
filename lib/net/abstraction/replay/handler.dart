import 'dart:core';
import 'dart:math';
import 'dart:typed_data';

import 'package:synchronized/synchronized.dart';
import 'package:vortex/net/abstraction/handler.dart';

import '../common/types.dart';

final _random = Random();
const int _maxStartSequence = 4_294_967_296;

enum PacketType { SYN, ACK, SYNACK, DATA }

class State {
  final ourSequence;
  final peerSequence;

  State(this.ourSequence, this.peerSequence);
}

extension Extension on PacketType {
  int _expectedSize() {
    switch (this) {
      case PacketType.SYN:
        return Num.uint64.bytes + Num.uint8.bytes;
      case PacketType.ACK:
        return Num.uint64.bytes + Num.uint8.bytes;
      case PacketType.SYNACK:
        return Num.uint64.bytes * 2 + Num.uint8.bytes;
      case PacketType.DATA:
        return -1;

    }
  }

  Future<void> handle(
    Uint8List dataWithPacketType,
    State state,
    Future<void> Function(State, [Uint8List?]) done,
  ) {
    final int expectedSize = _expectedSize();
    if (dataWithPacketType.length != expectedSize && expectedSize >= 0) {
      throw Exception("invalid packet length");
    }
    int receivedType = Num.uint8.read(dataWithPacketType);
    if (receivedType != index) {
      throw Exception("invalid packet type");
    }
    return _handle(dataWithPacketType.sublist(Num.uint8.bytes), state, done);
  }

  static from(State state) {
    if (state.ourSequence < 0) {
      return state.peerSequence < 0 ? PacketType.SYN : PacketType.SYNACK;
    }
    if (state.peerSequence < 0) {
      return PacketType.ACK;
    }
    return PacketType.DATA;
  }

  Future<void> _handle(
    Uint8List data,
    State state,
    Future<void> Function(State, [Uint8List?]) done,
  ) async {
    switch (this) {
      case PacketType.SYN:
        int peersSequence = Num.uint64.read(data.sublist(0));

        if (peersSequence < 0 || peersSequence > _maxStartSequence) {
          throw Exception("invalid our sequence returned");
        }

        return await done(State(state.ourSequence, state.peerSequence));

      case PacketType.ACK:
        int increasedOurSequence = Num.uint64.read(data.sublist(0));

        if (increasedOurSequence != state.ourSequence + 1) {
          throw Exception("invalid our sequence returned");
        }
        return await done(State(increasedOurSequence, _random.nextInt(_maxStartSequence)));

      case PacketType.SYNACK:
        int increasedPeersSequence = Num.uint64.read(data.sublist(0));

        if (increasedPeersSequence <= state.peerSequence) {
          throw Exception("invalid our sequence returned");
        }

        int ourSequence = Num.uint64.read(data.sublist(Num.uint64.bytes));

        if (ourSequence < 0 || ourSequence > _maxStartSequence) {
          throw Exception("invalid invalid our sequence");
        }
        return await done(State(ourSequence, increasedPeersSequence));

      case PacketType.DATA:
        int peerSequence = Num.uint64.read(data.sublist(Num.uint64.bytes));
        if (peerSequence <= state.peerSequence) {
          throw Exception("invalid sequence");
        }
        return await done(State(state.ourSequence, peerSequence), data.sublist(Num.uint64.bytes));

    }
  }
}

class ReplayHandler extends Handler<Uint8List, Uint8List> {
  State _state = State(-1, -1);

  final Lock _lock = Lock(reentrant: false);

  @override
  Future<void> receive(Uint8List received, Chain<Uint8List, Uint8List> chain) async {
    return await _lock.synchronized(() async {
      PacketType packetType = Extension.from(_state);
      packetType.handle(received, _state, (newState, [data]) async {
        _state = newState;
        switch (packetType) {
          case PacketType.SYN:
            return await chain.send(
              Uint8List.fromList(
                Num.uint8.write(PacketType.ACK.index) + Num.uint64.write(_state.peerSequence),
              ),
            );
          case PacketType.ACK:
            return await chain.send(
              Uint8List.fromList(
                Num.uint8.write(PacketType.SYNACK.index) +
                    Num.uint64.write(_state.ourSequence) +
                    Num.uint64.write(_state.peerSequence),
              ),
            );

          case PacketType.DATA:
            return chain.receive(data);
          case PacketType.SYNACK:

          // do nothing
        }
      });
    });
  }

  @override
  Future<void> send(Uint8List out, Chain<Uint8List, Uint8List> chain) async {
    await _lock.synchronized(() async {
      if (_state.ourSequence < 0 && _state.peerSequence < 0) {
        int ourSequence = _random.nextInt(_maxStartSequence);
        List<int> packet = Num.uint8.write(PacketType.SYN.index);
        packet += Num.uint64.write(ourSequence);
        _state = State(ourSequence, _state.peerSequence);
        return await chain.send(Uint8List.fromList(packet));
      } else if (_state.ourSequence < 0 || _state.peerSequence < 0) {
        throw Exception("connection in progress");
      }

      _state = State(_state.ourSequence + 1, _state.peerSequence);
      // todo should we retry?
      return await chain.send(
        Uint8List.fromList(
          Num.uint8.write(PacketType.DATA.index) + Num.uint64.write(_state.ourSequence) + out,
        ),
      );
    });
  }

}

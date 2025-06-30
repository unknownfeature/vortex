import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_sodium/flutter_sodium.dart'; // Or another relevant package
import 'package:hashlib/hashlib.dart';
import 'package:secp256k1/secp256k1.dart';
import 'package:synchronized/synchronized.dart';
import 'package:vortex/net/abstraction/impl/secure/types.dart';

import '../../handler.dart';

class SecureHandler extends Handler<Uint8List, Uint8List> {
  late final PrivateKey _ourKey;
  late final Encrypter? _cipher;
  final Lock _lock = Lock(reentrant: true);

  SecureHandler() {
    _ourKey = PrivateKey(randomBigInt(256, N));
  }

  @override
  Future<void> receive(Uint8List received, Chain<Uint8List, Uint8List> chain) async {
    if (_cipher == null) {
      // expecting connection request here
      if (received.length != messageSize * 4) {
        throw Exception("invalid message");
      }
      int offset = 0;
      Uint8List peersPubKey = received.sublist(offset, offset + messageSize * 2);
      offset += messageSize * 2;
      Uint8List nonce = received.sublist(offset, offset + messageSize);
      offset += messageSize;
      Uint8List r = received.sublist(offset, offset + messageSize);
      offset += messageSize;
      Uint8List s = received.sublist(offset, offset + messageSize);
      Signature sgn = Signature.fromHexes(
        hex.encode(r).padLeft(messageSize * 2, '0'),
        hex.encode(s).padLeft(messageSize * 2, '0'),
      );
      PublicKey pubK = PublicKey.fromHex(hex.encode(peersPubKey));
      Uint8List hash = keccak256.convert(peersPubKey + nonce).bytes;
      if (sgn.verify(pubK, bytesToHexPadded(hash))) {
        throw Exception("invalid signature");
      }
      Uint8List secret = ScalarMult.computeSharedSecret(
        Uint8List.fromList(hex.decode(_ourKey.toHex())),
        peersPubKey,
      );
      await _lock.synchronized(() {
        _cipher = Encrypter(
          AES(Key.fromBase16(bytesToHexPadded(secret)), mode: AESMode.ecb),
        );
      });

      return await chain.send(_handshakeMsg());
    }
    await chain.receive(_cipher.decryptBytes(Encrypted.fromBase16(hex.encode(received))));
  }

  @override
  Future<void> send(Uint8List out, Chain<Uint8List, Uint8List> chain) async {
    if (_cipher == null) {
      throw Exception("not connected");
    }
    await chain.send(_cipher.encryptBytes(out).bytes);
  }

  Uint8List _handshakeMsg() {
    List<int> msg =
        hex.decode(bigIntToHexPadded(_ourKey.publicKey.X)) +
        hex.decode(bigIntToHexPadded(_ourKey.publicKey.Y)) +
        hex.decode(bigIntToHexPadded(randomBigInt(256, N)));
    Uint8List hash = keccak256.convert(msg).bytes;
    Signature sgn = _ourKey.signature(hex.encode(hash));
    List<int> signatureBytes = hex.decode(sgn.toRawHex());
    return Uint8List.fromList(msg + signatureBytes);
  }


  @override
  Future<void> connect(Chain<Uint8List, Uint8List> chain) async {
    await chain.connect();
    await chain.send(_handshakeMsg());
  }

  @override
  Future<void> disconnect(Chain<Uint8List, Uint8List> chain) async {
    await _lock.synchronized(() => _cipher = null);

    await chain.disconnect();
  }
}

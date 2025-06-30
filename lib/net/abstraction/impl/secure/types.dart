import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';

const int messageSize = 32;

final BigInt N = BigInt.parse(
  '115792089237316195423570985008687907852837564279074904382605163141518161494337',
  radix: 10,
);

String bigIntToHexPadded(BigInt bi, [int padTo = messageSize * 2, String padWith = '0']) =>
    bi.toRadixString(16).padLeft(padTo, padWith);


String bytesToHexPadded(Uint8List bytes, [int padTo = messageSize * 2, String padWith = '0']) =>
    hex.encode(bytes).padLeft(padTo, padWith);

Uint8List randomBytes(int bitLength) {
  final Random random = Random.secure();
  final BytesBuilder builder = BytesBuilder();

  // Generate random bytes
  for (var i = 0; i < bitLength ~/ 8; ++i) {
    // Adjust bitLength to bytes
    builder.addByte(random.nextInt(256));
  }

  final Uint8List bytes = builder.toBytes();
  return bytes;
}

BigInt randomBigInt(int bitLength, [BigInt? cap]) {
  Uint8List bytes = randomBytes(bitLength);

  while (cap != null && BigInt.parse(hex.encode(bytes), radix: 16) >= cap) {
    bytes = randomBytes(bitLength);
  }
  // Convert bytes to BigInt (assuming you have a decodeBigInt function from a library like pointycastle)
  // return decodeBigInt(bytes);

  // Alternative without pointycastle (deserialize BigInt from bytes)
  var bi = BigInt.zero;
  for (var byte in bytes.reversed) {
    bi <<= 8;
    bi |= BigInt.from(byte);
  }
  return bi;
}

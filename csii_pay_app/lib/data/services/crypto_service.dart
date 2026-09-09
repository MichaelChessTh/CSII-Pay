import 'dart:convert';
import 'package:crypto/crypto.dart';

final BigInt SECP256K1_P = BigInt.parse('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F', radix: 16);
final BigInt SECP256K1_N = BigInt.parse('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141', radix: 16);
final BigInt SECP256K1_GX = BigInt.parse('79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798', radix: 16);
final BigInt SECP256K1_GY = BigInt.parse('483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8', radix: 16);

class ECPoint {
  final BigInt x;
  final BigInt y;
  const ECPoint(this.x, this.y);
}

ECPoint? ecPointAdd(ECPoint? p1, ECPoint? p2) {
  if (p1 == null) return p2;
  if (p2 == null) return p1;
  final x1 = p1.x;
  final y1 = p1.y;
  final x2 = p2.x;
  final y2 = p2.y;

  BigInt m;
  if (x1 == x2) {
    if ((y1 + y2) % SECP256K1_P == BigInt.zero) return null;
    final num = (BigInt.from(3) * x1 * x1) % SECP256K1_P;
    final den = (BigInt.two * y1).modInverse(SECP256K1_P);
    m = (num * den) % SECP256K1_P;
  } else {
    final num = ((y2 - y1) % SECP256K1_P + SECP256K1_P) % SECP256K1_P;
    final den = ((x2 - x1) % SECP256K1_P + SECP256K1_P) % SECP256K1_P;
    m = (num * den.modInverse(SECP256K1_P)) % SECP256K1_P;
  }
  final x3 = ((m * m - x1 - x2) % SECP256K1_P + SECP256K1_P) % SECP256K1_P;
  final y3 = ((m * (x1 - x3) - y1) % SECP256K1_P + SECP256K1_P) % SECP256K1_P;
  return ECPoint(x3, y3);
}

ECPoint? ecPointMul(ECPoint pt, BigInt scalar) {
  var s = scalar % SECP256K1_N;
  ECPoint? result;
  ECPoint? addend = pt;
  while (s > BigInt.zero) {
    if ((s & BigInt.one) == BigInt.one) {
      result = ecPointAdd(result, addend);
    }
    addend = ecPointAdd(addend, addend);
    s >>= 1;
  }
  return result;
}

List<int> bigIntToBytes(BigInt number, int length) {
  var hex = number.toRadixString(16);
  if (hex.length % 2 != 0) hex = '0$hex';
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  while (bytes.length < length) {
    bytes.insert(0, 0);
  }
  return bytes.sublist(bytes.length - length);
}

BigInt bytesToBigInt(List<int> bytes) {
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return BigInt.parse(hex, radix: 16);
}

dynamic _normalizeValue(dynamic v) {
  if (v is num) {
    if (v == v.toInt()) {
      return v.toInt();
    }
    return v.toDouble();
  }
  if (v is Map) {
    final sorted = <String, dynamic>{};
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    for (final k in keys) {
      sorted[k] = _normalizeValue(v[k]);
    }
    return sorted;
  }
  if (v is List) {
    return v.map(_normalizeValue).toList();
  }
  return v;
}

List<int> computeCanonicalTxBytes(Map<String, dynamic> tx) {
  final rawTimestamp = tx['timestamp'];
  dynamic normTimestamp = 0;
  if (rawTimestamp is num) {
    normTimestamp = _normalizeValue(rawTimestamp);
  }
  final sortedMap = <String, dynamic>{
    'action': tx['action'],
    'nonce': (tx['nonce'] as num?)?.toInt() ?? 0,
    'payload': _normalizeValue(tx['payload'] ?? {}),
    'sender': tx['sender'],
    'timestamp': normTimestamp,
  };
  final serialized = jsonEncode(sortedMap);
  return utf8.encode(serialized);
}

String signTransactionPayload(Map<String, dynamic> tx, BigInt privkey) {
  final msgBytes = computeCanonicalTxBytes(tx);
  final msgHash = sha256.convert(msgBytes).bytes;

  // k = int.from_bytes(sha256(privkey.to_bytes(32) + msg_hash)) % (N - 1) + 1
  final privBytes = bigIntToBytes(privkey, 32);
  final kHash = sha256.convert(privBytes + msgHash).bytes;
  final k = (bytesToBigInt(kHash) % (SECP256K1_N - BigInt.one)) + BigInt.one;

  final G = ECPoint(SECP256K1_GX, SECP256K1_GY);
  final R = ecPointMul(G, k)!;
  final pub = ecPointMul(G, privkey)!;

  // e = int.from_bytes(sha256(Rx + Ry + Qx + Qy + msg_hash)) % N
  final eInput = bigIntToBytes(R.x, 32) +
      bigIntToBytes(R.y, 32) +
      bigIntToBytes(pub.x, 32) +
      bigIntToBytes(pub.y, 32) +
      msgHash;
  final eHash = sha256.convert(eInput).bytes;
  final e = bytesToBigInt(eHash) % SECP256K1_N;

  final s = (k + e * privkey) % SECP256K1_N;

  final RxHex = R.x.toRadixString(16).padLeft(64, '0');
  final RyHex = R.y.toRadixString(16).padLeft(64, '0');
  final sHex = s.toRadixString(16).padLeft(64, '0');
  return '$RxHex$RyHex$sHex';
}

String hashData(dynamic data) {
  String serialized;
  if (data is Map || data is List) {
    serialized = jsonEncode(_normalizeValue(data));
  } else {
    serialized = data.toString();
  }
  final bytes = utf8.encode(serialized);
  return sha256.convert(bytes).toString();
}

String randomHex(int bytes) {
  final rng = DateTime.now().microsecondsSinceEpoch.toString();
  return sha256.convert(utf8.encode(rng)).toString().substring(0, bytes * 2);
}

String generateTxId(String prefix) {
  return hashData('${prefix}_${DateTime.now().millisecondsSinceEpoch}_${randomHex(4)}');
}

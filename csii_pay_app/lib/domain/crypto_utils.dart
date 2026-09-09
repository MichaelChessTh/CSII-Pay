import 'dart:convert';

/// CSII-Pay QR payload format (PromptPay-style)
class QrPayload {
  final String accountId;
  final double? amount;
  final String? token;
  final String? note;

  const QrPayload({
    required this.accountId,
    this.amount,
    this.token,
    this.note,
  });

  factory QrPayload.fromJson(Map<String, dynamic> json) {
    return QrPayload(
      accountId: json['account'] as String,
      amount: json['amount'] != null ? (json['amount'] as num).toDouble() : null,
      token: json['token'] as String?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'csii_pay': '1',
        'account': accountId,
        if (amount != null) 'amount': amount,
        if (token != null) 'token': token,
        if (note != null) 'note': note,
      };

  String toJsonString() => jsonEncode(toJson());

  String toQrString() {
    final parts = <String>['csii_pay:$accountId'];
    if (amount != null) parts.add('amount=$amount');
    if (token != null) parts.add('token=$token');
    if (note != null) parts.add('note=$note');
    return parts.join('&');
  }

  static QrPayload? tryParse(String raw) {
    try {
      final trimmed = raw.trim();
      // Try JSON format first
      if (trimmed.startsWith('{')) {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic> && decoded.containsKey('account')) {
          return QrPayload.fromJson(decoded);
        }
      }
      // Try URI format: csii_pay:<account>&amount=...
      if (raw.startsWith('csii_pay:')) {
        final noPrefix = raw.substring('csii_pay:'.length);
        final parts = noPrefix.split('&');
        final accountId = parts[0];
        double? amount;
        String? token;
        String? note;
        for (final p in parts.skip(1)) {
          final kv = p.split('=');
          if (kv.length == 2) {
            if (kv[0] == 'amount') amount = double.tryParse(kv[1]);
            if (kv[0] == 'token') token = kv[1];
            if (kv[0] == 'note') note = kv[1];
          }
        }
        return QrPayload(accountId: accountId, amount: amount, token: token, note: note);
      }
      // Plain account ID
      if (raw.isNotEmpty && !raw.contains(' ')) {
        return QrPayload(accountId: raw);
      }
    } catch (_) {}
    return null;
  }
}

double calculateFee(String token, double amount) {
  if (amount <= 0) return 0.0;
  if (token == 'BDP') return double.parse((amount * 0.01).toStringAsFixed(6));
  if (token == 'CSP') {
    if (amount > 500.0) return double.parse((amount * 0.02).toStringAsFixed(6));
    if (amount > 150.0) return double.parse((amount * 0.01).toStringAsFixed(6));
    return 0.0;
  }
  return 0.0;
}

String feeLabel(String token, double amount) {
  if (token == 'BDP') return '1%';
  if (token == 'CSP') {
    if (amount > 500.0) return '2%';
    if (amount > 150.0) return '1%';
    return '0% (Free)';
  }
  return '0%';
}

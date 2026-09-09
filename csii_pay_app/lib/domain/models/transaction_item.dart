import 'package:flutter/material.dart';

class TransactionItem {
  final String txId;
  final String action;
  final String sender;
  final String? recipient;
  final String token;
  final double amount;
  final double fee;
  final String feeToken;
  final double timestamp;
  final int? blockIndex;
  final String status;
  final Map<String, dynamic> payload;

  TransactionItem({
    required this.txId,
    required this.action,
    required this.sender,
    this.recipient,
    required this.token,
    required this.amount,
    this.fee = 0.0,
    this.feeToken = 'CSP',
    required this.timestamp,
    this.blockIndex,
    this.status = 'CONFIRMED',
    this.payload = const {},
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem(
      txId: json['tx_id'] ?? json['hash'] ?? '',
      action: json['action'] ?? 'TRANSFER',
      sender: json['sender'] ?? '',
      recipient: json['recipient'],
      token: json['token'] ?? 'CSP',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      fee: (json['fee'] as num?)?.toDouble() ?? 0.0,
      feeToken: json['fee_token'] ?? 'CSP',
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
      blockIndex: json['block_index'] as int?,
      status: json['status'] ?? 'CONFIRMED',
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
    'tx_id': txId,
    'action': action,
    'sender': sender,
    'recipient': recipient,
    'token': token,
    'amount': amount,
    'fee': fee,
    'fee_token': feeToken,
    'timestamp': timestamp,
    'block_index': blockIndex,
    'status': status,
    'payload': payload,
  };

  DateTime get dateTime {
    if (timestamp <= 0) return DateTime.now();
    // Check if timestamp in seconds or milliseconds
    return timestamp > 2000000000
        ? DateTime.fromMillisecondsSinceEpoch(timestamp.toInt())
        : DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt());
  }

  bool isIncoming(String myAccount) {
    if (action == 'MARKETPLACE_CLAIM' && sender == myAccount) return true;
    if (action == 'POA_REWARD' && recipient == myAccount) return true;
    if (recipient == myAccount && sender != myAccount) return true;
    if (sender == myAccount) return false;
    return false;
  }

  bool isOutgoing(String myAccount) {
    if (action == 'MARKETPLACE_CLAIM' && sender == myAccount) return false;
    return sender == myAccount;
  }

  IconData get icon {
    switch (action) {
      case 'POA_REWARD':
        return Icons.military_tech_rounded;
      case 'ORDER_CREATE':
      case 'ORDER_FULFILL':
      case 'ORDER_CANCEL':
        return Icons.swap_horiz_rounded;
      case 'MARKETPLACE_CREATE':
        return Icons.work_outline_rounded;
      case 'MARKETPLACE_CLAIM':
        return Icons.verified_rounded;
      case 'ACCOUNT_REGISTER':
        return Icons.person_add_alt_1_rounded;
      case 'TRANSFER':
      default:
        return Icons.sync_alt_rounded;
    }
  }

  Color get iconColor {
    switch (action) {
      case 'POA_REWARD':
        return const Color(0xFFFFB300);
      case 'MARKETPLACE_CREATE':
        return const Color(0xFF6366F1);
      case 'MARKETPLACE_CLAIM':
        return const Color(0xFF10B981);
      case 'ORDER_CREATE':
      case 'ORDER_FULFILL':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF00E5FF);
    }
  }
}

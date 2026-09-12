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
    final payload = (json['payload'] as Map<String, dynamic>?) ?? {};
    final action = json['action'] ?? 'TRANSFER';
    String token = json['token'] ?? payload['token'] ?? payload['offer_token'] ?? payload['wage_token'] ?? 'CSP';
    double amount = (json['amount'] as num?)?.toDouble() ?? 0.0;
    String? recipient = json['recipient'] ?? payload['recipient'] ?? payload['maker'] ?? payload['worker'] ?? payload['account_id'];

    if (amount <= 0) {
      if (action == 'POA_REWARD') {
        token = 'CSP';
        amount = (payload['total_csp'] as num?)?.toDouble() ??
            (payload['base_reward_csp'] as num?)?.toDouble() ??
            (payload['amount'] as num?)?.toDouble() ??
            10.0;
      } else if (action == 'ACCOUNT_REGISTER') {
        token = 'BDP';
        amount = (payload['initial_bdp'] as num?)?.toDouble() ?? 100.0;
      } else if (action == 'ACCOUNT_VERIFY') {
        token = 'BDP';
        amount = payload['status'] == 'VERIFIED' ? 100.0 : 0.0;
      } else if (action == 'ORDER_CANCEL') {
        token = payload['offer_token'] ?? token;
        amount = (payload['offer_amount'] as num?)?.toDouble() ?? 0.0;
      } else if (action == 'ORDER_CREATE') {
        token = payload['offer_token'] ?? token;
        amount = (payload['offer_amount'] as num?)?.toDouble() ?? 0.0;
      } else if (action == 'ORDER_FULFILL') {
        token = payload['offer_token'] ?? payload['request_token'] ?? token;
        amount = (payload['take_offer'] as num?)?.toDouble() ??
            (payload['fill_amount'] as num?)?.toDouble() ??
            (payload['paid_request'] as num?)?.toDouble() ??
            0.0;
      }
    }

    return TransactionItem(
      txId: json['tx_id'] ?? json['hash'] ?? '',
      action: action,
      sender: json['sender'] ?? '',
      recipient: recipient,
      token: token,
      amount: amount,
      fee: (json['fee'] as num?)?.toDouble() ?? 0.0,
      feeToken: json['fee_token'] ?? 'CSP',
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
      blockIndex: json['block_index'] as int?,
      status: json['status'] ?? 'CONFIRMED',
      payload: payload,
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
    if (action == 'POA_REWARD') return true;
    if (action == 'ACCOUNT_REGISTER') return true;
    if (action == 'ACCOUNT_VERIFY') return true;
    if (action == 'ORDER_CANCEL' && sender == myAccount) return true;
    if (recipient == myAccount && sender != myAccount) return true;
    if (sender == myAccount) return false;
    return false;
  }

  bool isOutgoing(String myAccount) {
    if (action == 'POA_REWARD') return false;
    if (action == 'ACCOUNT_REGISTER') return false;
    if (action == 'ACCOUNT_VERIFY') return false;
    if (action == 'ORDER_CANCEL') return false;
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

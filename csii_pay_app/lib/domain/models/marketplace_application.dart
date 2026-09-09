class MarketplaceApplication {
  final String id;
  final String title;
  final String type; // 'student application' or 'faculty application'
  final String category; // 'social relations', 'business', 'programming', 'design', 'pitching', 'tech', 'personal'
  final String description;
  final String deadline;
  final int difficulty; // 1 to 5
  final String lineId;
  final double wage;
  final String wageToken; // 'CSP' or 'BDP'
  final String creatorAccountId;
  final String? creatorNickname;
  final String? secretCode; // 6-digit unique secret code
  final String? secretHash;
  final String status; // 'OPEN', 'COMPLETED', 'CANCELLED'
  final DateTime createdAt;
  final String? worker;
  final Map<String, int> failedAttempts;

  MarketplaceApplication({
    required this.id,
    required this.title,
    this.type = 'student application',
    required this.category,
    required this.description,
    required this.deadline,
    this.difficulty = 1,
    required this.lineId,
    required this.wage,
    this.wageToken = 'CSP',
    required this.creatorAccountId,
    this.creatorNickname,
    this.secretCode,
    this.secretHash,
    this.status = 'OPEN',
    required this.createdAt,
    this.worker,
    this.failedAttempts = const {},
  });

  bool get isOpen => status == 'OPEN';
  bool get isCompleted => status == 'COMPLETED';
  bool get isCancelled => status == 'CANCELLED';

  factory MarketplaceApplication.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      if (val is num) {
        return val > 2000000000
            ? DateTime.fromMillisecondsSinceEpoch(val.toInt())
            : DateTime.fromMillisecondsSinceEpoch((val * 1000).toInt());
      }
      if (val is String) {
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      return DateTime.now();
    }

    Map<String, int> parseFails(dynamic val) {
      if (val is Map) {
        return val.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
      }
      return {};
    }

    return MarketplaceApplication(
      id: json['id'] ?? json['job_id'] ?? '',
      title: json['title'] ?? '',
      type: json['type'] ?? 'student application',
      category: json['category'] ?? 'tech',
      description: json['description'] ?? '',
      deadline: json['deadline'] ?? '',
      difficulty: (json['difficulty'] as num?)?.toInt() ?? 1,
      lineId: json['line_id'] ?? json['lineId'] ?? '',
      wage: (json['wage'] as num?)?.toDouble() ?? 0.0,
      wageToken: json['wage_token'] ?? json['wageToken'] ?? 'CSP',
      creatorAccountId: json['creator'] ?? json['creatorAccountId'] ?? '',
      creatorNickname: json['creatorNickname'] ?? json['creator_nickname'],
      secretCode: json['secret_code'] ?? json['secretCode'],
      secretHash: json['secret_hash'] ?? json['secretHash'],
      status: json['status'] ?? 'OPEN',
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      worker: json['worker'],
      failedAttempts: parseFails(json['failed_attempts'] ?? json['failedAttempts']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type,
    'category': category,
    'description': description,
    'deadline': deadline,
    'difficulty': difficulty,
    'line_id': lineId,
    'wage': wage,
    'wage_token': wageToken,
    'creator': creatorAccountId,
    if (creatorNickname != null) 'creator_nickname': creatorNickname,
    if (secretCode != null) 'secret_code': secretCode,
    if (secretHash != null) 'secret_hash': secretHash,
    'status': status,
    'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
    if (worker != null) 'worker': worker,
    'failed_attempts': failedAttempts,
  };

  MarketplaceApplication copyWith({
    String? id,
    String? title,
    String? type,
    String? category,
    String? description,
    String? deadline,
    int? difficulty,
    String? lineId,
    double? wage,
    String? wageToken,
    String? creatorAccountId,
    String? creatorNickname,
    String? secretCode,
    String? secretHash,
    String? status,
    DateTime? createdAt,
    String? worker,
    Map<String, int>? failedAttempts,
  }) {
    return MarketplaceApplication(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      category: category ?? this.category,
      description: description ?? this.description,
      deadline: deadline ?? this.deadline,
      difficulty: difficulty ?? this.difficulty,
      lineId: lineId ?? this.lineId,
      wage: wage ?? this.wage,
      wageToken: wageToken ?? this.wageToken,
      creatorAccountId: creatorAccountId ?? this.creatorAccountId,
      creatorNickname: creatorNickname ?? this.creatorNickname,
      secretCode: secretCode ?? this.secretCode,
      secretHash: secretHash ?? this.secretHash,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      worker: worker ?? this.worker,
      failedAttempts: failedAttempts ?? this.failedAttempts,
    );
  }
}

class AiEvaluation {
  final String id;
  final String branchId;
  final String? inboundMessageId;
  final String? conversationId;
  final String senderPhone;
  final String customerName;
  final String inputText;
  final String aiReply;
  final Map<String, dynamic> extractedDraft;
  final String rating; // 'UNRATED', 'GOOD', 'BAD', 'NEEDS_CORRECTION'
  final String? feedbackCategory;
  final String? correctionNotes;
  final String? expectedReply;
  final bool isReviewed;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  const AiEvaluation({
    required this.id,
    required this.branchId,
    this.inboundMessageId,
    this.conversationId,
    required this.senderPhone,
    this.customerName = '',
    required this.inputText,
    required this.aiReply,
    this.extractedDraft = const {},
    this.rating = 'UNRATED',
    this.feedbackCategory,
    this.correctionNotes,
    this.expectedReply,
    this.isReviewed = false,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
  });

  bool get isGood => rating == 'GOOD';
  bool get isBad => rating == 'BAD' || rating == 'NEEDS_CORRECTION';
  bool get isUnrated => rating == 'UNRATED';

  factory AiEvaluation.fromJson(Map<String, dynamic> json) {
    return AiEvaluation(
      id: json['id'] as String? ?? '',
      branchId: json['branch_id'] as String? ?? '',
      inboundMessageId: json['inbound_message_id'] as String?,
      conversationId: json['conversation_id'] as String?,
      senderPhone: json['sender_phone'] as String? ?? '',
      customerName: json['customer_name'] as String? ?? '',
      inputText: json['input_text'] as String? ?? '',
      aiReply: json['ai_reply'] as String? ?? '',
      extractedDraft: json['extracted_draft'] is Map<String, dynamic>
          ? json['extracted_draft'] as Map<String, dynamic>
          : {},
      rating: json['rating'] as String? ?? 'UNRATED',
      feedbackCategory: json['feedback_category'] as String?,
      correctionNotes: json['correction_notes'] as String?,
      expectedReply: json['expected_reply'] as String?,
      isReviewed: json['is_reviewed'] as bool? ?? false,
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'branch_id': branchId,
      'inbound_message_id': inboundMessageId,
      'conversation_id': conversationId,
      'sender_phone': senderPhone,
      'customer_name': customerName,
      'input_text': inputText,
      'ai_reply': aiReply,
      'extracted_draft': extractedDraft,
      'rating': rating,
      'feedback_category': feedbackCategory,
      'correction_notes': correctionNotes,
      'expected_reply': expectedReply,
      'is_reviewed': isReviewed,
      'reviewed_by': reviewedBy,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  AiEvaluation copyWith({
    String? id,
    String? branchId,
    String? inboundMessageId,
    String? conversationId,
    String? senderPhone,
    String? customerName,
    String? inputText,
    String? aiReply,
    Map<String, dynamic>? extractedDraft,
    String? rating,
    String? feedbackCategory,
    String? correctionNotes,
    String? expectedReply,
    bool? isReviewed,
    String? reviewedBy,
    DateTime? reviewedAt,
    DateTime? createdAt,
  }) {
    return AiEvaluation(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      inboundMessageId: inboundMessageId ?? this.inboundMessageId,
      conversationId: conversationId ?? this.conversationId,
      senderPhone: senderPhone ?? this.senderPhone,
      customerName: customerName ?? this.customerName,
      inputText: inputText ?? this.inputText,
      aiReply: aiReply ?? this.aiReply,
      extractedDraft: extractedDraft ?? this.extractedDraft,
      rating: rating ?? this.rating,
      feedbackCategory: feedbackCategory ?? this.feedbackCategory,
      correctionNotes: correctionNotes ?? this.correctionNotes,
      expectedReply: expectedReply ?? this.expectedReply,
      isReviewed: isReviewed ?? this.isReviewed,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

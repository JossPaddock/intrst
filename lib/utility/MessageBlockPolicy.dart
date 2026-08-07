/// Pure rules deciding whether messaging is blocked between the current viewer
/// and the other conversation participant.
///
/// Blocking is only enforced for one-to-one conversations (exactly one other
/// participant). Group conversations keep normal messaging behavior for now.
class MessageBlockPolicy {
  const MessageBlockPolicy._();

  /// A conversation is one-to-one when there is exactly one other participant
  /// besides the current viewer.
  static bool isOneToOne(int otherParticipantCount) =>
      otherParticipantCount == 1;

  /// Whether messaging should be blocked (input hidden, sends rejected).
  ///
  /// A block in either direction is enough to stop messages between the two
  /// users, but only for one-to-one conversations.
  static bool isBlocked({
    required int otherParticipantCount,
    required bool iBlockedThem,
    required bool theyBlockedMe,
  }) =>
      isOneToOne(otherParticipantCount) && (iBlockedThem || theyBlockedMe);
}

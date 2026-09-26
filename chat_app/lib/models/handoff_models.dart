class HandoffAccount {
  const HandoffAccount({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.email,
    required this.role,
    this.profilePicture,
  });

  final int userId;
  final String username;
  final String fullName;
  final String email;
  final String role;
  final String? profilePicture;

  String get displayName =>
      fullName.trim().isNotEmpty ? fullName.trim() : username;

  String get firstName {
    final parts = displayName.split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? displayName : parts.first;
  }

  factory HandoffAccount.fromJson(Map<String, dynamic> json) {
    final picture = (json['profile_picture'] ?? '').toString();
    return HandoffAccount(
      userId: int.tryParse((json['user_id'] ?? '0').toString()) ?? 0,
      username: (json['username'] ?? '').toString(),
      fullName: (json['full_name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? 'user').toString(),
      profilePicture: picture.isEmpty ? null : picture,
    );
  }
}

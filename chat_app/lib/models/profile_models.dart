class ProfileInfo {
  ProfileInfo({
    required this.fullName,
    required this.email,
    required this.username,
    required this.profilePicture,
  });

  final String fullName;
  final String email;
  final String username;

  final String? profilePicture;

  String get displayName => fullName.trim().isNotEmpty ? fullName : username;

  factory ProfileInfo.fromJson(Map<String, dynamic> json) {
    final pic = json['profile_picture'];
    return ProfileInfo(
      fullName: (json['full_name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      profilePicture:
          (pic == null || pic.toString().isEmpty) ? null : pic.toString(),
    );
  }

  ProfileInfo copyWith({String? profilePicture, bool clearPicture = false}) {
    return ProfileInfo(
      fullName: fullName,
      email: email,
      username: username,
      profilePicture:
          clearPicture ? null : (profilePicture ?? this.profilePicture),
    );
  }
}

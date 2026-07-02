// The signed-in user's own account, as returned by `getSelfSettings` on
// api.php ({status:'success', data:{...}}). Only the fields the mobile
// settings screen needs are modelled. `profilePicture` is a path relative
// to the server root (e.g. "uploads/avatars/avatar_80_ab12.png") or null.

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

  /// Server-relative path to the avatar, or null when none is set. Combine
  /// with the API base URL to build the image URL.
  final String? profilePicture;

  /// Best display name: full name if present, else the username.
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

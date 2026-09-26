import 'package:flutter/material.dart';

import '../models/user_admin_models.dart';
import '../theme.dart';

const Color kCustomRoleColor = Color(0xFF0891B2);

String titleCaseRole(String role) {
  final words = role
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase());
  return words.join(' ');
}

String roleLabel(String role, [List<RoleOption> roles = const []]) {
  final builtin = kBuiltinRoleLabels[role];
  if (builtin != null) return builtin;
  for (final r in roles) {
    if (r.slug == role) return r.label;
  }
  if (role.isEmpty) return 'No role';
  return titleCaseRole(role);
}

String roleTag(String role) {
  final builtin = kBuiltinRoleAccess[role];
  if (builtin != null) return builtin;
  if (role == 'super_admin') return 'Owner';
  return 'Custom';
}

const Map<String, String> _kRoleDescriptions = {
  'admin':
      'Full administrative permissions, system configurations, and operational command.',
  'developer':
      'Engineering, debugging, system logs, API integrations, and code branch releases.',
  'technical_staff':
      'Hardware setups, terminal diagnostics, customer support, and field operations.',
  'sales':
      'Client onboarding, leads pipeline, pricing agreements, and marketing materials.',
  'user':
      'Standard operational permissions for daily support tickets and task management.',
  'ojt':
      'Restricted onboarding profile for interns and trainees undergoing supervision.',
};

String roleDescription(String role, [List<RoleOption> roles = const []]) {
  final builtin = _kRoleDescriptions[role];
  if (builtin != null) return builtin;
  for (final r in roles) {
    if (r.slug == role && r.description.trim().isNotEmpty) {
      return r.description.trim();
    }
  }
  return 'Custom role. Set exactly what accounts with this clearance can reach.';
}

Color roleColor(String role) {
  switch (role) {
    case 'super_admin':
      return Brand.danger;
    case 'admin':
      return Brand.signal;
    case 'developer':
      return const Color(0xFF6366F1);
    case 'technical_staff':
      return Brand.info;
    case 'sales':
      return const Color(0xFF059669);
    case 'user':
      return const Color(0xFF14B8A6);
    case 'ojt':
      return const Color(0xFFA855F7);
    default:
      return kCustomRoleColor;
  }
}

IconData roleIcon(String role) {
  switch (role) {
    case 'super_admin':
      return Icons.admin_panel_settings_outlined;
    case 'admin':
      return Icons.shield_outlined;
    case 'developer':
      return Icons.code_rounded;
    case 'technical_staff':
      return Icons.build_outlined;
    case 'sales':
      return Icons.trending_up_rounded;
    case 'user':
      return Icons.person_outline_rounded;
    case 'ojt':
      return Icons.school_outlined;
    default:
      return Icons.badge_outlined;
  }
}

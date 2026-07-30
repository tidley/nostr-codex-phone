String normalizeWorkspaceInviteCode(String value) =>
    value.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

bool isWorkspaceInviteCode(String value) =>
    RegExp(r'^[0-9A-F]{10}$').hasMatch(normalizeWorkspaceInviteCode(value));

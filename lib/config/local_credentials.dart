/// Local login credentials — not sent to any server.
library;

/// Password-gated bill edit on saved bills (staff ledger flow).
const String billEditPassword = '12345678';

/// Password required before staff data reset runs.
const String resetPassword = 'SURABHI';

const Map<String, ({String locationCode, String password})> _staffAccounts = {
  'surabhi': (locationCode: 'main', password: 'surabhi'),
};

/// Staff usernames for the shop.
const List<String> staffLocationUsernames = ['surabhi'];

bool isStaffUsername(String username) {
  return _staffAccounts.containsKey(username.trim().toLowerCase());
}

bool verifyStaffLogin(String username, String password) {
  final account = _staffAccounts[username.trim().toLowerCase()];
  if (account == null) {
    return false;
  }
  return password.trim().toLowerCase() == account.password.toLowerCase();
}

String staffLocationCodeForUsername(String username) {
  final account = _staffAccounts[username.trim().toLowerCase()];
  if (account == null) {
    throw ArgumentError('Unknown staff username: $username');
  }
  return account.locationCode;
}

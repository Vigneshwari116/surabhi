/// Single-location Surabhi Exports (offline).
const List<String> allLocationCodes = ['main'];

const String businessDisplayName = 'SURABHI EXPORTS';

String displayNameForLocationCode(String code) {
  switch (code) {
    case 'main':
      return 'Surabhi';
    default:
      return code;
  }
}

/// Staff-facing branch label shown on dashboards and receipts.
String branchLabelForLocationCode(String code) {
  switch (code) {
    case 'main':
      return 'Surabhi Exports';
    default:
      return displayNameForLocationCode(code);
  }
}

String branchLabelForDisplayName(String displayName) {
  return branchLabelForLocationCode(locationCodeFromDisplayName(displayName));
}

String locationCodeFromDisplayName(String displayName) {
  switch (displayName) {
    case 'Surabhi':
      return 'main';
    default:
      return displayName.toLowerCase();
  }
}

bool isActiveLocationCode(String code) {
  return allLocationCodes.contains(code.toLowerCase());
}

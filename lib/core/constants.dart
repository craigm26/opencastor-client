/// App-wide constants — versions, URLs, labels.
library;

class AppConstants {
  AppConstants._();

  static const String appVersion = '1.5.0';
  static const String rcanVersion = '3.2';
  static const String versionLabel = 'v$appVersion · RCAN v$rcanVersion';
  // opencastorReleaseVersion removed: PyPI publishing is in CalVer → SemVer
  // transition (last CalVer release 2026.4.23.0; pyproject + CHANGELOG list
  // SemVer 3.0.2 but it's not yet on PyPI). No pin = no broken install
  // command. See opencastor-ops findings-app-opencastor.md F-OCC-02 follow-up.

  // Documentation URLs
  static const String docsRoot = 'https://opencastor.com/docs/';
  static const String docsFleetUi = 'https://opencastor.com/docs/fleet-ui/';
  static const String docsChat = 'https://opencastor.com/docs/chat/';
  static const String docsConsent = 'https://rcan.dev/spec/docs/consent/';

  // Ecosystem links
  static const String opencastorGitHub =
      'https://github.com/craigm26/OpenCastor';
  static const String rcanSpecUrl = 'https://rcan.dev/spec/';
  static const String rcanDevUrl = 'https://rcan.dev/';
  // Robot Registry Foundation — canonical URLs (robotregistryfoundation.org)
  static const String rrfUrl =
      'https://robotregistryfoundation.org/';
  static const String rrfRegisterUrl =
      'https://robotregistryfoundation.org/';
  static const String rrfOpencastorUrl =
      'https://robotregistryfoundation.org/registry/';
  static const String rcanPyPypi = 'https://pypi.org/project/rcan/';
  static const String rcanPyGitHub =
      'https://github.com/continuonai/rcan-py';
  static const String rcanTsNpm =
      'https://www.npmjs.com/package/rcan-ts';
  static const String rcanTsGitHub =
      'https://github.com/continuonai/rcan-ts';
}

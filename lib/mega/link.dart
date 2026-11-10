/// A parsed Mega public-folder link.
class MegaLink {
  /// Handle of the linked folder, e.g. `ytZkzaSC`.
  final String rootHandle;

  /// Base64url folder key (22 chars = 16 bytes), e.g. `l_VpZ-zplh5xYEm8RN7c2g`.
  final String key;

  /// Optional subfolder handle from a `/folder/<handle>` suffix.
  final String? subfolderHandle;

  const MegaLink({
    required this.rootHandle,
    required this.key,
    this.subfolderHandle,
  });

  /// The canonical link without any subfolder suffix.
  String get cleanUrl => 'https://mega.nz/folder/$rootHandle#$key';
}

final _linkRe = RegExp(
  r'mega\.nz\/folder\/([A-Za-z0-9_-]+)#([A-Za-z0-9_-]+)(?:\/folder\/([A-Za-z0-9_-]+))?',
);

/// Parse a Mega folder URL. Throws [FormatException] on anything else.
MegaLink parseMegaLink(String url) {
  final m = _linkRe.firstMatch(url.trim());
  if (m == null) {
    throw const FormatException(
      'That does not look like a Mega folder link (expected mega.nz/folder/…).',
    );
  }
  return MegaLink(
    rootHandle: m.group(1)!,
    key: m.group(2)!,
    subfolderHandle: m.group(3),
  );
}

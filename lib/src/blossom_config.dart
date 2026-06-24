const autoBlossomServer = 'auto';

const blossomPresets = <BlossomPreset>[
  BlossomPreset(
    label: 'Auto-select',
    url: autoBlossomServer,
    note: 'Try public free-tier servers in order',
  ),
  BlossomPreset(
    label: 'Nostr.build',
    url: 'https://blossom.nostr.build',
    note: 'Free audio uploads up to 20 MiB',
  ),
  BlossomPreset(
    label: 'Primal',
    url: 'https://blossom.primal.net',
    note: 'Public Blossom server',
  ),
  BlossomPreset(
    label: 'Nostrcheck',
    url: 'https://cdn.nostrcheck.me',
    note: 'Public Blossom endpoint',
  ),
];

const autoBlossomUploadServers = <String>[
  'https://blossom.nostr.build',
  'https://blossom.primal.net',
  'https://cdn.nostrcheck.me',
];

class BlossomPreset {
  const BlossomPreset({
    required this.label,
    required this.url,
    required this.note,
  });

  final String label;
  final String url;
  final String note;
}

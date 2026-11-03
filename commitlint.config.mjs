// Conventional Commits: https://www.conventionalcommits.org
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-enum': [1, 'always', [
      'ui', 'i18n', 'l10n', 'clipboard', 'snippets', 'passwords', 'notes', 'monitor', 'battery', 'displays',
      'cleaner', 'actions', 'palette', 'windows', 'notch', 'widgets', 'meetings', 'recordings', 'memory', 'ai',
      'files', 'updates', 'installer', 'release', 'site', 'readme', 'homebrew', 'deps',
    ]],
  },
};

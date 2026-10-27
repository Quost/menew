// Conventional Commits: https://www.conventionalcommits.org
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-enum': [1, 'always', [
      'ui', 'i18n', 'clipboard', 'snippets', 'notes', 'monitor', 'cleaner', 'actions',
      'updates', 'installer', 'release', 'site', 'homebrew', 'deps',
    ]],
  },
};

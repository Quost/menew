// Conventional Commits: https://www.conventionalcommits.org
export default {
  extends: ['@commitlint/config-conventional'],
  // Commits do Dependabot trazem changelog com linhas longas; o título do PR (que vira o commit no main) segue checado.
  ignores: [(message) => /^Signed-off-by: dependabot\[bot\]/m.test(message)],
  rules: {
    'scope-enum': [1, 'always', [
      'ui', 'i18n', 'l10n', 'clipboard', 'snippets', 'passwords', 'notes', 'monitor', 'battery', 'displays',
      'cleaner', 'actions', 'palette', 'windows', 'notch', 'widgets', 'meetings', 'recordings', 'memory', 'ai',
      'files', 'updates', 'installer', 'release', 'site', 'readme', 'homebrew', 'deps',
    ]],
  },
};

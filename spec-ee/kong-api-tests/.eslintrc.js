module.exports = {
  root: true,
  env: {
    node: true,
    mocha: true,
  },
  parser: '@typescript-eslint/parser',
  plugins: ['@typescript-eslint'],
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:prettier/recommended',
  ],
  ignorePatterns: ['packages/**'],
  rules: {
    'prettier/prettier': 0,
    'no-restricted-syntax': [
      'error',
      {
        selector: "AwaitExpression[argument.type='CallExpression'][argument.callee.name='wait']",
        message: "Don't use `await wait()` due to it's flakiness, prefer `eventually`",
      },
    ],
    '@typescript-eslint/no-var-requires': 'warn',
    '@typescript-eslint/no-explicit-any': 'off',
  },
};

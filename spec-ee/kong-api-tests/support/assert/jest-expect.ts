import { expect } from 'expect';

// https://jestjs.io/docs/expect#expectextendmatchers
expect.extend({
  toBeTypeOrNull: (actual, classType) => {
    try {
      expect(actual).toEqual(expect.any(classType));
      return {
        message: () => `Ok`,
        pass: true,
      };
    } catch (error) {
      return actual === null
        ? {
            message: () => `Ok`,
            pass: true,
          }
        : {
            message: () => `expected ${actual} to be ${classType} type or null`,
            pass: false,
          };
    }
  },
});

declare module 'expect' {
  interface AsymmetricMatchers {
    toBeTypeOrNull(classType: any): void;
  }
  interface Matchers<R> {
    toBeTypeOrNull(classType: any): R;
  }
}

export const jestExpect = expect;

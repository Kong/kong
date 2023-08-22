/**
 * This file helps to configure Assertion handles for automated tests.
 * Different plugin is used to enhance the capability of chai.
 * Chai as Promised extends Chai with a fluent language for asserting facts about promises.
 * chai-string extends the capability of chai to help with common string comparison assertions.
 *
 * Read more about :
 * chai as promised: https://www.chaijs.com/plugins/chai-as-promised/
 * chai-string: https://www.chaijs.com/plugins/chai-string/
 * chai-Arrays: https://www.chaijs.com/plugins/chai-arrays/
 */

import * as chai from 'chai';
import chaiArrays from 'chai-arrays';
import chaiAsPromised from 'chai-as-promised';
import chaiLike from 'chai-like';
import chaiString from 'chai-string';
import chaiBytes from 'chai-bytes';

chai.use(chaiAsPromised);
chai.use(chaiString);
chai.use(chaiArrays);
chai.use(chaiLike);
chai.use(chaiBytes);
export const expect = chai.expect;

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { isFirstPartyPublisher } from '../../frontend/src/utils/appsPublisher.ts';

test('공식 앱: Hub에서 명시한 first_party만 공식 제공으로 표시한다', () => {
  assert.equal(isFirstPartyPublisher('first_party'), true);
  assert.equal(isFirstPartyPublisher('third_party'), false);
});

test('공식 앱: 이전 Hub 응답·알 수 없는 값은 검증된 앱으로 표시한다', () => {
  for (const value of [undefined, null, '', 'partner', 'official', 'First_Party', 1, true, {}, []]) {
    assert.equal(isFirstPartyPublisher(value), false, String(value));
  }
});

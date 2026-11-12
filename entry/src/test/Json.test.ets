import { describe, expect, it } from '@ohos/hypium';
import {
  arrayValue,
  booleanValue,
  byteLength,
  numberValue,
  objectValue,
  parseJsonObject,
  stringValue
} from '../main/ets/util/Json';

export default function jsonTest(): void {
  describe('Json', () => {
    it('countsUtf8BytesWithoutRuntimeEncoderDependence', 0, () => {
      expect(byteLength('')).assertEqual(0);
      expect(byteLength('abc')).assertEqual(3);
      expect(byteLength('é')).assertEqual(2);
      expect(byteLength('中')).assertEqual(3);
      expect(byteLength('😀')).assertEqual(4);
    });

    it('parsesNestedObjectsAndArrays', 0, () => {
      const raw = parseJsonObject('{"name":"track","meta":{"page":2},"items":[1,2]}');
      const meta = objectValue(raw.meta);
      const items = arrayValue(raw.items);

      expect(stringValue(raw.name)).assertEqual('track');
      expect(numberValue(meta.page)).assertEqual(2);
      expect(items.length).assertEqual(2);
      expect(numberValue(items[1])).assertEqual(2);
    });

    it('rejectsInvalidJsonAndNonObjectRoots', 0, () => {
      let invalidJson = false;
      let arrayRoot = false;
      let scalarRoot = false;
      try {
        parseJsonObject('{bad json');
      } catch (error) {
        invalidJson = true;
      }
      try {
        parseJsonObject('[1,2]');
      } catch (error) {
        arrayRoot = true;
      }
      try {
        parseJsonObject('42');
      } catch (error) {
        scalarRoot = true;
      }

      expect(invalidJson).assertTrue();
      expect(arrayRoot).assertTrue();
      expect(scalarRoot).assertTrue();
    });

    it('usesDefaultsForMissingAndInvalidTypes', 0, () => {
      expect(numberValue(undefined, 7)).assertEqual(7);
      expect(numberValue('not-a-number', 7)).assertEqual(7);
      expect(numberValue('2.5', 0)).assertEqual(2.5);
      expect(stringValue(undefined, 'fallback')).assertEqual('fallback');
      expect(stringValue(0, 'fallback')).assertEqual('0');
      expect(booleanValue(undefined, true)).assertTrue();
      expect(booleanValue(0, true)).assertFalse();
      expect(booleanValue(1, false)).assertTrue();
    });

    it('keepsArrayAndObjectBoundaries', 0, () => {
      const object: Record<string, Object> = {};
      object.value = 'one';

      expect(Object.keys(objectValue(object)).length).assertEqual(1);
      expect(Object.keys(objectValue('text')).length).assertEqual(0);
      expect(Object.keys(objectValue(undefined)).length).assertEqual(0);
      expect(arrayValue(object).length).assertEqual(0);
      expect(arrayValue('text').length).assertEqual(0);
      expect(arrayValue([1, 'two']).length).assertEqual(2);
    });
  });
}

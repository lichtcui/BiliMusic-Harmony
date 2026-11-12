import { describe, expect, it } from '@ohos/hypium';
import {
  isBiliImageUrl,
  isBiliMediaUrl
} from '../main/ets/services/BiliUrl';

export default function biliUrlTest(): void {
  describe('BiliUrl', () => {
    it('acceptsOnlyBilibiliImageHostsOverHttps', 0, () => {
      expect(isBiliImageUrl('https://i0.hdslb.com/bfs/test.jpg')).assertTrue();
      expect(isBiliImageUrl('https://s1.biliimg.com/cover.jpg')).assertTrue();
      expect(isBiliImageUrl('https://hdslb.com/image.webp')).assertTrue();
      expect(isBiliImageUrl('https://i0.hdslb.com:443/image.webp')).assertTrue();

      expect(isBiliImageUrl('http://i0.hdslb.com/image.jpg')).assertFalse();
      expect(isBiliImageUrl('https://example.com/image.jpg')).assertFalse();
      expect(isBiliImageUrl('https://i0.hdslb.com.evil.example/image.jpg')).assertFalse();
      expect(isBiliImageUrl('https://user:pass@i0.hdslb.com/image.jpg')).assertFalse();
      expect(isBiliImageUrl('https://i0.hdslb.com:8443/image.jpg')).assertFalse();
      expect(isBiliImageUrl('https://127.0.0.1/image.jpg')).assertFalse();
      expect(isBiliImageUrl('file:///tmp/image.jpg')).assertFalse();
      expect(isBiliImageUrl('')).assertFalse();
    });

    it('acceptsOnlyKnownBilibiliMediaCdnHostsOverHttps', 0, () => {
      expect(isBiliMediaUrl('https://upos-sz-mirrorcos.bilivideo.com/audio.m4s')).assertTrue();
      expect(isBiliMediaUrl('https://mcdn.bilivideo.cn/audio.m4s')).assertTrue();
      expect(isBiliMediaUrl('https://upos-hz-mirrorakam.akamaized.net/audio.m4s')).assertTrue();
      expect(isBiliMediaUrl('https://upos-sz-mirror08c.bilibili.com/audio.m4s')).assertTrue();
      expect(isBiliMediaUrl('https://szbdyd.com/audio.m4s')).assertTrue();

      expect(isBiliMediaUrl('http://upos-sz-mirrorcos.bilivideo.com/audio.m4s')).assertFalse();
      expect(isBiliMediaUrl('https://www.bilibili.com/audio.m4s')).assertFalse();
      expect(isBiliMediaUrl('https://download.akamaized.net/audio.m4s')).assertFalse();
      expect(isBiliMediaUrl('https://cdn.bilibili.com/audio.m4s')).assertFalse();
      expect(isBiliMediaUrl('https://upos-sz-mirrorcos.bilivideo.com.evil.example/audio.m4s'))
        .assertFalse();
      expect(isBiliMediaUrl('https://example.com/audio.m4s')).assertFalse();
      expect(isBiliMediaUrl('https://user:pass@bilivideo.com/audio.m4s')).assertFalse();
      expect(isBiliMediaUrl('https://bilivideo.com:8443/audio.m4s')).assertFalse();
      expect(isBiliMediaUrl('https://10.0.0.1/audio.m4s')).assertFalse();
      expect(isBiliMediaUrl('')).assertFalse();
    });
  });
}
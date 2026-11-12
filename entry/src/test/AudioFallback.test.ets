import { describe, expect, it } from '@ohos/hypium';
import {
  AudioCandidateSource,
  audioPriorityFor,
  decideAudioRecovery,
  selectDashAudioCandidates,
  tryAudioCandidates
} from '../main/ets/services/AudioFallback';

interface AudioStreamFixture {
  id: number;
  baseUrl: string;
  backupUrl?: string[];
}

function candidate(id: number, name: string): AudioCandidateSource {
  return {
    url: `https://cdn.example.invalid/${name}.m4s`,
    id: id,
    mimeType: 'audio/mp4',
    codecs: 'mp4a.40.2',
    bandwidth: 128000,
    source: 'dash'
  };
}

export default function audioFallbackTest(): void {
  describe('AudioFallback', () => {
    it('ordersAudioIdsAndTriesBaseBeforeEveryBackup', 0, () => {
      const streams: AudioStreamFixture[] = [
        {
          id: 30216,
          baseUrl: 'https://cdn.example.invalid/30216-base.m4s',
          backupUrl: ['https://cdn.example.invalid/30216-backup.m4s']
        },
        {
          id: 30280,
          baseUrl: 'https://cdn.example.invalid/30280-base.m4s',
          backupUrl: [
            'https://cdn.example.invalid/30280-backup-1.m4s',
            'https://cdn.example.invalid/30280-backup-2.m4s'
          ]
        },
        {
          id: 30232,
          baseUrl: 'https://cdn.example.invalid/30232-base.m4s',
          backupUrl: ['https://cdn.example.invalid/30232-backup.m4s']
        },
        {
          id: 30232,
          baseUrl: 'http://cdn.example.invalid/30232-ignored.m4s'
        },
        {
          id: 99999,
          baseUrl: 'https://cdn.example.invalid/ignored.m4s'
        }
      ];

      const selected = selectDashAudioCandidates(streams, 'high');

      expect(selected.map((item: AudioCandidateSource): number => item.id).join(',')).assertEqual(
        '30280,30280,30280,30232,30232,30216,30216'
      );
      expect(selected[0].url).assertEqual('https://cdn.example.invalid/30280-base.m4s');
      expect(selected[1].url).assertEqual('https://cdn.example.invalid/30280-backup-1.m4s');
      expect(selected[2].url).assertEqual('https://cdn.example.invalid/30280-backup-2.m4s');
      expect(selected[3].url).assertEqual('https://cdn.example.invalid/30232-base.m4s');
      expect(selected[4].url).assertEqual('https://cdn.example.invalid/30232-backup.m4s');
    });

    it('mapsQualityTiersToDownwardOnlyAudioIds', 0, () => {
      expect(audioPriorityFor('high').join(',')).assertEqual('30280,30232,30216');
      expect(audioPriorityFor('standard').join(',')).assertEqual('30232,30216');
      expect(audioPriorityFor('low').join(',')).assertEqual('30216');
    });

    it('defaultsToStandardQualityAndFallsBackDownward', 0, () => {
      const streams: AudioStreamFixture[] = [
        {
          id: 30216,
          baseUrl: 'https://cdn.example.invalid/30216-base.m4s'
        },
        {
          id: 30280,
          baseUrl: 'https://cdn.example.invalid/30280-base.m4s'
        },
        {
          id: 30232,
          baseUrl: 'https://cdn.example.invalid/30232-base.m4s'
        }
      ];

      const standard = selectDashAudioCandidates(streams);
      expect(standard.map((item: AudioCandidateSource): number => item.id).join(',')).assertEqual(
        '30232,30216'
      );

      const low = selectDashAudioCandidates(streams, 'low');
      expect(low.map((item: AudioCandidateSource): number => item.id).join(',')).assertEqual('30216');
    });

    it('usesThePreferredCandidateWhenItIsAvailable', 0, async () => {
      const attempts: number[] = [];
      const selection = await tryAudioCandidates([
        candidate(30280, 'preferred-base'),
        candidate(30280, 'preferred-backup')
      ], (): boolean => true, async (item: AudioCandidateSource): Promise<void> => {
        attempts.push(item.id);
      });

      expect(selection?.index).assertEqual(0);
      expect(attempts.join(',')).assertEqual('30280');
    });

    it('fallsThroughToTheNextAudioIdWhenThePreferredIdFails', 0, async () => {
      const attempts: number[] = [];
      const selection = await tryAudioCandidates([
        candidate(30280, 'preferred-base'),
        candidate(30232, 'fallback-base')
      ], (): boolean => true, async (item: AudioCandidateSource): Promise<void> => {
        attempts.push(item.id);
        if (item.id === 30280) {
          throw new Error('preferred failed');
        }
      });

      expect(selection?.index).assertEqual(1);
      expect(selection?.candidate.id).assertEqual(30232);
      expect(attempts.join(',')).assertEqual('30280,30232');
    });

    it('triesTheBackupAfterItsBaseFails', 0, async () => {
      const attempts: string[] = [];
      const selection = await tryAudioCandidates([
        candidate(30280, 'base'),
        candidate(30280, 'backup')
      ], (): boolean => true, async (item: AudioCandidateSource): Promise<void> => {
        attempts.push(item.url);
        if (item.url.includes('base')) {
          throw new Error('base failed');
        }
      });

      expect(selection?.index).assertEqual(1);
      expect(selection?.candidate.url).assertEqual('https://cdn.example.invalid/backup.m4s');
      expect(attempts.length).assertEqual(2);
    });

    it('reportsFailureAfterEveryCandidateHasFailed', 0, async () => {
      const attempts: number[] = [];
      let message = '';
      try {
        await tryAudioCandidates([
          candidate(30280, 'base'),
          candidate(30280, 'backup')
        ], (): boolean => true, async (item: AudioCandidateSource): Promise<void> => {
          attempts.push(item.id);
          throw new Error('candidate failed');
        });
      } catch (error) {
        message = (error as Error).message;
      }

      expect(message).assertEqual('candidate failed');
      expect(attempts.length).assertEqual(2);
    });

    it('allowsOnePositionPreservingRefreshPerTrackFailureCycle', 0, () => {
      const first = decideAudioRecovery(false, true, 47.25);
      const second = decideAudioRecovery(true, true, 47.25);
      const missingTrack = decideAudioRecovery(false, false, 47.25);

      expect(first.action).assertEqual('refresh');
      expect(first.position).assertEqual(47.25);
      expect(second.action).assertEqual('fail');
      expect(missingTrack.action).assertEqual('fail');
    });
  });
}

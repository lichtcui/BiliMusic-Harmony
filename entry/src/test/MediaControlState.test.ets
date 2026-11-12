import { describe, expect, it } from '@ohos/hypium';
import {
  audioOutputChangeAction,
  audioOutputChangeReason,
  MediaControlCommand,
  MediaControlDispatcher,
  MediaControlHandler,
  MediaInterruptionState
} from '../main/ets/services/MediaControlState';

class RecordingMediaControlHandler implements MediaControlHandler {
  readonly commands: MediaControlCommand[] = [];

  onCommand(command: MediaControlCommand): void {
    this.commands.push(command);
  }
}

export default function mediaControlStateTest(): void {
  describe('MediaControlState', () => {
    it('routesEverySystemMediaCommandThroughOneHandler', 0, () => {
      const handler = new RecordingMediaControlHandler();
      const dispatcher = new MediaControlDispatcher(handler);

      dispatcher.dispatch({ type: 'play' });
      dispatcher.dispatch({ type: 'pause' });
      dispatcher.dispatch({ type: 'stop' });
      dispatcher.dispatch({ type: 'next' });
      dispatcher.dispatch({ type: 'previous' });
      dispatcher.dispatch({ type: 'seek', positionSeconds: 42.5 });
      dispatcher.dispatch({ type: 'mode-change', mode: 'repeat-all' });

      expect(handler.commands.map((command: MediaControlCommand): string => command.type).join(','))
        .assertEqual('play,pause,stop,next,previous,seek,mode-change');
      expect(handler.commands[5].positionSeconds).assertEqual(42.5);
      expect(handler.commands[6].mode).assertEqual('repeat-all');
    });

    it('preservesSubmissionOrderForRapidSystemCommands', 0, () => {
      const handler = new RecordingMediaControlHandler();
      const dispatcher = new MediaControlDispatcher(handler);

      dispatcher.dispatch({ type: 'pause' });
      dispatcher.dispatch({ type: 'next' });
      dispatcher.dispatch({ type: 'play' });
      dispatcher.dispatch({ type: 'seek', positionSeconds: 12 });

      expect(handler.commands.map((command: MediaControlCommand): string => command.type).join(','))
        .assertEqual('pause,next,play,seek');
      expect(handler.commands[3].positionSeconds).assertEqual(12);
    });

    it('ignoresCommandsAfterDispatcherShutdown', 0, () => {
      const handler = new RecordingMediaControlHandler();
      const dispatcher = new MediaControlDispatcher(handler);

      expect(dispatcher.dispatch({ type: 'play' })).assertTrue();
      dispatcher.shutdown();
      dispatcher.dispatch({ type: 'pause' });

      expect(handler.commands.length).assertEqual(1);
      expect(handler.commands[0].type).assertEqual('play');
    });

    it('pausesOnceForFocusLossAndResumesOnceOnFocusReturn', 0, () => {
      const state = new MediaInterruptionState();
      const paused = state.handleInterrupt('pause', 'playing');
      const duplicatePause = state.handleInterrupt('pause', 'playing');
      const resumed = state.handleInterrupt('resume', 'paused');
      const duplicateResume = state.handleInterrupt('resume', 'playing');

      expect(paused.action).assertEqual('pause');
      expect(paused.revision).assertEqual(1);
      expect(duplicatePause.action).assertEqual('none');
      expect(resumed.action).assertEqual('resume');
      expect(resumed.revision).assertEqual(2);
      expect(duplicateResume.action).assertEqual('none');
    });

    it('doesNotResumeAfterStopOrACommandDuringInterruption', 0, () => {
      const stopped = new MediaInterruptionState();
      const stopPause = stopped.handleInterrupt('stop', 'playing');
      const stopResume = stopped.handleInterrupt('resume', 'paused');

      const manuallyChanged = new MediaInterruptionState();
      const focusPause = manuallyChanged.handleInterrupt('pause', 'playing');
      const commandRevision = manuallyChanged.beginExternalCommand();
      const manualResume = manuallyChanged.handleInterrupt('resume', 'paused');

      expect(stopPause.action).assertEqual('pause');
      expect(stopResume.action).assertEqual('none');
      expect(focusPause.action).assertEqual('pause');
      expect(commandRevision).assertEqual(2);
      expect(manualResume.action).assertEqual('none');
    });

    it('ignoresInterruptionsWhenIdleOrDestroyed', 0, () => {
      const state = new MediaInterruptionState();

      expect(state.handleInterrupt('pause', 'idle').action).assertEqual('none');
      expect(state.handleInterrupt('pause', 'paused').action).assertEqual('none');
      state.destroy();

      expect(state.beginExternalCommand()).assertEqual(-1);
      expect(state.handleInterrupt('pause', 'playing').action).assertEqual('none');
    });

    it('dropsQueuedInterruptionWorkAfterALaterCommand', 0, () => {
      const state = new MediaInterruptionState();
      const pauseDecision = state.handleInterrupt('pause', 'playing');
      const resumeDecision = state.handleInterrupt('resume', 'paused');
      const commandRevision = state.beginExternalCommand();

      expect(state.isRevisionCurrent(pauseDecision.revision)).assertFalse();
      expect(state.isRevisionCurrent(resumeDecision.revision)).assertFalse();
      expect(state.isRevisionCurrent(commandRevision)).assertTrue();

      state.destroy();
      expect(state.isRevisionCurrent(commandRevision)).assertFalse();
    });

    it('pausesOnlyWhenTheActiveOutputDeviceDisappears', 0, () => {
      expect(audioOutputChangeReason(0)).assertEqual('unknown');
      expect(audioOutputChangeReason(1)).assertEqual('new-device');
      expect(audioOutputChangeReason(2)).assertEqual('old-device-unavailable');
      expect(audioOutputChangeReason(3)).assertEqual('overridden');
      expect(audioOutputChangeReason(4)).assertEqual('session-activated');
      expect(audioOutputChangeReason(5)).assertEqual('stream-priority-changed');
      expect(audioOutputChangeAction('old-device-unavailable')).assertEqual('pause');
      expect(audioOutputChangeAction('new-device')).assertEqual('none');
      expect(audioOutputChangeAction('overridden')).assertEqual('none');
      expect(audioOutputChangeAction('unknown')).assertEqual('none');
    });
  });
}

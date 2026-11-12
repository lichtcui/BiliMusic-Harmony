/**
 * Pure helpers for the player stage vertical swipe.
 *
 * Swiping up moves to the next track and swiping down back to the previous one, mirroring the
 * feed style used by short-form music players. Keeping the threshold math out of the component
 * lets the host tests cover it without an ArkUI runtime.
 */
export type PlayerSwipeDirection = '' | 'next' | 'previous';

export interface PlayerSwipeInput {
  offsetY: number;
  velocityY: number;
  stageHeight: number;
  ratio: number;
  velocityThreshold: number;
}

const MIN_DRAG_DISTANCE: number = 8;
const DRAG_LIMIT_RATIO: number = 0.35;
const DRAG_RESISTANCE: number = 0.25;

export function dampPlayerSwipeOffset(offsetY: number, stageHeight: number): number {
  const offset = Number.isFinite(offsetY) ? offsetY : 0;
  const height = Number.isFinite(stageHeight) ? stageHeight : 0;
  if (height <= 0) {
    return 0;
  }
  const limit = height * DRAG_LIMIT_RATIO;
  if (Math.abs(offset) <= limit) {
    return offset;
  }
  const sign = offset < 0 ? -1 : 1;
  return sign * (limit + (Math.abs(offset) - limit) * DRAG_RESISTANCE);
}

export function resolvePlayerSwipe(input: PlayerSwipeInput): PlayerSwipeDirection {
  const offset = Number.isFinite(input.offsetY) ? input.offsetY : 0;
  const velocity = Number.isFinite(input.velocityY) ? input.velocityY : 0;
  const height = Number.isFinite(input.stageHeight) ? input.stageHeight : 0;
  if (height <= 0 || Math.abs(offset) < MIN_DRAG_DISTANCE) {
    return '';
  }
  const threshold = height * Math.max(0, input.ratio);
  if (offset <= -threshold) {
    return 'next';
  }
  if (offset >= threshold) {
    return 'previous';
  }
  if (Math.abs(velocity) >= Math.max(0, input.velocityThreshold)) {
    return velocity < 0 ? 'next' : 'previous';
  }
  return '';
}

/** Offset the incoming stage starts from once the outgoing stage has left the screen. */
export function playerSwipeEnterOffset(direction: PlayerSwipeDirection, stageHeight: number): number {
  const height = Number.isFinite(stageHeight) ? Math.max(0, stageHeight) : 0;
  if (direction === 'next') {
    return height;
  }
  if (direction === 'previous') {
    return -height;
  }
  return 0;
}

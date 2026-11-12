import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

const COVER_DIRECTORY: string = 'playlist-covers';

export enum CoverPickStatus {
  Picked = 0,
  Cancelled = 1,
  Failed = 2
}

export interface CoverPickResult {
  status: CoverPickStatus;
  /** `Picked` 时是 app 沙箱内封面的 `file://` URI，其余状态为空串。 */
  uri: string;
}

/**
 * 新建 / 修改歌单抽屉共用的封面草稿。
 *
 * 相册返回的 URI 只在临时授权期内可靠，所以选中后立即复制进 app 沙箱；
 * 抽屉关闭或重新选择时删除上一次复制、但还没有入库的临时文件。
 * `dispose(keepPending)` 在提交进行中时保留临时文件，等提交结果再决定提交 / 删除。
 */
export class PlaylistCoverDraft {
  private pendingPath: string = '';
  /** 选择图片的世代戳：抽屉关闭 / 重选时丢弃迟到的异步结果。 */
  private generation: number = 0;
  private destroyed: boolean = false;

  async pick(context: common.UIAbilityContext | undefined): Promise<CoverPickResult> {
    if (context === undefined || this.destroyed) {
      return { status: CoverPickStatus.Failed, uri: '' };
    }
    const generation = this.generation + 1;
    this.generation = generation;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (this.stale(generation) || result.photoUris.length === 0) {
        return { status: CoverPickStatus.Cancelled, uri: '' };
      }
      const copiedPath = this.copyIntoApp(context, result.photoUris[0]);
      if (this.stale(generation)) {
        removeCoverFile(copiedPath);
        return { status: CoverPickStatus.Cancelled, uri: '' };
      }
      this.replacePending(copiedPath);
      return { status: CoverPickStatus.Picked, uri: fileUri.getUriFromPath(copiedPath) };
    } catch (_error) {
      return { status: CoverPickStatus.Failed, uri: '' };
    }
  }

  /**
   * 组件卸载：作废在途选择。
   * 提交进行中时传 `keepPending = true`，临时文件交给 `commit()` / `discard()` 收尾。
   */
  dispose(keepPending: boolean): void {
    this.destroyed = true;
    this.generation += 1;
    if (!keepPending) {
      this.discard();
    }
  }

  /** 封面已经随歌单入库：停止跟踪临时文件，不再删除。 */
  commit(): void {
    this.pendingPath = '';
  }

  /** 放弃本次选择的临时封面（已入库的旧封面不受影响）。 */
  discard(): void {
    const path = this.pendingPath;
    this.pendingPath = '';
    removeCoverFile(path);
  }

  private stale(generation: number): boolean {
    return this.destroyed || generation !== this.generation;
  }

  private replacePending(path: string): void {
    this.discard();
    this.pendingPath = path;
  }

  /** 把相册临时 URI 复制进 app 沙箱；返回绝对路径。 */
  private copyIntoApp(context: common.UIAbilityContext, sourceUri: string): string {
    const directory = `${context.filesDir}/${COVER_DIRECTORY}`;
    if (!fs.accessSync(directory)) {
      fs.mkdirSync(directory, true);
    }
    const path = `${directory}/cover-${Date.now()}-${Math.floor(Math.random() * 1000000)}.img`;
    const source = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
    try {
      fs.copyFileSync(source.fd, path);
    } finally {
      fs.closeSync(source);
    }
    return path;
  }
}

function removeCoverFile(path: string): void {
  if (path.length === 0) {
    return;
  }
  try {
    if (fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  } catch (_error) {
    // 临时文件清理是 best effort；失败不能影响创建 / 保存流程。
  }
}
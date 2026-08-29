import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

export class TempFileManager {
  private static context: common.UIAbilityContext;

  static init(context: common.UIAbilityContext): void {
    TempFileManager.context = context;
    // 确保编辑器帧缓存目录存在
    TempFileManager.ensureEditorFramesDir();
  }

  static getEditorFramesDir(): string {
    return `${TempFileManager.context.cacheDir}/frames/`;
  }

  static ensureEditorFramesDir(): void {
    const dir = TempFileManager.getEditorFramesDir();
    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
    } catch (e) {
      fileIo.mkdirSync(dir, true);
    }
  }

  static getFrameFilePath(index: number): string {
    return `${TempFileManager.getEditorFramesDir()}frame_${index}.png`;
  }

  static clearEditorFrames(): void {
    const dir = TempFileManager.getEditorFramesDir();
    try {
      if (fileIo.accessSync(dir)) {
        TempFileManager.deleteDirectoryRecursive(dir);
      }
    } catch (e) { /* 忽略 */ }
  }

  private static deleteDirectoryRecursive(path: string): void {
    try {
      const files = fileIo.listFileSync(path);
      for (const file of files) {
        const fullPath = `${path}/${file}`;
        const stat = fileIo.statSync(fullPath);
        if (stat.isDirectory()) {
          TempFileManager.deleteDirectoryRecursive(fullPath);
        } else {
          fileIo.unlinkSync(fullPath);
        }
      }
      fileIo.rmdirSync(path);
    } catch (e) {
      console.warn('删除目录失败:', path, JSON.stringify(e));
    }
  }
}
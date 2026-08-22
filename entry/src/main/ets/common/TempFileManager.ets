import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

export class TempFileManager {
  private static context: common.UIAbilityContext;

  static init(context: common.UIAbilityContext): void {
    TempFileManager.context = context;
    TempFileManager.cleanTempDir();
  }

  static getTempDir(): string {
    return `${TempFileManager.context.filesDir}/temp_frames/`;
  }

  // 递归删除目录
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
      console.error('删除目录失败:', path, JSON.stringify(e));
    }
  }

  static cleanTempDir(): void {
    try {
      const dir = TempFileManager.getTempDir();
      if (fileIo.accessSync(dir)) {
        TempFileManager.deleteDirectoryRecursive(dir);
      }
      fileIo.mkdirSync(dir);
    } catch (e) {
      console.error('清理临时目录失败:', JSON.stringify(e));
    }
  }

  static getTempFilePath(index: number): string {
    return `${TempFileManager.getTempDir()}frame_${index}.png`;
  }
}
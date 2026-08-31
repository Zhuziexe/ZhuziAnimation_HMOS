import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { executeCommand, stopCommand } from '@tyousan/ffmpeg';
import { BusinessError } from '@kit.BasicServicesKit';

@CustomDialog
export struct VideoMuteDialog {
  controller: CustomDialogController;
  videoUri: string = ''; // 由外部传入

  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  @State status: 'processing' | 'saving' | 'done' = 'processing';
  private currentSessionId: number = -1;
  private cancelFlag: boolean = false;
  private isPageAlive: boolean = true;

  aboutToAppear() {
    if (!this.videoUri) {
      promptAction.showToast({ message: '未传入视频' });
      this.controller.close();
      return;
    }
    this.startMute();
  }

  aboutToDisappear() {
    this.isPageAlive = false;
    if (this.currentSessionId > 0) {
      stopCommand({ sessionId: this.currentSessionId });
    }
    const cacheDir = this.context.cacheDir + '/tools/mute/';
    try { fileIo.unlinkSync(cacheDir + 'muted_video.mp4'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'tmp_video.mp4'); } catch {}
  }

  private async startMute() {
    try {
      const cacheDir = this.context.cacheDir + '/tools/mute/';
      try { fileIo.mkdirSync(cacheDir, true); } catch {}
      const inputPath = cacheDir + 'tmp_video.mp4';
      const outputPath = cacheDir + 'muted_video.mp4';

      // 复制视频到缓存
      await this.copyMediaUriToPath(this.videoUri, inputPath);
      try { fileIo.unlinkSync(outputPath); } catch {}

      // FFmpeg 命令：-c:v copy 复制视频流（无损），-an 去除音频
      const args = ['-i', inputPath, '-c:v', 'copy', '-an', '-y', outputPath];
      console.info('静音参数:', args.join(' '));

      this.cancelFlag = false;
      executeCommand({
        cmd: args.join(' '),
        start: (result) => {
          this.currentSessionId = result.sessionId;
        },
        success: (result) => {
          if (!this.cancelFlag && this.isPageAlive) {
            this.saveVideo(outputPath);
          } else {
            try { fileIo.unlinkSync(outputPath); } catch {}
            this.controller.close();
          }
        },
        fail: (error) => {
          console.error('静音失败:', error);
          if (this.isPageAlive && !this.cancelFlag) {
            promptAction.showToast({ message: `静音失败: ${error.message || '未知错误'}` });
          }
          try { fileIo.unlinkSync(outputPath); } catch {}
          this.controller.close();
        },
        cancel: (result) => {
          console.info('静音已取消');
          try { fileIo.unlinkSync(outputPath); } catch {}
          if (this.isPageAlive) {
            promptAction.showToast({ message: '已取消静音' });
          }
          this.controller.close();
        },
        complete: (result) => {
          this.currentSessionId = -1;
        }
      });
    } catch (err) {
      console.error('准备静音失败:', err);
      promptAction.showToast({ message: '准备失败' });
      this.controller.close();
    }
  }

  private async copyMediaUriToPath(mediaUri: string, destPath: string): Promise<void> {
    try { fileIo.unlinkSync(destPath); } catch {}
    const srcFd = fileIo.openSync(mediaUri, fileIo.OpenMode.READ_ONLY);
    if (srcFd.fd < 0) throw new Error('打开媒体失败');
    const destFd = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      const bufferSize = 1024 * 1024;
      const buf = new ArrayBuffer(bufferSize);
      let readLen: number;
      while ((readLen = fileIo.readSync(srcFd.fd, buf)) > 0) {
        fileIo.writeSync(destFd.fd, buf, { length: readLen });
      }
    } finally {
      fileIo.closeSync(srcFd);
      fileIo.closeSync(destFd);
    }
  }

  private async saveVideo(filePath: string) {
    try {
      this.status = 'saving';
      const phHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
      const configs: photoAccessHelper.PhotoCreationConfig[] = [
        {
          title: `静音_${Date.now()}`,
          fileNameExtension: 'mp4',
          photoType: photoAccessHelper.PhotoType.VIDEO,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
        }
      ];
      const destUris = await phHelper.showAssetsCreationDialog([filePath], configs);
      if (!destUris || destUris.length === 0) {
        throw new Error('用户取消保存');
      }
      const destUri = destUris[0];
      const srcFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(destUri, fileIo.OpenMode.WRITE_ONLY);
      fileIo.copyFileSync(srcFile.fd, destFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(destFile);

      if (this.isPageAlive) {
        promptAction.showToast({ message: '静音视频已保存' });
      }
      this.controller.close();
    } catch (err) {
      console.error('保存视频失败:', err);
      if (this.isPageAlive) {
        const errorMsg = (err as BusinessError).message || '未知错误';
        promptAction.showToast({ message: `保存失败: ${errorMsg}` });
      }
      this.controller.close();
    } finally {
      try { fileIo.unlinkSync(filePath); } catch {}
    }
  }

  build() {
    Column({ space: 16 }) {
      if (this.status === 'processing') {
        LoadingProgress().width(48).height(48)
        Text('静音处理中，请稍候...').fontSize(14).fontColor($r('sys.color.font_secondary'))
        Button('取消').onClick(() => {
          if (this.currentSessionId > 0) {
            stopCommand({ sessionId: this.currentSessionId });
          }
          this.cancelFlag = true;
          this.controller.close();
        })
      } else if (this.status === 'saving') {
        LoadingProgress().width(48).height(48)
        Text('正在弹出保存窗口...').fontSize(16).fontColor($r('sys.color.font_primary'))
      }
    }
    .padding(24)
  }
}
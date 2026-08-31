// ExtractAudioDialog.ets
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { executeCommand, stopCommand } from '@tyousan/ffmpeg';
import { BusinessError } from '@kit.BasicServicesKit';

@CustomDialog
export struct ExtractAudioDialog {
  controller: CustomDialogController;
  videoUri: string = ''; // 由外部传入，不再内部选择

  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  @State status: 'processing' | 'saving' | 'done' = 'processing';
  @State progressText: string = '正在提取音频...';
  private currentSessionId: number = -1;
  private cancelFlag: boolean = false;
  private isPageAlive: boolean = true;

  aboutToAppear() {
    if (!this.videoUri) {
      promptAction.showToast({ message: '未传入视频' });
      this.controller.close();
      return;
    }
    // 自动开始提取
    this.startExtract();
  }

  aboutToDisappear() {
    this.isPageAlive = false;
    if (this.currentSessionId > 0) {
      stopCommand({ sessionId: this.currentSessionId });
    }
    const cacheDir = this.context.cacheDir + '/tools/audio/';
    try { fileIo.unlinkSync(cacheDir + 'extracted_audio.mp3'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'tmp_video.mp4'); } catch {}
  }

  private async startExtract() {
    try {
      const cacheDir = this.context.cacheDir + '/tools/audio/';
      try { fileIo.mkdirSync(cacheDir, true); } catch {}
      const inputPath = cacheDir + 'tmp_video.mp4';
      const outputPath = cacheDir + 'extracted_audio.mp3';

      // 复制视频到缓存
      await this.copyMediaUriToPath(this.videoUri, inputPath);
      try { fileIo.unlinkSync(outputPath); } catch {}

      // FFmpeg 命令：提取音频为 MP3
      const args = ['-i', inputPath, '-vn', '-acodec', 'libmp3lame', '-ab', '192k', '-y', outputPath];
      console.info('提取音频参数:', args.join(' '));

      this.cancelFlag = false;
      executeCommand({
        cmd: args.join(' '),
        start: (result) => {
          this.currentSessionId = result.sessionId;
        },
        success: (result) => {
          if (!this.cancelFlag && this.isPageAlive) {
            this.saveAudio(outputPath);
          } else {
            try { fileIo.unlinkSync(outputPath); } catch {}
            this.controller.close();
          }
        },
        fail: (error) => {
          console.error('提取失败:', error);
          if (this.isPageAlive && !this.cancelFlag) {
            promptAction.showToast({ message: `提取失败: ${error.message || '未知错误'}` });
          }
          try { fileIo.unlinkSync(outputPath); } catch {}
          this.controller.close();
        },
        cancel: (result) => {
          console.info('提取已取消');
          try { fileIo.unlinkSync(outputPath); } catch {}
          if (this.isPageAlive) {
            promptAction.showToast({ message: '已取消提取' });
          }
          this.controller.close();
        },
        complete: (result) => {
          this.currentSessionId = -1;
        }
      });
    } catch (err) {
      console.error('准备提取失败:', err);
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

  private async saveAudio(filePath: string) {
    try {
      this.status = 'saving';
      this.progressText = '保存音频...';
      const audioSaveOptions = new picker.AudioSaveOptions();
      const timestamp = Date.now();
      audioSaveOptions.newFileNames = [`提取音频_${timestamp}.mp3`];

      const audioViewPicker = new picker.AudioViewPicker(this.context);
      const uris = await audioViewPicker.save(audioSaveOptions);
      if (!uris || uris.length === 0) {
        throw new Error('用户取消保存');
      }
      const destUri = uris[0];

      const srcFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(destUri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.copyFileSync(srcFile.fd, destFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(destFile);

      if (this.isPageAlive) {
        promptAction.showToast({ message: '音频已保存' });
      }
      this.controller.close();
    } catch (err) {
      console.error('保存音频失败:', err);
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
        Text(this.progressText).fontSize(16).fontColor($r('sys.color.font_primary'))
        Text('提取可能需要一些时间...').fontSize(14).fontColor($r('sys.color.font_secondary'))
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
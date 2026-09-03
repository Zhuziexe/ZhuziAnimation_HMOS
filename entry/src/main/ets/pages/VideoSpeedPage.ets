// VideoSpeedPage.ets
import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommand, stopCommand } from '@tyousan/ffmpeg';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProcessingDialog } from '../components/ProcessingDialog';

interface FfmpegResult {
  sessionId?: number;
}
interface FfmpegError {
  sessionId?: number;
  errCode?: number | string;
  message?: string;
  stderr?: string;
}

// 预定义倍速选项
const SPEED_OPTIONS = [0.25, 0.5, 0.75, 1.25, 1.5, 2.0, 4.0];

@Entry
@Component
struct VideoSpeedPage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  @State videoUri: string = '';
  @State selectedSpeed: number = 1.5;
  @State isProcessing: boolean = false;

  private currentSessionId: number = -1;
  private cancelFlag: boolean = false;
  private isPageAlive: boolean = true;
  private progressDialogController: CustomDialogController | null = null;

  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    if (params && params['videoUri']) {
      this.videoUri = params['videoUri'];
      // 可以获取视频缩略图或信息，这里略
    } else {
      promptAction.showToast({ message: '未传入视频' });
      router.back();
    }
  }

  aboutToDisappear() {
    this.isPageAlive = false;
    if (this.progressDialogController) {
      try { this.progressDialogController.close(); } catch {}
      this.progressDialogController = null;
    }
    // 清理临时文件
    try {
      const cacheDir = this.context.cacheDir + '/tools/speed/';
      fileIo.unlinkSync(cacheDir + 'output.mp4');
    } catch {}
  }

  // ---------- 构建FFmpeg变速命令 ----------
  private buildSpeedCommand(inputPath: string, outputPath: string, speed: number): string[] {
    // 视频setpts
    let setptsValue = '';
    if (speed >= 1) {
      setptsValue = `${1 / speed}*PTS`;
    } else {
      setptsValue = `${1 / speed}*PTS`; // 例如0.5倍 => setpts=2.0*PTS
    }

    // 音频atempo：需要拆分成多个atempo链，每个有效范围0.5~2.0
    const atempoFilters = this.buildAtempoChain(speed);

    const videoFilter = `setpts=${setptsValue}`;
    const audioFilter = atempoFilters.length > 0 ? `atempo=${atempoFilters.join(',atempo=')}` : '';

    let args = ['-i', inputPath];
    if (videoFilter) {
      args.push('-vf', videoFilter);
    }
    if (audioFilter) {
      args.push('-af', audioFilter);
    }
    // 保持编码质量
    args.push('-c:v', 'libx264', '-crf', '18', '-preset', 'medium');
    args.push('-c:a', 'aac', '-b:a', '192k');
    args.push('-y', outputPath);
    return args;
  }

  private buildAtempoChain(speed: number): number[] {
    if (speed === 1.0) return [];
    if (speed >= 0.5 && speed <= 2.0) return [speed];

    const factors: number[] = [];
    let remaining = speed;
    if (speed > 2.0) {
      while (remaining > 2.0) {
        factors.push(2.0);
        remaining /= 2.0;
      }
      if (remaining > 1) factors.push(remaining);
      else if (remaining < 1) factors.push(remaining);
    } else if (speed < 0.5) {
      while (remaining < 0.5) {
        factors.push(0.5);
        remaining /= 0.5;
      }
      if (remaining > 0) factors.push(remaining);
    }
    return factors.filter(f => f >= 0.5 && f <= 2.0);
  }

  private cancelProcess(): void {
    if (this.currentSessionId > 0) {
      stopCommand({ sessionId: this.currentSessionId });
    }
    this.cancelFlag = true;
  }

  private startSpeedExport() {
    if (this.isProcessing) return;
    if (this.selectedSpeed === 1.0) {
      promptAction.showToast({ message: '倍速为1.0，无需处理' });
      return;
    }

    this.cancelFlag = false;
    this.isProcessing = true;

    this.progressDialogController = new CustomDialogController({
      builder: ProcessingDialog({
        processingText: `视频变速中...`,
        secondaryText: '处理视频可能需要一些时间',
        onCancel: () => this.cancelProcess()
      }),
      autoCancel: false,
      customStyle: true,
      cancel: () => this.cancelProcess()
    });
    this.progressDialogController.open();

    // 准备文件路径
    const cacheDir = this.context.cacheDir + '/tools/speed/';
    try { fileIo.mkdirSync(cacheDir, true); } catch {}
    const inputPath = cacheDir + 'source.mp4';
    const outputPath = cacheDir + 'output.mp4';

    // 复制原始视频到缓存（避免直接操作媒体库文件）
    this.copyVideoToCache(this.videoUri, inputPath).then(() => {
      const args = this.buildSpeedCommand(inputPath, outputPath, this.selectedSpeed);
      console.info('FFmpeg变速参数:', args.join(' '));

      executeCommand({
        cmd: args.join(' '),
        start: (result: FfmpegResult) => {
          this.currentSessionId = result.sessionId ?? -1;
        },
        success: (result: FfmpegResult) => {
          console.info('FFmpeg success 回调触发，sessionId:', result.sessionId);
          console.info('   cancelFlag=', this.cancelFlag, 'isPageAlive=', this.isPageAlive);

          this.closeProgressDialog();
          if (this.isPageAlive && !this.cancelFlag) {
            this.saveToGallery(outputPath);
          } else {
            console.warn('条件不满足，跳过保存。可能页面已销毁或已取消');
            // 如果页面已销毁，可能无法弹窗，但仍可尝试保存（但context可能无效）
            // 这里可以继续尝试，但为了安全，先跳过
            try { fileIo.unlinkSync(outputPath); } catch {}
          }
          this.isProcessing = false;
        },
        fail: (error: FfmpegError) => {
          console.error('变速失败:', error);
          if (this.isPageAlive && !this.cancelFlag) {
            promptAction.showToast({ message: `变速失败: ${error.message || '未知错误'}` });
          }
          try { fileIo.unlinkSync(outputPath); } catch {}
          this.closeProgressDialog();
          this.isProcessing = false;
        },
        cancel: (result: FfmpegResult) => {
          try { fileIo.unlinkSync(outputPath); } catch {}
          if (this.isPageAlive) {
            promptAction.showToast({ message: '已取消变速' });
          }
          this.closeProgressDialog();
          this.isProcessing = false;
        },
        complete: (result: FfmpegResult) => {
          this.currentSessionId = -1;
        }
      });
    }).catch(() => {
      console.error('复制视频失败');
      promptAction.showToast({ message: '准备视频失败' });
      this.isProcessing = false;
      this.closeProgressDialog();
    });
  }

  private async copyVideoToCache(srcUri: string, destPath: string): Promise<void> {
    try { fileIo.unlinkSync(destPath); } catch {}
    const srcFd = fileIo.openSync(srcUri, fileIo.OpenMode.READ_ONLY);
    if (srcFd.fd < 0) throw new Error('打开源视频失败');
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

  private closeProgressDialog() {
    if (this.progressDialogController) {
      try { this.progressDialogController.close(); } catch {}
      this.progressDialogController = null;
    }
  }

  private async saveToGallery(filePath: string): Promise<void> {
    try {
      const phHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
      const configs: photoAccessHelper.PhotoCreationConfig[] = [
        {
          title: `变速_${Date.now()}`,
          fileNameExtension: 'mp4',
          photoType: photoAccessHelper.PhotoType.VIDEO,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
        }
      ];
      const destUris = await phHelper.showAssetsCreationDialog([filePath], configs);
      if (!destUris || destUris.length === 0) {
        promptAction.showToast({ message: '用户取消保存' });
        return;
      }
      const srcFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(destUris[0], fileIo.OpenMode.WRITE_ONLY);
      fileIo.copyFileSync(srcFile.fd, destFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(destFile);
      if (this.isPageAlive) {
        promptAction.showToast({ message: '变速视频已保存到相册' });
        router.back();
      }
    } catch (err) {
      console.error('保存到图库失败:', err);
      if (this.isPageAlive) {
        promptAction.showToast({ message: `保存失败: ${(err as Error).message || '未知错误'}` });
      }
    } finally {
      try { fileIo.unlinkSync(filePath); } catch {}
    }
  }

  // ---------- UI ----------
  @Builder
  buildTopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(24).width(24).height(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .onClick(() => {
        if (this.isProcessing) {
          promptAction.showToast({ message: '正在处理，请使用"取消"按钮停止' });
        } else {
          router.back();
        }
      })
      .height(40).width(40).buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('视频变速')
        .layoutWeight(1)
        .fontSize(18)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Start)
    }
    .width('100%').height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('sys.color.background_primary'))
    .shadow({ radius: 2, color: '#1A000000', offsetY: 1 })
  }

  @Builder
  buildSpeedSelector() {
    Column({ space: 12 }) {
      Text('选择倍速')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Row() {
        Slider({
            value: 4,
            min: 0,
            max: 6,
            step: 1,
          })
          .layoutWeight(1)
          .selectedColor($r('app.color.brand'))
          .onChange((index: number) => {
            const speed = SPEED_OPTIONS[index];
            if (!this.isProcessing && speed !== undefined) {
              this.selectedSpeed = speed;
            }
          })
          .enabled(!this.isProcessing)
          .layoutWeight(1)

        Text(`${this.selectedSpeed}x`)
          .fontSize(18)
          .width(50)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      if(this.selectedSpeed == 0.25 || this.selectedSpeed == 4.0) {
        Text('提示: 0.25倍速/4倍速变速可能需要更长的时间')
          .fontSize(16)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start)
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
  }

  build() {
    Column() {
      this.buildTopBar();
      this.buildSpeedSelector()

      Blank()

      Button('变速并导出')
        .height(48)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.brand'))
        .fontColor(Color.White)
        .borderRadius(24)
        .onClick(() => this.startSpeedExport())
        .enabled(!this.isProcessing && this.selectedSpeed !== 1.0)
        .width('90%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_tertiary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
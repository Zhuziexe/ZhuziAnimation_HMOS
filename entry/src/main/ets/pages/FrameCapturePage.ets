import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';

@Entry
@Component
struct FrameCapturePage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  @State videoUri: string = '';
  @State currentTime: number = 0;
  @State isReady: boolean = false;
  private videoController: VideoController = new VideoController();

  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    if (params && params['videoUri']) {
      this.videoUri = params['videoUri'];
      this.isReady = true;
    } else {
      promptAction.showToast({ message: '未传入视频' });
      router.back();
    }
  }

  aboutToDisappear() {
    this.videoController.stop();
  }

  private async captureFrame() {
    if (!this.isReady) {
      promptAction.showToast({ message: '视频尚未加载' });
      return;
    }

    try {
      const cacheDir = this.context.cacheDir + '/tools/framecapture/';
      try { fileIo.mkdirSync(cacheDir, true); } catch {}

      const inputPath = cacheDir + 'tmp_video.mp4';
      const outputPath = cacheDir + 'capture_frame.png';

      // 复制视频到缓存
      await this.copyMediaUriToPath(this.videoUri, inputPath);

      const timeInSeconds = this.currentTime.toFixed(3);
      const cmd = `-ss ${timeInSeconds} -i "${inputPath}" -frames:v 1 -y "${outputPath}"`;
      const result: CommandSyncResult = executeCommandSync(cmd);
      if (result.evenType !== 'onSuccess') {
        throw new Error(`FFmpeg截图失败: ${result.failStackTrace || '未知错误'}`);
      }

      await this.saveToGallery(outputPath);

      // 清理
      try { fileIo.unlinkSync(inputPath); } catch {}
      try { fileIo.unlinkSync(outputPath); } catch {}

      promptAction.showToast({ message: '截图已保存到相册' });
    } catch (err) {
      console.error('截图失败:', err);
      promptAction.showToast({ message: `截图失败: ${err.message || '未知错误'}` });
    }
  }

  private async copyMediaUriToPath(mediaUri: string, destPath: string): Promise<void> {
    const srcFd = fileIo.openSync(mediaUri, fileIo.OpenMode.READ_ONLY);
    if (srcFd.fd < 0) throw new Error('打开媒体失败');
    const destFd = fileIo.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
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

  private async saveToGallery(filePath: string): Promise<void> {
    const phHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
    const configs: photoAccessHelper.PhotoCreationConfig[] = [
      {
        title: `截图_${Date.now()}`,
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
      }
    ];
    const destUris = await phHelper.showAssetsCreationDialog([filePath], configs);
    if (!destUris || destUris.length === 0) {
      throw new Error('用户取消保存');
    }
    const srcFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    const destFile = fileIo.openSync(destUris[0], fileIo.OpenMode.WRITE_ONLY);
    fileIo.copyFileSync(srcFile.fd, destFile.fd);
    fileIo.closeSync(srcFile);
    fileIo.closeSync(destFile);
  }

  @Builder
  buildTopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(24)
          .width(24)
          .height(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .onClick(() => { router.back(); })
      .height(40)
      .width(40)
      .buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('视频单帧提取')
        .layoutWeight(1)
        .fontSize(18)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.LEFT)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('sys.color.background_primary'))
    .shadow({ radius: 2, color: '#1A000000', offsetY: 1 })
  }

  build() {
    Column() {
      this.buildTopBar();

      if (this.isReady && this.videoUri) {
        Column({ space: 12 }) {
          Video({
            src: this.videoUri,
            controller: this.videoController
          })
            .width('100%')
            .layoutWeight(1)
            .autoPlay(false)
            .controls(true)
            .objectFit(ImageFit.Contain)
            .onPrepared(() => {
              this.videoController.setCurrentTime(0);
              this.videoController.pause();
            })
            .onUpdate((event) => {
              this.currentTime = event.time;
            })

          Button('截取此帧')
            .onClick(() => { this.captureFrame(); })
            .width('90%')
            .height(48)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('sys.color.background_emphasize'))
            .fontColor(Color.White)
            .borderRadius(24)
            .margin({ bottom: 20 })
        }
        .layoutWeight(1)
        .padding({ top: 8 })
      } else {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
          Text('加载中...')
            .fontSize(16)
            .fontColor($r('sys.color.font_secondary'))
            .margin({ top: 12 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_tertiary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
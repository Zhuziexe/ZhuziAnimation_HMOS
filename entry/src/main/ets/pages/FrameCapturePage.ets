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
  @State currentTime: number = 0;        // 当前播放位置（秒）
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

  // ----- 截取当前帧 -----
  private async captureFrame() {
    if (!this.isReady) {
      promptAction.showToast({ message: '视频尚未加载' });
      return;
    }

    try {
      // 将媒体 URI 复制到沙箱（FFmpeg 需要普通文件路径）
      const inputPath = await this.copyMediaUriToSandbox(this.videoUri);
      const timeInSeconds = this.currentTime.toFixed(3);  // 精确到毫秒
      const outputPath = `${this.context.cacheDir}/frame_${Date.now()}.png`;

      const command = [
        '-ss', timeInSeconds,
        '-i', `"${inputPath}"`,
        '-frames:v', '1',
        '-y',
        `"${outputPath}"`
      ];
      const result: CommandSyncResult = executeCommandSync(command.join(' '));
      if (result.evenType !== 'onSuccess') {
        throw new Error(`FFmpeg 截图失败: ${result.failStackTrace || '未知错误'}`);
      }

      await this.saveToGallery(outputPath);

      // 清理临时文件
      try { fileIo.unlinkSync(inputPath); } catch {}
      try { fileIo.unlinkSync(outputPath); } catch {}

      promptAction.showToast({ message: '截图已保存到相册' });
    } catch (err) {
      console.error('截图失败:', err);
      promptAction.showToast({ message: `截图失败: ${err.message || '未知错误'}` });
    }
  }

  // ----- 复制媒体到沙箱（供 FFmpeg 使用）-----
  private async copyMediaUriToSandbox(mediaUri: string): Promise<string> {
    const srcFd = fileIo.openSync(mediaUri, fileIo.OpenMode.READ_ONLY);
    if (srcFd.fd < 0) {
      throw new Error('打开媒体文件失败');
    }
    const tempPath = `${this.context.cacheDir}/tmp_video_${Date.now()}.mp4`;
    const destFd = fileIo.openSync(tempPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
    try {
      const bufferSize = 1024 * 1024;
      const buf = new ArrayBuffer(bufferSize);
      let readLen: number;
      while ((readLen = fileIo.readSync(srcFd.fd, buf)) > 0) {
        fileIo.writeSync(destFd.fd, buf, { length: readLen });
      }
      return tempPath;
    } finally {
      fileIo.closeSync(srcFd);
      fileIo.closeSync(destFd);
    }
  }

  // ----- 保存到相册（弹窗授权）-----
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

      Text('视频帧截取')
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
        Scroll() {
          Column({ space: 12 }) {
            // 使用系统自带控制条
            Video({
              src: this.videoUri,
              controller: this.videoController
            })
              .width('100%')
              .aspectRatio(16 / 9)
              .autoPlay(false)
              .controls(true)
              .objectFit(ImageFit.Contain)
              .onPrepared(() => {
                // 视频准备完成后，定位到第一帧并暂停（系统控制条会在UI上显示）
                this.videoController.setCurrentTime(0);
                this.videoController.pause();
              })
              .onUpdate((event) => {
                // 实时更新当前时间（供截图使用）
                this.currentTime = event.time; // 单位：秒
              })
              .onFinish(() => {
                // 播放结束时可以不做特殊处理
              })

            Button('截取此帧')
              .onClick(() => {
                this.captureFrame();
              })
              .width('100%')
          }
          .layoutWeight(1)
        }
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
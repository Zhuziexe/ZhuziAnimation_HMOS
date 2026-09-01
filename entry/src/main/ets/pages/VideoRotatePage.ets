import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommand, stopCommand, executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';

@CustomDialog
struct RotateProgressDialog {
  controller: CustomDialogController;
  onCancel: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      LoadingProgress().width(48).height(48)
      Text('旋转中...').fontSize(18).fontColor($r('sys.color.font_primary'))
      Text('旋转视频可能需要一些时间。').fontSize(14).fontColor($r('sys.color.font_secondary'))
      Button('取消')
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick(() => {
          this.onCancel();
          this.controller.close();
        })
        .width(120)
    }
    .padding(24)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_tertiary'))
  }
}

@Entry
@Component
struct VideoRotatePage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  @State videoUri: string = '';
  @State rotateMode: string = 'none';
  @State framePath: string = '';
  @State isLoading: boolean = true;
  @State isRotating: boolean = false;

  private currentSessionId: number = -1;
  private cancelFlag: boolean = false;
  private isPageAlive: boolean = true;
  private progressDialogController: CustomDialogController | null = null;

  private rotateOptions: SelectOption[] = [
    { value: '不旋转' },
    { value: '顺时针90°' },
    { value: '逆时针90°' },
    { value: '旋转180°' },
    { value: '水平翻转' },
    { value: '垂直翻转' }
  ];

  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    if (params && params['videoUri']) {
      this.videoUri = params['videoUri'];
      this.prepareFrame();
    } else {
      promptAction.showToast({ message: '未传入视频' });
      router.back();
    }
  }

  aboutToDisappear() {
    this.isPageAlive = false;
    if (this.progressDialogController) {
      try {
        this.progressDialogController.close();
      } catch (e) {}
      this.progressDialogController = null;
    }
    const cacheDir = this.context.cacheDir + '/tools/rotate/';
    try { fileIo.unlinkSync(cacheDir + 'crop_frame.png'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'tmp_video.mp4'); } catch {}
  }

  private async prepareFrame() {
    try {
      this.isLoading = true;
      const cacheDir = this.context.cacheDir + '/tools/rotate/';
      try { fileIo.mkdirSync(cacheDir, true); } catch {}
      const inputPath = cacheDir + 'tmp_video.mp4';
      const framePath = cacheDir + 'crop_frame.png';

      try { fileIo.unlinkSync(inputPath); } catch {}
      try { fileIo.unlinkSync(framePath); } catch {}

      await this.copyMediaUriToPath(this.videoUri, inputPath);
      const cmd = `-i "${inputPath}" -frames:v 1 -y "${framePath}"`;
      const result: CommandSyncResult = executeCommandSync(cmd);
      if (result.evenType !== 'onSuccess') throw new Error('提取第一帧失败');

      this.framePath = framePath;
      this.isLoading = false;
    } catch (err) {
      console.error('准备帧失败:', err);
      promptAction.showToast({ message: '加载视频失败' });
      router.back();
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

  private getRotateAngle(): number {
    switch (this.rotateMode) {
      case 'clockwise90': return 90;
      case 'counterclockwise90': return -90;
      case 'rotate180': return 180;
      default: return 0;
    }
  }

  private getScaleX(): number {
    switch (this.rotateMode) {
      case 'hflip': return -1;
      default: return 1;
    }
  }

  private getScaleY(): number {
    switch (this.rotateMode) {
      case 'vflip': return -1;
      default: return 1;
    }
  }

  private buildRotateCommand(inputPath: string, outputPath: string, mode: string): string[] {
    if (mode === 'none') {
      return ['-i', inputPath, '-c', 'copy', '-y', outputPath];
    }
    let filter = '';
    switch (mode) {
      case 'clockwise90': filter = 'transpose=1'; break;
      case 'counterclockwise90': filter = 'transpose=2'; break;
      case 'rotate180': filter = 'transpose=2,transpose=2'; break;
      case 'hflip': filter = 'hflip'; break;
      case 'vflip': filter = 'vflip'; break;
    }
    return ['-i', inputPath, '-vf', filter, '-c:a', 'copy', '-y', outputPath];
  }

  private startRotate() {
    if (this.isRotating) return;
    this.cancelFlag = false;
    this.isRotating = true;

    this.progressDialogController = new CustomDialogController({
      builder: RotateProgressDialog({
        onCancel: () => {
          if (this.currentSessionId > 0) {
            stopCommand({ sessionId: this.currentSessionId });
          }
          this.cancelFlag = true;
        }
      }),
      autoCancel: false,
      customStyle: true,
    });
    this.progressDialogController.open();

    const cacheDir = this.context.cacheDir + '/tools/rotate/';
    const inputPath = cacheDir + 'tmp_video.mp4';
    const outputPath = cacheDir + 'rotated_video.mp4';

    try { fileIo.unlinkSync(outputPath); } catch {}

    const args = this.buildRotateCommand(inputPath, outputPath, this.rotateMode);
    console.info('FFmpeg 参数:', args.join(' '));

    executeCommand({
      cmd: args.join(' '),
      start: (result) => {
        this.currentSessionId = result.sessionId;
        console.info('旋转任务启动, sessionId:', this.currentSessionId);
      },
      success: (result) => {
        console.info('旋转任务成功, sessionId: ', result.sessionId);
        if (!this.cancelFlag && this.isPageAlive) {
          this.saveToGallery(outputPath);
        } else {
          try { fileIo.unlinkSync(outputPath); } catch {}
        }
        this.closeProgressDialog();
      },
      fail: (error) => {
        console.error('旋转任务失败:', error);
        if (this.isPageAlive && !this.cancelFlag) {
          promptAction.showToast({ message: `旋转失败: ${error.message || '未知错误'}` });
        }
        try { fileIo.unlinkSync(outputPath); } catch {}
        this.closeProgressDialog();
      },
      cancel: (result) => {
        console.info('旋转任务已取消, sessionId: ', result.sessionId);
        try { fileIo.unlinkSync(outputPath); } catch {}
        if (this.isPageAlive) {
          promptAction.showToast({ message: '已取消旋转' });
        }
        this.closeProgressDialog();
      },
      complete: (result) => {
        console.info('旋转任务结束, sessionId: ', result.sessionId);
        this.isRotating = false;
        this.currentSessionId = -1;
      }
    });
  }

  private closeProgressDialog() {
    if (this.progressDialogController) {
      try {
        this.progressDialogController.close();
      } catch (e) {}
      this.progressDialogController = null;
    }
  }

  private async saveToGallery(filePath: string): Promise<void> {
    try {
      const phHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
      const configs: photoAccessHelper.PhotoCreationConfig[] = [
        {
          title: `旋转_${Date.now()}`,
          fileNameExtension: 'mp4',
          photoType: photoAccessHelper.PhotoType.VIDEO,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
        }
      ];
      const destUris = await phHelper.showAssetsCreationDialog([filePath], configs);
      if (!destUris || destUris.length === 0) throw new Error('用户取消保存');
      const srcFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(destUris[0], fileIo.OpenMode.WRITE_ONLY);
      fileIo.copyFileSync(srcFile.fd, destFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(destFile);
      if (this.isPageAlive) {
        promptAction.showToast({ message: '旋转视频已保存到相册' });
        router.back();
      }
    } catch (err) {
      console.error('保存到图库失败:', err);
      if (this.isPageAlive) {
        promptAction.showToast({ message: `保存失败: ${err.message || '未知错误'}` });
      }
    } finally {
      try { fileIo.unlinkSync(filePath); } catch {}
    }
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
      .onClick(() => {
        if (this.isRotating) {
          promptAction.showToast({ message: '正在旋转，请使用"取消"按钮停止' });
        } else {
          router.back();
        }
      })
      .height(40)
      .width(40)
      .buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('视频旋转')
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

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(48).height(48)
          Text('加载视频中...').fontSize(16).fontColor($r('sys.color.font_secondary')).margin({ top: 12 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        Column({ space: 16 }) {
          Stack(){
            Image(`file://${this.framePath}`)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .rotate({ angle: this.getRotateAngle() })
              .scale({
                x: this.getScaleX(),
                y: this.getScaleY(),
                centerX: '50%',
                centerY: '50%'
              })
              .backgroundColor(Color.Transparent)
              .borderRadius(8)
          }
          .width('100%')
          .layoutWeight(1)
          .clip(true)   // 父容器裁剪

          Row() {
            Text('旋转方式')
              .width(80)
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
            Select(this.rotateOptions)
              .selected(0)
              .value(this.rotateOptions[0].value)
              .onSelect((index: number) => {
                const modes = ['none', 'clockwise90', 'counterclockwise90', 'rotate180', 'hflip', 'vflip'];
                this.rotateMode = modes[index] || 'none';
              })
              .layoutWeight(1)
              .height(40)
          }
          .width('90%')

          Button('旋转')
            .width('90%')
            .height(48)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.brand'))
            .fontColor(Color.White)
            .borderRadius(24)
            .onClick(() => this.startRotate())
            .enabled(!this.isRotating && this.rotateMode !== 'none')
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_tertiary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
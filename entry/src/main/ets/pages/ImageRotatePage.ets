import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommand, stopCommand, executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProcessingDialog } from '../components/ProcessingDialog';

@Builder
export function ImageRotatePageBuilder() {
  ImageRotatePage();
}

@Component
export struct ImageRotatePage {
  private pathStack: NavPathStack | null = null;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  @State imageUri: string = '';
  @State imageWidth: number = 0;
  @State imageHeight: number = 0;
  @State previewPath: string = '';          // 缓存的预览图片（原始图片拷贝）
  @State isLoading: boolean = true;

  @State rotateMode: string = 'none';
  @State isExporting: boolean = false;

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

  }

  aboutToDisappear() {
    this.isPageAlive = false;
    if (this.progressDialogController) {
      try { this.progressDialogController.close(); } catch {}
      this.progressDialogController = null;
    }
    const cacheDir = this.context.cacheDir + '/tools/rotate/';
    try { fileIo.unlinkSync(cacheDir + 'source_image.png'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'rotated_image.png'); } catch {}
  }

  private async prepareImage() {
    try {
      this.isLoading = true;
      // 复制图片到缓存，获取尺寸
      const cacheDir = this.context.cacheDir + '/tools/rotate/';
      try { fileIo.mkdirSync(cacheDir, true); } catch {}
      const destPath = cacheDir + 'source_image.png';
      await this.copyMediaUriToPath(this.imageUri, destPath);
      this.previewPath = destPath;

      // 获取图片尺寸
      const imageSource = image.createImageSource(destPath);
      const info = await imageSource.getImageInfo();
      this.imageWidth = info.size.width;
      this.imageHeight = info.size.height;

      this.isLoading = false;
    } catch (err) {
      console.error('加载图片失败:', (err as BusinessError).message);
      promptAction.showToast({ message: '加载图片失败' });
      this.pathStack?.pop();
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
    return ['-i', inputPath, '-vf', filter, '-y', outputPath];
  }

  private cancelProcess(): void {
    if (this.currentSessionId > 0) {
      stopCommand({ sessionId: this.currentSessionId });
    }
    this.cancelFlag = true;
  }

  private startRotate() {
    if (this.isExporting) return;
    this.cancelFlag = false;
    this.isExporting = true;

    this.progressDialogController = new CustomDialogController({
      builder: ProcessingDialog({
        processingText: '旋转图片中...',
        secondaryText: '旋转图片可能需要一些时间。',
        onCancel: () => this.cancelProcess()
      }),
      autoCancel: false,
      customStyle: true,
      cancel: () => this.cancelProcess()
    });
    this.progressDialogController.open();

    const cacheDir = this.context.cacheDir + '/tools/rotate/';
    const inputPath = cacheDir + 'source_image.png';
    const outputPath = cacheDir + 'rotated_image.png';
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
        console.info('旋转任务成功');
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
        console.info('旋转任务已取消');
        try { fileIo.unlinkSync(outputPath); } catch {}
        if (this.isPageAlive) {
          promptAction.showToast({ message: '已取消旋转' });
        }
        this.closeProgressDialog();
      },
      complete: (result) => {
        console.info('旋转任务结束');
        this.isExporting = false;
        this.currentSessionId = -1;
      }
    });
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
          title: `旋转_${Date.now()}`,
          fileNameExtension: 'png',
          photoType: photoAccessHelper.PhotoType.IMAGE,
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
        promptAction.showToast({ message: '旋转图片已保存到相册' });
        this.pathStack?.pop();
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

  @Builder
  buildTopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(24).width(24).height(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .onClick(() => {
        if (this.isExporting) {
          promptAction.showToast({ message: '正在处理，请使用"取消"按钮停止' });
        } else {
          this.pathStack?.pop();
        }
      })
      .height(40).width(40).buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('图片旋转')
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

  build() {
    NavDestination() {
      Column() {
        this.buildTopBar();

        if (this.isLoading) {
          Column() {
            LoadingProgress().width(48).height(48)
            Text('加载图片中...').fontSize(16).fontColor($r('sys.color.font_secondary')).margin({ top: 12 })
          }
          .layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
        } else {
          Column({ space: 16 }) {
            // 预览区域（应用旋转/翻转效果）
            Stack() {
              Image(`file://${this.previewPath}`)
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
            }
            .width('100%')
            .layoutWeight(1)
            .clip(true)

            Row() {
              Text('旋转方式').width(80).fontSize(16).fontColor($r('sys.color.font_primary'))
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
              .enabled(!this.isExporting && this.rotateMode !== 'none')
          }
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_tertiary'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onReady((context:NavDestinationContext)=>{
      this.pathStack = context.pathStack;
      const params = context.pathInfo.param as Record<string, string>;
      if (params.imageUri) {
        this.imageUri = params.imageUri;
        this.prepareImage();
      } else {
        this.pathStack.pop();
        return;
      }
    })
  }
}
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommand, stopCommand } from '@tyousan/ffmpeg';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProcessingDialog } from '../components/ProcessingDialog';
import { RenderRect,PixelPos,FfmpegResult,FfmpegError } from '../common/CommonInterfaces'
import { DraggableImageOverlay } from '../components/DraggableImageOverlay'

export interface ImageOverlayParams {
  baseImageUri: string;
  overlayImageUri: string;
}

@Builder
export function ImageOverlayPageBuilder() {
  ImageOverlayPage();
}

@Component
export struct ImageOverlayPage {
  private pathStack: NavPathStack | null = null;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  @State baseImageUri: string = '';
  @State overlayImageUri: string = '';
  @State baseWidth: number = 0;
  @State baseHeight: number = 0;
  @State previewPath: string = '';
  @State isLoading: boolean = true;

  @State overlayScale: number = 0.5;
  @State overlayAlpha: number = 1.0;

  @State positionX: number = 0;
  @State positionY: number = 0;
  @State displayPosX: number = 0;
  @State displayPosY: number = 0;

  @State overlayWidth: number = 0;
  @State overlayHeight: number = 0;
  @State overlayPreviewPath: string = '';

  @State renderRect: RenderRect = { x: 0, y: 0, width: 0, height: 0 };
  @State displayOverlayWidth: number = 0;
  @State displayOverlayHeight: number = 0;
  @State renderInitialized: boolean = false;

  @State isExporting: boolean = false;
  private currentSessionId: number = -1;
  private cancelFlag: boolean = false;
  private isPageAlive: boolean = true;
  private progressDialogController: CustomDialogController | null = null;

  aboutToAppear() {

  }

  aboutToDisappear() {
    this.isPageAlive = false;
    if (this.progressDialogController) {
      try { this.progressDialogController.close(); } catch {}
      this.progressDialogController = null;
    }
    const cacheDir = this.context.cacheDir + '/tools/overlay/';
    try { fileIo.unlinkSync(cacheDir + 'base.png'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'overlay.png'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'result.png'); } catch {}
  }

  private async prepareImages() {
    try {
      this.isLoading = true;
      const cacheDir = this.context.cacheDir + '/tools/overlay/';
      try { fileIo.mkdirSync(cacheDir, true); } catch {}

      const baseDest = cacheDir + 'base.png';
      await this.copyMediaUriToPath(this.baseImageUri, baseDest);
      this.previewPath = baseDest;

      const overlayDest = cacheDir + 'overlay.png';
      await this.copyMediaUriToPath(this.overlayImageUri, overlayDest);
      this.overlayPreviewPath = overlayDest;

      const baseSource = image.createImageSource(baseDest);
      const baseInfo = await baseSource.getImageInfo();
      this.baseWidth = baseInfo.size.width;
      this.baseHeight = baseInfo.size.height;

      const overlaySource = image.createImageSource(overlayDest);
      const overlayInfo = await overlaySource.getImageInfo();
      this.overlayWidth = overlayInfo.size.width;
      this.overlayHeight = overlayInfo.size.height;

      this.positionX = 10;
      this.positionY = 10;

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

  private calcRenderRect(containerW: number, containerH: number): RenderRect {
    if (containerW === 0 || containerH === 0 || this.baseWidth === 0 || this.baseHeight === 0) {
      return { x: 0, y: 0, width: 0, height: 0 };
    }
    const srcRatio = this.baseWidth / this.baseHeight;
    const displayRatio = containerW / containerH;
    let renderW: number, renderH: number, offsetX: number, offsetY: number;
    if (srcRatio > displayRatio) {
      renderW = containerW;
      renderH = containerW / srcRatio;
      offsetX = 0;
      offsetY = (containerH - renderH) / 2;
    } else {
      renderH = containerH;
      renderW = containerH * srcRatio;
      offsetX = (containerW - renderW) / 2;
      offsetY = 0;
    }
    return { x: offsetX, y: offsetY, width: renderW, height: renderH };
  }

  private screenToPixel(screenX: number, screenY: number): PixelPos {
    const rect = this.renderRect;
    if (rect.width === 0 || rect.height === 0) return { x: 0, y: 0 };
    const relX = (screenX - rect.x) / rect.width;
    const relY = (screenY - rect.y) / rect.height;
    const px = Math.max(0, Math.min(1, relX)) * this.baseWidth;
    const py = Math.max(0, Math.min(1, relY)) * this.baseHeight;
    return { x: Math.round(px), y: Math.round(py) };
  }

  private pixelToScreen(pixelX: number, pixelY: number): PixelPos {
    const rect = this.renderRect;
    if (rect.width === 0 || rect.height === 0) return { x: 0, y: 0 };
    const screenX = rect.x + (pixelX / this.baseWidth) * rect.width;
    const screenY = rect.y + (pixelY / this.baseHeight) * rect.height;
    return { x: screenX, y: screenY };
  }

  private updateDisplayOverlaySize() {
    if (this.renderRect.width > 0 && this.baseWidth > 0) {
      const scaleX = this.renderRect.width / this.baseWidth;
      const scaleY = this.renderRect.height / this.baseHeight;
      this.displayOverlayWidth = this.overlayWidth * this.overlayScale * scaleX;
      this.displayOverlayHeight = this.overlayHeight * this.overlayScale * scaleY;
    }
  }

  private buildOverlayCommand(inputPath: string, overlayPath: string, outputPath: string): string[] {
    const x = this.positionX;
    const y = this.positionY;
    const w = Math.round(this.overlayWidth * this.overlayScale);
    const h = Math.round(this.overlayHeight * this.overlayScale);
    const alpha = Math.max(0, Math.min(1, this.overlayAlpha));
    const filter = `[1:v]scale=${w}:${h},format=rgba,colorchannelmixer=aa=${alpha}[ov];[0:v][ov]overlay=${x}:${y}`;
    return ['-i', inputPath, '-i', overlayPath, '-filter_complex', filter, '-y', outputPath];
  }

  private cancelProcess(): void {
    if (this.currentSessionId > 0) {
      stopCommand({ sessionId: this.currentSessionId });
    }
    this.cancelFlag = true;
  }

  private startExport() {
    if (this.isExporting) return;
    this.cancelFlag = false;
    this.isExporting = true;

    this.progressDialogController = new CustomDialogController({
      builder: ProcessingDialog({
        processingText: '叠加图片中...',
        secondaryText: '叠加图片可能需要一些时间。',
        onCancel: () => this.cancelProcess()
      }),
      autoCancel: false,
      customStyle: true,
      cancel: () => this.cancelProcess()
    });
    this.progressDialogController.open();

    const cacheDir = this.context.cacheDir + '/tools/overlay/';
    const inputPath = cacheDir + 'base.png';
    const overlayPath = cacheDir + 'overlay.png';
    const outputPath = cacheDir + 'result.png';
    try { fileIo.unlinkSync(outputPath); } catch {}

    const args = this.buildOverlayCommand(inputPath, overlayPath, outputPath);
    console.info('FFmpeg 叠加参数:', args.join(' '));

    executeCommand({
      cmd: args.join(' '),
      start: (result: FfmpegResult) => {
        this.currentSessionId = result.sessionId ?? -1;
      },
      success: (result: FfmpegResult) => {
        if (!this.cancelFlag && this.isPageAlive) {
          this.saveToGallery(outputPath);
        } else {
          try { fileIo.unlinkSync(outputPath); } catch {}
        }
        this.closeProgressDialog();
        this.isExporting = false;
      },
      fail: (error: FfmpegError) => {
        console.error('叠加任务失败:', error);
        if (this.isPageAlive && !this.cancelFlag) {
          promptAction.showToast({ message: `叠加失败: ${error.message || '未知错误'}` });
        }
        try { fileIo.unlinkSync(outputPath); } catch {}
        this.closeProgressDialog();
        this.isExporting = false;
      },
      cancel: (result: FfmpegResult) => {
        try { fileIo.unlinkSync(outputPath); } catch {}
        if (this.isPageAlive) {
          promptAction.showToast({ message: '已取消叠加' });
        }
        this.closeProgressDialog();
        this.isExporting = false;
      },
      complete: (result: FfmpegResult) => {
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
          title: `叠加_${Date.now()}`,
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
        promptAction.showToast({ message: '叠加图片已保存到相册' });
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

      Text('叠加图片')
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
  buildControlPanel() {
    Column({ space: 8 }) {
      Row() {
        Text('大小').width(70).fontSize(16).fontColor($r('sys.color.font_primary'))
        Slider({ min: 0.1, max: 2.0, step: 0.05, value: this.overlayScale })
          .onChange((v: number) => {
            this.overlayScale = v;
            this.updateDisplayOverlaySize();
            if (this.renderInitialized) {
              const screenPos = this.pixelToScreen(this.positionX, this.positionY);
              this.displayPosX = screenPos.x;
              this.displayPosY = screenPos.y;
            }
          })
          .layoutWeight(1).selectedColor($r('app.color.brand'))
        Text(`${Math.round(this.overlayScale * 100)}%`).width(50).fontSize(16).textAlign(TextAlign.End)
      }
      .width('100%').padding({ left: 16, right: 16 })

      Row() {
        Text('不透明度').width(70).fontSize(16).fontColor($r('sys.color.font_primary'))
        Slider({ min: 0.1, max: 1.0, step: 0.05, value: this.overlayAlpha })
          .onChange((v: number) => { this.overlayAlpha = v; })
          .layoutWeight(1).selectedColor($r('app.color.brand'))
        Text(`${Math.round(this.overlayAlpha * 100)}%`).width(50).fontSize(16).textAlign(TextAlign.End)
      }
      .width('100%').padding({ left: 16, right: 16 })

      Row() {
        Text('位置').width(70).fontSize(16).fontColor($r('sys.color.font_primary'))
        Text(`(${this.positionX}, ${this.positionY})`)
          .fontSize(16).fontColor($r('sys.color.font_primary')).layoutWeight(1).textAlign(TextAlign.Start)
      }
      .width('100%').padding({ left: 16, right: 16 })
    }
    .width('90%').padding({ top: 8, bottom: 8 }).borderRadius(12)
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
          Column({ space: 12 }) {
            Stack() {
              Image(`file://${this.previewPath}`)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
                .backgroundColor(Color.Transparent)
                .onAreaChange((_, newArea) => {
                  const w = Number(newArea.width);
                  const h = Number(newArea.height);
                  if (w > 0 && h > 0) {
                    const rect = this.calcRenderRect(w, h);
                    this.renderRect = rect;
                    this.updateDisplayOverlaySize();
                    if (!this.renderInitialized) {
                      const screenPos = this.pixelToScreen(this.positionX, this.positionY);
                      this.displayPosX = screenPos.x;
                      this.displayPosY = screenPos.y;
                      this.renderInitialized = true;
                    }
                  }
                })

              if (this.renderInitialized && this.overlayPreviewPath) {
                DraggableImageOverlay({
                  imageUri: `file://${this.overlayPreviewPath}`,
                  imageWidth: this.displayOverlayWidth,
                  imageHeight: this.displayOverlayHeight,
                  imageAlpha: this.overlayAlpha,
                  x: this.displayPosX,
                  y: this.displayPosY,
                  renderRect: this.renderRect,
                  onPositionChange: (x: number, y: number) => {
                    this.displayPosX = x;
                    this.displayPosY = y;
                    const pixel = this.screenToPixel(x, y);
                    this.positionX = pixel.x;
                    this.positionY = pixel.y;
                  }
                })
              }
            }
            .width('100%').layoutWeight(1).clip(true)

            this.buildControlPanel()

            Button('叠加并导出')
              .width('90%')
              .height(48)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .backgroundColor($r('app.color.brand'))
              .fontColor(Color.White)
              .borderRadius(24)
              .onClick(() => this.startExport())
              .enabled(!this.isExporting)
          }
          .layoutWeight(1)
        }
      }
      .width('100%').height('100%')
      .backgroundColor($r('sys.color.background_tertiary'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const params = context.pathInfo.param as Record<string, string>;
      if (params.baseImageUri && params.overlayImageUri) {
        this.baseImageUri = params.baseImageUri;
        this.overlayImageUri = params.overlayImageUri;
        this.prepareImages();
      } else {
        this.pathStack.pop();
        return;
      }
    })
  }
}
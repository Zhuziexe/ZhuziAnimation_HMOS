import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommand, stopCommand, executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';
import { getVideoInfo } from '../common/VideoUtils';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProcessingDialog } from '../components/ProcessingDialog';
import { RenderRect,PixelPos,FfmpegResult,FfmpegError } from '../common/CommonInterfaces'
import {DraggableImageOverlay} from '../components/DraggableImageOverlay'

export interface VideoOverlayParams {
  videoUri: string;
  imageUri: string;
}

@Builder
export function VideoOverlayPageBuilder() {
  VideoOverlayPage();
}

@Component
export struct VideoOverlayPage {
  private pathStack: NavPathStack | null = null;
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  @State videoUri: string = '';
  @State imageUri: string = '';
  @State framePath: string = '';
  @State isLoading: boolean = true;
  @State videoWidth: number = 0;
  @State videoHeight: number = 0;

  @State watermarkImagePath: string = '';
  @State originalImageWidth: number = 0;
  @State originalImageHeight: number = 0;
  @State imageScale: number = 0.5;
  @State imageAlpha: number = 1.0;   // 新增不透明度

  @State positionX: number = 0;
  @State positionY: number = 0;
  @State displayPosX: number = 0;
  @State displayPosY: number = 0;

  @State containerWidth: number = 0;
  @State containerHeight: number = 0;
  @State renderRect: RenderRect = { x: 0, y: 0, width: 0, height: 0 };
  @State displayImageWidth: number = 0;
  @State displayImageHeight: number = 0;
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
    const cacheDir = this.context.cacheDir + '/tools/watermark/';
    try { fileIo.unlinkSync(cacheDir + 'preview_frame.png'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'tmp_video.mp4'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'watermark_image.png'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'watermarked_video.mp4'); } catch {}
  }

  private async prepareImageAndVideo() {
    try {
      const cacheDir = this.context.cacheDir + '/tools/watermark/';
      try { fileIo.mkdirSync(cacheDir, true); } catch {}
      const destPath = cacheDir + 'watermark_image.png';
      await this.copyMediaUriToPath(this.imageUri, destPath);
      this.watermarkImagePath = destPath;

      const imageSource = image.createImageSource(destPath);
      const info = await imageSource.getImageInfo();
      this.originalImageWidth = info.size.width;
      this.originalImageHeight = info.size.height;

      await this.prepareFrame();
    } catch (err) {
      console.error('准备图片或视频失败:', (err as BusinessError).message);
      promptAction.showDialog({
        title: '错误',
        message: '加载资源失败，请重试。',
        buttons: [{ text: '确定', color: '#007DFF' }],
      }).then(() => {
        if (this.isPageAlive) this.pathStack?.pop();
      });
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

  private async prepareFrame() {
    try {
      this.isLoading = true;
      if (!this.videoUri) throw new Error('视频URI为空');
      const info = await getVideoInfo(this.videoUri, this.context);
      if (info) {
        const stream = info.allProperties?.streams?.[0];
        if (stream) {
          const w = stream.width;
          const h = stream.height;
          this.videoWidth = (typeof w === 'number') ? w : (w ? parseInt(w as string, 10) : 1280);
          this.videoHeight = (typeof h === 'number') ? h : (h ? parseInt(h as string, 10) : 720);
        }
      }
      if (!this.videoWidth || !this.videoHeight) {
        this.videoWidth = 1280;
        this.videoHeight = 720;
      }

      const cacheDir = this.context.cacheDir + '/tools/watermark/';
      const inputPath = cacheDir + 'tmp_video.mp4';
      const framePath = cacheDir + 'preview_frame.png';

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
      this.pathStack?.pop();
    }
  }

  private calcRenderRect(containerW: number, containerH: number): RenderRect {
    if (containerW === 0 || containerH === 0 || this.videoWidth === 0 || this.videoHeight === 0) {
      return { x: 0, y: 0, width: 0, height: 0 };
    }
    const srcRatio = this.videoWidth / this.videoHeight;
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
    const px = Math.max(0, Math.min(1, relX)) * this.videoWidth;
    const py = Math.max(0, Math.min(1, relY)) * this.videoHeight;
    return { x: Math.round(px), y: Math.round(py) };
  }

  private pixelToScreen(pixelX: number, pixelY: number): PixelPos {
    const rect = this.renderRect;
    if (rect.width === 0 || rect.height === 0) return { x: 0, y: 0 };
    const screenX = rect.x + (pixelX / this.videoWidth) * rect.width;
    const screenY = rect.y + (pixelY / this.videoHeight) * rect.height;
    return { x: screenX, y: screenY };
  }

  private updateDisplaySize() {
    if (this.renderRect.width > 0 && this.videoWidth > 0 && this.originalImageWidth > 0) {
      const pixelW = this.originalImageWidth * this.imageScale;
      const pixelH = this.originalImageHeight * this.imageScale;
      this.displayImageWidth = pixelW * (this.renderRect.width / this.videoWidth);
      this.displayImageHeight = pixelH * (this.renderRect.height / this.videoHeight);
    }
  }

  private buildWatermarkCommand(inputPath: string, outputPath: string, watermarkPath: string): string[] {
    const x = this.positionX;
    const y = this.positionY;
    const w = Math.round(this.originalImageWidth * this.imageScale);
    const h = Math.round(this.originalImageHeight * this.imageScale);
    const alpha = Math.max(0.0, Math.min(1.0, this.imageAlpha));
    const filter = `[1:v]scale=${w}:${h},format=rgba,colorchannelmixer=aa=${alpha}[wm];[0:v][wm]overlay=${x}:${y}`;
    return ['-i', inputPath, '-i', watermarkPath, '-filter_complex', filter, '-c:a', 'copy', '-y', outputPath];
  }

  private cancelProcess():void{
    if (this.currentSessionId > 0) {
      stopCommand({ sessionId: this.currentSessionId });
    }
    this.cancelFlag = true;
  }

  private async startExport() {
    if (this.isExporting) return;
    if (!this.watermarkImagePath) {
      promptAction.showToast({ message: '请先选择要叠加的图片' });
      return;
    }

    this.cancelFlag = false;
    this.isExporting = true;

    this.progressDialogController = new CustomDialogController({
      builder: ProcessingDialog({
        processingText:'叠加图片中...',
        secondaryText:'叠加图片可能需要一些时间。',
        onCancel: () => this.cancelProcess()
      }),
      autoCancel: false,
      customStyle: true,
      cancel: ()=>this.cancelProcess()
    });
    this.progressDialogController.open();

    try {
      const cacheDir = this.context.cacheDir + '/tools/watermark/';
      const inputPath = cacheDir + 'tmp_video.mp4';
      const outputPath = cacheDir + 'watermarked_video.mp4';
      try { fileIo.unlinkSync(outputPath); } catch {}

      const args = this.buildWatermarkCommand(inputPath, outputPath, this.watermarkImagePath);
      console.info('FFmpeg 叠加图片参数:', args.join(' '));

      executeCommand({
        cmd: args.join(' '),
        start: (result: FfmpegResult) => {
          this.currentSessionId = result.sessionId ?? -1;
          console.info('叠加图片任务启动, sessionId:', this.currentSessionId);
        },
        success: (result: FfmpegResult) => {
          console.info('叠加图片任务成功');
          if (!this.cancelFlag && this.isPageAlive) {
            this.saveToGallery(outputPath);
          } else {
            try { fileIo.unlinkSync(outputPath); } catch {}
          }
          this.closeProgressDialog();
          this.isExporting = false;
        },
        fail: (error: FfmpegError) => {
          console.error('叠加图片任务失败，完整错误:', JSON.stringify(error));
          if (error.stderr) {
            console.error('stderr:', error.stderr);
          }
          if (this.isPageAlive && !this.cancelFlag) {
            promptAction.showToast({ message: `叠加图片失败: ${error.message || '未知错误'}` });
          }
          try { fileIo.unlinkSync(outputPath); } catch {}
          this.closeProgressDialog();
          this.isExporting = false;
        },
        cancel: (result: FfmpegResult) => {
          console.info('叠加图片任务已取消');
          try { fileIo.unlinkSync(outputPath); } catch {}
          if (this.isPageAlive) {
            promptAction.showToast({ message: '已取消叠加图片' });
          }
          this.closeProgressDialog();
          this.isExporting = false;
        },
        complete: (result: FfmpegResult) => {
          console.info('叠加图片任务结束');
          this.currentSessionId = -1;
        }
      });
    } catch (err) {
      console.error('准备叠加图片失败:', err);
      promptAction.showToast({ message: '准备叠加图片失败' });
      this.closeProgressDialog();
      this.isExporting = false;
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
          title: `水印_${Date.now()}`,
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
        promptAction.showToast({ message: '视频已保存到相册' });
        this.pathStack?.pop();
      }
    } catch (err) {
      console.error('保存到图库失败:', err);
      if (this.isPageAlive) {
        const errorMsg = (err as Error).message || '未知错误';
        promptAction.showToast({ message: `保存失败: ${errorMsg}` });
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

      Text('叠加图片到视频')
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
        Slider({
          min: 0.1,
          max: 2.0,
          step: 0.05,
          value: this.imageScale
        })
          .onChange((value: number) => {
            this.imageScale = value;
            this.updateDisplaySize();
            if (this.renderInitialized) {
              const screenPos = this.pixelToScreen(this.positionX, this.positionY);
              this.displayPosX = screenPos.x;
              this.displayPosY = screenPos.y;
            }
          })
          .layoutWeight(1)
          .selectedColor($r('app.color.brand'))
        Text(`${Math.round(this.imageScale * 100)}%`).width(50).fontSize(16).textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Row() {
        Text('不透明度').width(70).fontSize(16).fontColor($r('sys.color.font_primary'))
        Slider({
          min: 0.1,
          max: 1.0,
          step: 0.05,
          value: this.imageAlpha
        })
          .onChange((value: number) => {
            this.imageAlpha = value;
          })
          .layoutWeight(1)
          .selectedColor($r('app.color.brand'))
        Text(`${Math.round(this.imageAlpha * 100)}%`).width(50).fontSize(16).textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Row() {
        Text('位置').width(70).fontSize(16).fontColor($r('sys.color.font_primary'))
        Text(`(${this.positionX}, ${this.positionY})`)
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('90%')
    .padding({ top: 8, bottom: 8 })
    .borderRadius(12)
  }

  build() {
    NavDestination() {
      Column() {
        this.buildTopBar();

        if (this.isLoading) {
          Column() {
            LoadingProgress().width(48).height(48)
            Text('加载视频中...').fontSize(16).fontColor($r('sys.color.font_primary')).margin({ top: 12 })
          }
          .layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
        } else {
          Column({ space: 12 }) {
            Stack() {
              Image(`file://${this.framePath}`)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
                .backgroundColor(Color.Transparent)
                .onAreaChange((_, newArea) => {
                  const w = Number(newArea.width);
                  const h = Number(newArea.height);
                  if (w > 0 && h > 0) {
                    this.containerWidth = w;
                    this.containerHeight = h;
                    const rect = this.calcRenderRect(w, h);
                    this.renderRect = rect;
                    this.updateDisplaySize();
                    if (!this.renderInitialized && rect.width > 0 && rect.height > 0 && this.watermarkImagePath) {
                      this.positionX = 10;
                      this.positionY = 10;

                      const screenPos = this.pixelToScreen(10, 10);
                      this.displayPosX = screenPos.x;
                      this.displayPosY = screenPos.y;

                      this.renderInitialized = true;
                    }
                  }
                })

              if (this.renderInitialized && this.watermarkImagePath) {
                DraggableImageOverlay({
                  imageUri: `file://${this.watermarkImagePath}`,
                  imageWidth: this.displayImageWidth,
                  imageHeight: this.displayImageHeight,
                  imageAlpha: this.imageAlpha,
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
            .width('100%')
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .clip(true)

            this.buildControlPanel()

            Button('叠加图片并导出')
              .width('90%')
              .height(48)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .backgroundColor($r('app.color.brand'))
              .fontColor(Color.White)
              .borderRadius(24)
              .onClick(() => this.startExport())
              .enabled(!this.isExporting && this.watermarkImagePath.length > 0)
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
    .onReady((context: NavDestinationContext)=>{
      this.pathStack = context.pathStack;
      const params = context.pathInfo.param as Record<string, string>;
      if (params.videoUri && params.imageUri) {
        this.videoUri = params.videoUri;
        this.imageUri = params.imageUri;
        this.prepareImageAndVideo();
      } else {
        this.pathStack.pop();
        return;
      }
    })
  }
}
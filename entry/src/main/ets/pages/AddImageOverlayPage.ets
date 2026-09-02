import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommand, stopCommand, executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';
import { getVideoInfo } from '../common/VideoUtils';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProcessingDialog } from '../components/ProcessingDialog';

// ---------- 接口定义 ----------
interface RenderRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface PixelPos {
  x: number;
  y: number;
}

interface FfmpegResult {
  sessionId?: number;
}

interface FfmpegError {
  sessionId?: number;
  errCode?: number | string;
  message?: string;
  stderr?: string;
}

// ---------- 可拖动图片水印组件 ----------
@Component
struct DraggableImageOverlay {
  @Prop imageUri: string = '';
  @Prop imageWidth: number = 0;
  @Prop imageHeight: number = 0;
  @Prop imageAlpha: number = 1.0;
  @State x: number = 0;
  @State y: number = 0;
  @Prop renderRect: RenderRect = { x: 0, y: 0, width: 0, height: 0 };

  onPositionChange: (x: number, y: number) => void = () => {};

  private startX: number = 0;
  private startY: number = 0;
  private offsetX: number = 0;
  private offsetY: number = 0;
  private isDragging: boolean = false;

  build() {
    Image(this.imageUri)
      .width(this.imageWidth)
      .height(this.imageHeight)
      .objectFit(ImageFit.Fill)
      .opacity(this.imageAlpha)   // 预览时应用透明度
      .position({ x: this.x, y: this.y })
      .gesture(
        PanGesture({ direction: PanDirection.All, distance: 5 })
          .onActionStart((event: GestureEvent) => {
            this.isDragging = true;
            this.startX = event.fingerList[0].localX;
            this.startY = event.fingerList[0].localY;
            this.offsetX = this.x;
            this.offsetY = this.y;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.isDragging) return;
            let newX = this.offsetX + (event.fingerList[0].localX - this.startX);
            let newY = this.offsetY + (event.fingerList[0].localY - this.startY);

            const minX = this.renderRect.x;
            const minY = this.renderRect.y;
            const maxX = this.renderRect.x + this.renderRect.width - this.imageWidth;
            const maxY = this.renderRect.y + this.renderRect.height - this.imageHeight;
            newX = Math.max(minX, Math.min(newX, maxX));
            newY = Math.max(minY, Math.min(newY, maxY));

            this.x = newX;
            this.y = newY;
            this.onPositionChange(newX, newY);
          })
          .onActionEnd(() => {
            this.isDragging = false;
          })
      )
      .hitTestBehavior(HitTestMode.Default)
      .border({ width: 2, color: '#00BFFF', style: BorderStyle.Solid })
  }
}

// ---------- 主页面 ----------
@Entry
@Component
struct AddImageOverlayPage {
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;

  // 从路由参数接收视频URI和图片URI（图片已由调用方选择）
  @State videoUri: string = '';
  @State imageUri: string = '';
  @State framePath: string = '';
  @State isLoading: boolean = true;
  @State videoWidth: number = 0;
  @State videoHeight: number = 0;

  // 水印图片相关
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

  // ---------- 生命周期 ----------
  aboutToAppear() {
    const params = router.getParams() as Record<string, string> | undefined;
    if (params && params['videoUri'] && params['imageUri']) {
      this.videoUri = params['videoUri'];
      this.imageUri = params['imageUri'];
      this.prepareImageAndVideo();
    } else {
      promptAction.showToast({ message: '缺少必要参数' });
      router.back();
    }
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

  // ---------- 准备图片和视频 ----------
  private async prepareImageAndVideo() {
    try {
      // 1. 复制图片到缓存，获取尺寸
      const cacheDir = this.context.cacheDir + '/tools/watermark/';
      try { fileIo.mkdirSync(cacheDir, true); } catch {}
      const destPath = cacheDir + 'watermark_image.png';
      await this.copyMediaUriToPath(this.imageUri, destPath);
      this.watermarkImagePath = destPath;

      const imageSource = image.createImageSource(destPath);
      const info = await imageSource.getImageInfo();
      this.originalImageWidth = info.size.width;
      this.originalImageHeight = info.size.height;

      // 2. 准备视频预览帧
      await this.prepareFrame();
    } catch (err) {
      console.error('准备图片或视频失败:', (err as BusinessError).message);
      promptAction.showDialog({
        title: '错误',
        message: '加载资源失败，请重试。',
        buttons: [{ text: '确定', color: '#007DFF' }],
      }).then(() => {
        if (this.isPageAlive) router.back();
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

  // ---------- 准备视频预览帧 ----------
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
      router.back();
    }
  }

  // ---------- 计算渲染矩形 ----------
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

  // ---------- 构建 FFmpeg 命令（增加透明度） ----------
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

  // ---------- 保存到相册 ----------
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
        router.back();
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

  // ---------- UI 构建 ----------
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
          router.back();
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

      // 新增不透明度滑块
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
                    const margin = 20;
                    const maxPixelX = this.videoWidth - margin;
                    const maxPixelY = this.videoHeight - margin;
                    const pixelW = this.originalImageWidth * this.imageScale;
                    const pixelH = this.originalImageHeight * this.imageScale;
                    let initPixelX = maxPixelX - pixelW;
                    let initPixelY = maxPixelY - pixelH;
                    initPixelX = Math.max(0, initPixelX);
                    initPixelY = Math.max(0, initPixelY);

                    this.positionX = initPixelX;
                    this.positionY = initPixelY;

                    const screenPos = this.pixelToScreen(initPixelX, initPixelY);
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
}
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommand, stopCommand, executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';
import { getVideoInfo } from '../common/VideoUtils';
import { util } from '@kit.ArkTS';
import { PickColorDialog } from '../components/PickColorDialog';
import { ProcessingDialog } from '../components/ProcessingDialog';
import { RenderRect,PixelPos,FfmpegResult,FfmpegError } from '../common/CommonInterfaces'
import { DraggableWatermark } from '../components/DraggableWatermark'

@Builder
export function VideoWatermarkPageBuilder() {
  VideoWatermarkPage();
}

@Component
export struct VideoWatermarkPage {
  private pathStack: NavPathStack | null = null;
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private colorPickerController: CustomDialogController | null = null;

  @State videoUri: string = '';
  @State framePath: string = '';
  @State isLoading: boolean = true;
  @State videoWidth: number = 0;
  @State videoHeight: number = 0;

  @State watermarkText: string = '我的水印';
  @State fontSize: number = 60;               // 视频像素大小
  @State fontColor: string = '#FF0000';
  @State alpha: number = 0.8;

  // 视频像素坐标（用于导出）
  @State positionX: number = 0;
  @State positionY: number = 0;
  // 显示坐标（用于预览拖动）
  @State displayPosX: number = 0;
  @State displayPosY: number = 0;

  @State containerWidth: number = 0;
  @State containerHeight: number = 0;
  @State renderRect: RenderRect = { x: 0, y: 0, width: 0, height: 0 };
  @State displayFontSize: number = 20;
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
    try { fileIo.unlinkSync(cacheDir + 'watermark.png'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'watermarked_video.mp4'); } catch {}
  }

  // ---------- 准备预览帧 ----------
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
      try { fileIo.mkdirSync(cacheDir, true); } catch {}
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

  // 屏幕坐标 → 视频像素坐标
  private screenToPixel(screenX: number, screenY: number): PixelPos {
    const rect = this.renderRect;
    if (rect.width === 0 || rect.height === 0) return { x: 0, y: 0 };
    const relX = (screenX - rect.x) / rect.width;
    const relY = (screenY - rect.y) / rect.height;
    const px = Math.max(0, Math.min(1, relX)) * this.videoWidth;
    const py = Math.max(0, Math.min(1, relY)) * this.videoHeight;
    return { x: Math.round(px), y: Math.round(py) };
  }

  // 视频像素坐标 → 屏幕坐标（用于显示位置）
  private pixelToScreen(pixelX: number, pixelY: number): PixelPos {
    const rect = this.renderRect;
    if (rect.width === 0 || rect.height === 0) return { x: 0, y: 0 };
    const screenX = rect.x + (pixelX / this.videoWidth) * rect.width;
    const screenY = rect.y + (pixelY / this.videoHeight) * rect.height;
    return { x: screenX, y: screenY };
  }

  private updateDisplayFontSize() {
    if (this.renderRect.width > 0 && this.videoWidth > 0) {
      this.displayFontSize = this.fontSize * (this.renderRect.width / this.videoWidth);
    }
  }

  // ---------- 生成水印图片（无旋转） ----------
  private async generateWatermarkImage(): Promise<string> {
    // 计算文字大小
    const tempCtx = new OffscreenCanvas(1, 1).getContext('2d');
    tempCtx.font = `${this.fontSize}px sans-serif`;
    const metrics = tempCtx.measureText(this.watermarkText);
    const textWidth = metrics.width;
    const textHeight = this.fontSize * 1.2;
    const padding = this.fontSize * 0.3;
    const canvasWidth = Math.ceil(textWidth + padding * 2);
    const canvasHeight = Math.ceil(textHeight + padding * 2);

    const canvas = new OffscreenCanvas(canvasWidth, canvasHeight);
    const ctx = canvas.getContext('2d');

    ctx.clearRect(0, 0, canvasWidth, canvasHeight);
    ctx.font = `${this.fontSize}px sans-serif`;
    ctx.fillStyle = this.fontColor;
    ctx.globalAlpha = this.alpha;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    // 直接绘制在左上角（无旋转）
    ctx.fillText(this.watermarkText, 0, 0);

    const dataUrl = ctx.toDataURL('image/png');
    const base64Data = dataUrl.split(',')[1];
    const base64Helper = new util.Base64Helper();
    const decodedData = base64Helper.decodeSync(base64Data) as Uint8Array;
    const buffer = decodedData.buffer;

    const cacheDir = this.context.cacheDir + '/tools/watermark/';
    const imagePath = cacheDir + 'watermark.png';
    const file = fileIo.openSync(imagePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(file.fd, buffer);
    fileIo.closeSync(file);
    return imagePath;
  }

  // ---------- 构建 FFmpeg 命令（简单 overlay） ----------
  private buildWatermarkCommand(inputPath: string, outputPath: string, watermarkPath: string): string[] {
    // 使用视频像素坐标（positionX/Y）
    const x = this.positionX;
    const y = this.positionY;
    const filter = `overlay=${x}:${y}`;
    return ['-i', inputPath, '-i', watermarkPath, '-filter_complex', filter, '-c:a', 'copy', '-y', outputPath];
  }

  private cancelProcess():void{
    if (this.currentSessionId > 0) {
      stopCommand({ sessionId: this.currentSessionId });
    }
    this.cancelFlag = true;
  }

  // ---------- 导出 ----------
  private async startExport() {
    if (this.isExporting) return;
    if (!this.watermarkText.trim()) {
      promptAction.showToast({ message: '请输入水印文字' });
      return;
    }

    this.cancelFlag = false;
    this.isExporting = true;

    this.progressDialogController = new CustomDialogController({
      builder: ProcessingDialog({
        processingText:'添加水印中...',
        secondaryText:'添加水印可能需要一些时间。',
        onCancel: () => this.cancelProcess()
      }),
      autoCancel: false,
      customStyle: true,
      cancel:()=>this.cancelProcess()
    });
    this.progressDialogController.open();

    try {
      const watermarkPath = await this.generateWatermarkImage();
      const cacheDir = this.context.cacheDir + '/tools/watermark/';
      const inputPath = cacheDir + 'tmp_video.mp4';
      const outputPath = cacheDir + 'watermarked_video.mp4';
      try { fileIo.unlinkSync(outputPath); } catch {}

      const args = this.buildWatermarkCommand(inputPath, outputPath, watermarkPath);
      console.info('FFmpeg 水印参数:', args.join(' '));

      executeCommand({
        cmd: args.join(' '),
        start: (result: FfmpegResult) => {
          this.currentSessionId = result.sessionId ?? -1;
          console.info('水印任务启动, sessionId:', this.currentSessionId);
        },
        success: (result: FfmpegResult) => {
          console.info('水印任务成功');
          if (!this.cancelFlag && this.isPageAlive) {
            this.saveToGallery(outputPath);
          } else {
            try { fileIo.unlinkSync(outputPath); } catch {}
          }
          this.closeProgressDialog();
          this.isExporting = false;
        },
        fail: (error: FfmpegError) => {
          console.error('水印任务失败，完整错误:', JSON.stringify(error));
          if (error.stderr) {
            console.error('stderr:', error.stderr);
          }
          if (this.isPageAlive && !this.cancelFlag) {
            promptAction.showToast({ message: `添加水印失败: ${error.message || '未知错误'}` });
          }
          try { fileIo.unlinkSync(outputPath); } catch {}
          this.closeProgressDialog();
          this.isExporting = false;
        },
        cancel: (result: FfmpegResult) => {
          console.info('水印任务已取消');
          try { fileIo.unlinkSync(outputPath); } catch {}
          if (this.isPageAlive) {
            promptAction.showToast({ message: '已取消添加水印' });
          }
          this.closeProgressDialog();
          this.isExporting = false;
        },
        complete: (result: FfmpegResult) => {
          console.info('水印任务结束');
          this.currentSessionId = -1;
        }
      });
    } catch (err) {
      console.error('准备水印失败:', err);
      promptAction.showToast({ message: '准备水印失败' });
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
        promptAction.showToast({ message: '水印视频已保存到相册' });
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
          this.pathStack?.pop();
        }
      })
      .height(40).width(40).buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('添加文字水印')
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
    Column({ space: 6 }) {
      Row() {
        Text('水印文字').width(70).fontSize(16).fontColor($r('sys.color.font_primary'))
        TextInput({ text: this.watermarkText, placeholder: '输入水印内容' })
          .layoutWeight(1)
          .height(36)
          .onChange((value: string) => {
            this.watermarkText = value;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Row() {
        Text('字体大小').width(70).fontSize(16).fontColor($r('sys.color.font_primary'))
        Slider({
          min: 20,
          max: 200,
          step: 2,
          value: this.fontSize
        })
          .onChange((value: number) => {
            this.fontSize = value;
            this.updateDisplayFontSize();
            // 更新显示坐标
            if (this.renderInitialized) {
              const screenPos = this.pixelToScreen(this.positionX, this.positionY);
              this.displayPosX = screenPos.x;
              this.displayPosY = screenPos.y;
            }
          })
          .layoutWeight(1)
          .selectedColor($r('app.color.brand'))
        Text(`${this.fontSize}`).width(40).fontSize(16).textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Row() {
        Text('颜色').width(70).fontSize(16).fontColor($r('sys.color.font_primary'))

        Button() {
          Row() {
            // 显示当前颜色的色块
            Row()
              .layoutWeight(1)
              .height(24)
              .borderRadius(12)
              .backgroundColor(this.fontColor)
              .margin({ right: 8 })
            Text(this.fontColor)
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
          }
          .padding({ left: 12, right: 12 })
          .height(40)
        }
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick(() => {
          // 创建并打开颜色选择弹窗
          if (this.colorPickerController) {
            this.colorPickerController.close();
            this.colorPickerController = null;
          }
          this.colorPickerController = new CustomDialogController({
            builder: PickColorDialog({
              currentColor: this.fontColor,
              onColorSelected: (color: string) => {
                this.fontColor = color;
              }
            }),
            alignment: DialogAlignment.Center,
            maskColor: 'rgba(0, 0, 0, 0.5)'
          });
          this.colorPickerController.open();
        })
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Row() {
        Text('不透明度').width(70).fontSize(16).fontColor($r('sys.color.font_primary'))
        Slider({
          min: 0.1,
          max: 1.0,
          step: 0.05,
          value: this.alpha
        })
          .onChange((value: number) => {
            this.alpha = value;
          })
          .layoutWeight(1)
          .selectedColor($r('app.color.brand'))
        Text(`${Math.round(this.alpha * 100)}%`).width(40).fontSize(16).textAlign(TextAlign.End)
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
                    this.updateDisplayFontSize();
                    if (!this.renderInitialized && rect.width > 0 && rect.height > 0) {
                      this.positionX = 10;
                      this.positionY = 10;

                      // 转换为屏幕坐标
                      const screenPos = this.pixelToScreen(10, 10);
                      this.displayPosX = screenPos.x;
                      this.displayPosY = screenPos.y;

                      this.renderInitialized = true;
                    }
                  }
                })

              if (this.renderInitialized) {
                DraggableWatermark({
                  text: this.watermarkText,
                  fontSize: this.displayFontSize,
                  fontColor: this.fontColor,
                  alpha: this.alpha,
                  x: this.displayPosX,
                  y: this.displayPosY,
                  renderRect: this.renderRect,
                  onPositionChange: (x: number, y: number) => {
                    // 更新显示坐标
                    this.displayPosX = x;
                    this.displayPosY = y;
                    // 转换为视频像素坐标
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

            Button('添加水印并导出')
              .width('90%')
              .height(48)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .backgroundColor($r('app.color.brand'))
              .fontColor(Color.White)
              .borderRadius(24)
              .onClick(() => this.startExport())
              .enabled(!this.isExporting && this.watermarkText.trim().length > 0)
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
    .onReady((context:NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const params = context.pathInfo.param as Record<string, string>;
      if (params.videoUri) {
        this.videoUri = params.videoUri;
        this.prepareFrame();
      } else {
        this.pathStack.pop();
        return;
      }
    })
  }
}
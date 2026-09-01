// VideoBlurPage.ets
import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommand, stopCommand, executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';
import { getVideoInfo } from '../common/VideoUtils';

interface CropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

@CustomDialog
struct BlurProgressDialog {
  controller: CustomDialogController;
  onCancel: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      LoadingProgress().width(48).height(48)
      Text('模糊处理中...').fontSize(18).fontColor($r('sys.color.font_primary'))
      Text('模糊视频区域可能需要一些时间。').fontSize(14).fontColor($r('sys.color.font_secondary'))
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
struct VideoBlurPage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  @State videoUri: string = '';
  @State rawWidth: number = 0;
  @State rawHeight: number = 0;
  @State framePath: string = '';
  @State crop: CropRect = { x: 0, y: 0, width: 0, height: 0 };
  @State displayWidth: number = 0;
  @State displayHeight: number = 0;
  @State renderX: number = 0;
  @State renderY: number = 0;
  @State renderW: number = 0;
  @State renderH: number = 0;
  @State isLoading: boolean = true;
  @State isExporting: boolean = false;
  @State pixelInfo: string = '等待选择区域';
  private cropInitialized: boolean = false;
  private progressDialogController: CustomDialogController | null = null;
  private currentSessionId: number = -1;
  private cancelFlag: boolean = false;
  private isPageAlive: boolean = true;

  // 模糊方式：0-普通模糊，1-高斯模糊
  @State blurMode: number = 0;
  private blurModeOptions: SelectOption[] = [
    { value: '普通模糊' },
    { value: '高斯模糊' }
  ];
  @State blurStrength: number = 10; // 模糊强度：普通模糊为半径，高斯模糊为sigma

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
      try { this.progressDialogController.close(); } catch {}
      this.progressDialogController = null;
    }
    const cacheDir = this.context.cacheDir + '/tools/blurvideo/';
    try { fileIo.unlinkSync(cacheDir + 'blur_frame.png'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'tmp_video.mp4'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'blurred_video.mp4'); } catch {}
  }

  private async prepareFrame() {
    try {
      this.isLoading = true;
      const info = await getVideoInfo(this.videoUri, this.context);
      if (!info) throw new Error('无法获取视频信息');

      if (info.allProperties?.streams?.length) {
        const stream = info.allProperties.streams[0];
        const w = stream.width;
        const h = stream.height;
        this.rawWidth = (typeof w === 'number') ? w : (typeof w === 'string' ? parseInt(w, 10) : 1280);
        this.rawHeight = (typeof h === 'number') ? h : (typeof h === 'string' ? parseInt(h, 10) : 720);
      } else {
        this.rawWidth = 1280;
        this.rawHeight = 720;
      }

      const cacheDir = this.context.cacheDir + '/tools/blurvideo/';
      try { fileIo.mkdirSync(cacheDir, true); } catch {}
      const inputPath = cacheDir + 'tmp_video.mp4';
      const framePath = cacheDir + 'blur_frame.png';

      await this.copyMediaUriToPath(this.videoUri, inputPath);
      const cmd = `-i "${inputPath}" -frames:v 1 -y "${framePath}"`;
      const result: CommandSyncResult = executeCommandSync(cmd);
      if (result.evenType !== 'onSuccess') throw new Error('提取第一帧失败');

      fileIo.statSync(framePath);
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

  private updateRenderRect(containerW: number, containerH: number) {
    if (containerW === 0 || containerH === 0 || this.rawWidth === 0 || this.rawHeight === 0) return;
    const scale = Math.min(containerW / this.rawWidth, containerH / this.rawHeight);
    const rw = this.rawWidth * scale;
    const rh = this.rawHeight * scale;
    this.renderX = (containerW - rw) / 2;
    this.renderY = (containerH - rh) / 2;
    this.renderW = rw;
    this.renderH = rh;
  }

  private updateCrop(newCrop: CropRect) {
    const minSize = 20;
    const renderLeft = this.renderX;
    const renderRight = this.renderX + this.renderW;
    const renderTop = this.renderY;
    const renderBottom = this.renderY + this.renderH;
    let x = Math.max(renderLeft, Math.min(newCrop.x, renderRight - newCrop.width));
    let y = Math.max(renderTop, Math.min(newCrop.y, renderBottom - newCrop.height));
    let w = Math.max(minSize, Math.min(newCrop.width, renderRight - x));
    let h = Math.max(minSize, Math.min(newCrop.height, renderBottom - y));
    if (x + w > renderRight) { x = renderRight - w; }
    if (y + h > renderBottom) { y = renderBottom - h; }
    const rect: CropRect = { x, y, width: w, height: h };
    this.crop = rect;
    this.updatePixelInfo(rect);
  }

  private updatePixelInfo(c: CropRect) {
    if (this.renderW === 0 || this.renderH === 0 || this.rawWidth === 0 || this.rawHeight === 0) {
      this.pixelInfo = '等待视频加载';
      return;
    }
    const relX = (c.x - this.renderX) / this.renderW;
    const relY = (c.y - this.renderY) / this.renderH;
    const relW = c.width / this.renderW;
    const relH = c.height / this.renderH;
    const pixelX = Math.round(relX * this.rawWidth);
    const pixelY = Math.round(relY * this.rawHeight);
    const pixelW = Math.round(relW * this.rawWidth);
    const pixelH = Math.round(relH * this.rawHeight);
    this.pixelInfo = `模糊区域: (${pixelX}, ${pixelY})  大小: ${pixelW}×${pixelH}`;
  }

  private onCropChange(newCrop: CropRect) {
    this.updateCrop(newCrop);
  }

  private doBlurAsync() {
    if (this.isExporting) return;
    if (this.crop.width < 10 || this.crop.height < 10) {
      promptAction.showToast({ message: '模糊区域太小' });
      return;
    }

    this.cancelFlag = false;
    this.isExporting = true;

    this.progressDialogController = new CustomDialogController({
      builder: BlurProgressDialog({
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

    const cacheDir = this.context.cacheDir + '/tools/blurvideo/';
    const inputPath = cacheDir + 'tmp_video.mp4';
    const outputPath = cacheDir + 'blurred_video.mp4';

    const displayWidth = this.displayWidth;
    const displayHeight = this.displayHeight;
    const srcRatio = this.rawWidth / this.rawHeight;
    const displayRatio = displayWidth / displayHeight;

    let renderWidth: number, renderHeight: number;
    let offsetX: number, offsetY: number;
    if (srcRatio > displayRatio) {
      renderWidth = displayWidth;
      renderHeight = displayWidth / srcRatio;
      offsetX = 0;
      offsetY = (displayHeight - renderHeight) / 2;
    } else {
      renderHeight = displayHeight;
      renderWidth = displayHeight * srcRatio;
      offsetX = (displayWidth - renderWidth) / 2;
      offsetY = 0;
    }

    const relX = (this.crop.x - offsetX) / renderWidth;
    const relY = (this.crop.y - offsetY) / renderHeight;
    const relW = this.crop.width / renderWidth;
    const relH = this.crop.height / renderHeight;

    const pixelX = Math.round(relX * this.rawWidth);
    const pixelY = Math.round(relY * this.rawHeight);
    const pixelW = Math.round(relW * this.rawWidth);
    const pixelH = Math.round(relH * this.rawHeight);

    const finalX = Math.max(0, Math.min(pixelX, this.rawWidth - pixelW));
    const finalY = Math.max(0, Math.min(pixelY, this.rawHeight - pixelH));
    const finalW = Math.min(pixelW, this.rawWidth - finalX);
    const finalH = Math.min(pixelH, this.rawHeight - finalY);

    if (finalW < 10 || finalH < 10) {
      promptAction.showToast({ message: '模糊区域映射到视频后太小' });
      this.isExporting = false;
      this.closeProgressDialog();
      return;
    }

    try { fileIo.unlinkSync(outputPath); } catch {}

    // 构建滤镜链：crop + blur + overlay
    const strength = Math.round(this.blurStrength);
    let blurFilter: string;
    if (this.blurMode === 0) {
      // 普通模糊 boxblur
      blurFilter = `boxblur=${strength}:1`; // luma_radius:luma_power
    } else {
      // 高斯模糊 gblur
      blurFilter = `gblur=sigma=${strength}`;
    }
    const filterComplex = `[0:v]crop=${finalW}:${finalH}:${finalX}:${finalY},${blurFilter}[blurred];[0:v][blurred]overlay=${finalX}:${finalY}`;
    const args = ['-i', inputPath, '-filter_complex', filterComplex, '-c:a', 'copy', '-y', outputPath];

    console.info('FFmpeg 模糊参数:', args.join(' '));

    executeCommand({
      cmd: args.join(' '),
      start: (result) => {
        this.currentSessionId = result.sessionId;
        console.info('模糊任务启动, sessionId:', this.currentSessionId);
      },
      success: (result) => {
        console.info('模糊任务成功:', result);
        if (!this.cancelFlag && this.isPageAlive) {
          this.saveToGallery(outputPath);
        } else {
          try { fileIo.unlinkSync(outputPath); } catch {}
        }
        this.closeProgressDialog();
      },
      fail: (error) => {
        console.error('模糊任务失败:', error);
        if (this.isPageAlive && !this.cancelFlag) {
          promptAction.showToast({ message: `模糊失败: ${error.message || '未知错误'}` });
        }
        try { fileIo.unlinkSync(outputPath); } catch {}
        this.closeProgressDialog();
      },
      cancel: (result) => {
        console.info('模糊任务已取消:', result);
        try { fileIo.unlinkSync(outputPath); } catch {}
        if (this.isPageAlive) {
          promptAction.showToast({ message: '已取消模糊' });
        }
        this.closeProgressDialog();
      },
      complete: (result) => {
        console.info('模糊任务结束:', result);
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

  private async doBlur() {
    this.doBlurAsync();
  }

  private async saveToGallery(filePath: string): Promise<void> {
    try {
      const phHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
      const configs: photoAccessHelper.PhotoCreationConfig[] = [
        {
          title: `模糊_${Date.now()}`,
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
        promptAction.showToast({ message: '模糊视频已保存到相册' });
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
          .fontSize(24).width(24).height(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .onClick(() => {
        if (this.isExporting) {
          promptAction.showToast({ message: '正在模糊，请使用"取消"按钮停止' });
        } else {
          router.back();
        }
      })
      .height(40).width(40).buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('视频区域模糊')
        .layoutWeight(1)
        .fontSize(18)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.LEFT)
    }
    .width('100%').height(56)
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
        .layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
      } else {
        Column({ space: 12 }) {
          Stack() {
            Image(`file://${this.framePath}`)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
              .onAreaChange((_, newArea) => {
                const w = Number(newArea.width);
                const h = Number(newArea.height);
                if (w > 0 && h > 0) {
                  this.displayWidth = w;
                  this.displayHeight = h;
                  this.updateRenderRect(w, h);
                  if (!this.cropInitialized && this.renderW > 0 && this.renderH > 0) {
                    const margin = 20;
                    const rect: CropRect = {
                      x: this.renderX + margin,
                      y: this.renderY + margin,
                      width: this.renderW - margin * 2,
                      height: this.renderH - margin * 2
                    };
                    if (rect.width > 0 && rect.height > 0) {
                      this.crop = rect;
                      this.cropInitialized = true;
                      this.updatePixelInfo(rect);
                    }
                  }
                }
              })
              .onError((err) => console.error('Image加载失败:', err))

            BlurOverlay({
              cropRect: this.crop,
              imageWidth: this.displayWidth,
              imageHeight: this.displayHeight,
              renderX: this.renderX,
              renderY: this.renderY,
              renderWidth: this.renderW,
              renderHeight: this.renderH,
              onCropChange: (newCrop: CropRect) => { this.onCropChange(newCrop); }
            })
              .width('100%')
              .height('100%')
              .position({ x: 0, y: 0 })
          }
          .width('100%')
          .layoutWeight(1)

          // 模糊方式选择
          Row() {
            Text('模糊方式')
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
              .width(70)
            Select(this.blurModeOptions)
              .value(this.blurModeOptions[this.blurMode].value)
              .selected(this.blurMode)
              .onSelect((index: number) => {
                this.blurMode = index;
              })
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          // 模糊程度滑块（两种模式均可用）
          Row() {
            Text('模糊程度')
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
              .width(70)
            Slider({
              min: 1,
              max: 20,
              step: 1,
              value: this.blurStrength
            })
              .onChange((value: number) => {
                this.blurStrength = value;
              })
              .layoutWeight(1)
              .selectedColor($r('app.color.brand'))
            Text(`${this.blurStrength}`)
              .fontSize(16)
              .width(40)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Row() {
            Text(this.pixelInfo)
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .height(30)

          Button('模糊区域')
            .width('90%')
            .height(48)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.brand'))
            .fontColor(Color.White)
            .borderRadius(24)
            .onClick(() => this.doBlur())
            .enabled(!this.isExporting && this.crop.width > 10 && this.crop.height > 10)
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

// ---- 自定义覆盖层：只蒙版选中区域（黑色半透明），其余透明 ----
@Component
struct BlurOverlay {
  @Prop @Watch('onCropChanged') cropRect: CropRect = { x: 0, y: 0, width: 0, height: 0 };
  @Prop @Watch('onSizeChanged') imageWidth: number = 0;
  @Prop @Watch('onSizeChanged') imageHeight: number = 0;
  @Prop @Watch('onSizeChanged') renderX: number = 0;
  @Prop @Watch('onSizeChanged') renderY: number = 0;
  @Prop @Watch('onSizeChanged') renderWidth: number = 0;
  @Prop @Watch('onSizeChanged') renderHeight: number = 0;
  onCropChange: (newRect: CropRect) => void = () => {};

  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private dragMode: string = 'none';
  private startX: number = 0;
  private startY: number = 0;
  private startCrop: CropRect = { x: 0, y: 0, width: 0, height: 0 };

  private draw() {
    const ctx = this.ctx;
    const w = this.imageWidth;
    const h = this.imageHeight;
    if (!ctx || w === 0 || h === 0) return;
    ctx.clearRect(0, 0, w, h);
    const c = this.cropRect;
    // 只填充选中区域（半透明黑色，表示要模糊）
    ctx.fillStyle = 'rgba(0,0,0,0.6)';
    ctx.fillRect(c.x, c.y, c.width, c.height);
    // 绘制白色边框和手柄
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 2;
    ctx.strokeRect(c.x, c.y, c.width, c.height);
    const handleSize = 20;
    ctx.fillStyle = '#FFFFFF';
    const corners: [number, number][] = [
      [c.x, c.y],
      [c.x + c.width - handleSize, c.y],
      [c.x, c.y + c.height - handleSize],
      [c.x + c.width - handleSize, c.y + c.height - handleSize]
    ];
    for (let i = 0; i < corners.length; i++) {
      ctx.fillRect(corners[i][0], corners[i][1], handleSize, handleSize);
    }
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.moveTo(c.x + c.width / 2 - 10, c.y);
    ctx.lineTo(c.x + c.width / 2 + 10, c.y);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(c.x + c.width / 2 - 10, c.y + c.height);
    ctx.lineTo(c.x + c.width / 2 + 10, c.y + c.height);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(c.x, c.y + c.height / 2 - 10);
    ctx.lineTo(c.x, c.y + c.height / 2 + 10);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(c.x + c.width, c.y + c.height / 2 - 10);
    ctx.lineTo(c.x + c.width, c.y + c.height / 2 + 10);
    ctx.stroke();
  }

  private getHitMode(tx: number, ty: number): string {
    const c = this.cropRect;
    const s = 30;
    if (tx >= c.x - s && tx <= c.x + s && ty >= c.y - s && ty <= c.y + s) return 'top-left';
    if (tx >= c.x + c.width - s && tx <= c.x + c.width + s && ty >= c.y - s && ty <= c.y + s) return 'top-right';
    if (tx >= c.x - s && tx <= c.x + s && ty >= c.y + c.height - s && ty <= c.y + c.height + s) return 'bottom-left';
    if (tx >= c.x + c.width - s && tx <= c.x + c.width + s && ty >= c.y + c.height - s && ty <= c.y + c.height + s) return 'bottom-right';
    if (ty >= c.y - s && ty <= c.y + s && tx >= c.x + s && tx <= c.x + c.width - s) return 'top';
    if (ty >= c.y + c.height - s && ty <= c.y + c.height + s && tx >= c.x + s && tx <= c.x + c.width - s) return 'bottom';
    if (tx >= c.x - s && tx <= c.x + s && ty >= c.y + s && ty <= c.y + c.height - s) return 'left';
    if (tx >= c.x + c.width - s && tx <= c.x + c.width + s && ty >= c.y + s && ty <= c.y + c.height - s) return 'right';
    if (tx >= c.x && tx <= c.x + c.width && ty >= c.y && ty <= c.y + c.height) return 'move';
    return 'none';
  }

  private onTouchStart(e: TouchEvent) {
    const t = e.touches[0];
    if (!t) return;
    const mode = this.getHitMode(t.x, t.y);
    if (mode === 'none') return;
    this.dragMode = mode;
    this.startX = t.x;
    this.startY = t.y;
    this.startCrop = {
      x: this.cropRect.x,
      y: this.cropRect.y,
      width: this.cropRect.width,
      height: this.cropRect.height
    };
  }

  private onTouchMove(e: TouchEvent) {
    if (this.dragMode === 'none') return;
    const t = e.touches[0];
    if (!t) return;
    const dx = t.x - this.startX;
    const dy = t.y - this.startY;
    let nc: CropRect = {
      x: this.startCrop.x,
      y: this.startCrop.y,
      width: this.startCrop.width,
      height: this.startCrop.height
    };
    const minSize = 20;
    const renderLeft = this.renderX;
    const renderRight = this.renderX + this.renderWidth;
    const renderTop = this.renderY;
    const renderBottom = this.renderY + this.renderHeight;

    switch (this.dragMode) {
      case 'move':
        nc.x = Math.max(renderLeft, Math.min(this.startCrop.x + dx, renderRight - nc.width));
        nc.y = Math.max(renderTop, Math.min(this.startCrop.y + dy, renderBottom - nc.height));
        break;
      case 'top-left':
        nc.x = Math.max(renderLeft, Math.min(this.startCrop.x + dx, this.startCrop.x + this.startCrop.width - minSize));
        nc.y = Math.max(renderTop, Math.min(this.startCrop.y + dy, this.startCrop.y + this.startCrop.height - minSize));
        nc.width = this.startCrop.width - (nc.x - this.startCrop.x);
        nc.height = this.startCrop.height - (nc.y - this.startCrop.y);
        break;
      case 'top-right':
        nc.y = Math.max(renderTop, Math.min(this.startCrop.y + dy, this.startCrop.y + this.startCrop.height - minSize));
        nc.width = Math.max(minSize, Math.min(this.startCrop.width + dx, renderRight - this.startCrop.x));
        nc.height = this.startCrop.height - (nc.y - this.startCrop.y);
        break;
      case 'bottom-left':
        nc.x = Math.max(renderLeft, Math.min(this.startCrop.x + dx, this.startCrop.x + this.startCrop.width - minSize));
        nc.width = this.startCrop.width - (nc.x - this.startCrop.x);
        nc.height = Math.max(minSize, Math.min(this.startCrop.height + dy, renderBottom - this.startCrop.y));
        break;
      case 'bottom-right':
        nc.width = Math.max(minSize, Math.min(this.startCrop.width + dx, renderRight - this.startCrop.x));
        nc.height = Math.max(minSize, Math.min(this.startCrop.height + dy, renderBottom - this.startCrop.y));
        break;
      case 'top':
        nc.y = Math.max(renderTop, Math.min(this.startCrop.y + dy, this.startCrop.y + this.startCrop.height - minSize));
        nc.height = this.startCrop.height - (nc.y - this.startCrop.y);
        break;
      case 'bottom':
        nc.height = Math.max(minSize, Math.min(this.startCrop.height + dy, renderBottom - this.startCrop.y));
        break;
      case 'left':
        nc.x = Math.max(renderLeft, Math.min(this.startCrop.x + dx, this.startCrop.x + this.startCrop.width - minSize));
        nc.width = this.startCrop.width - (nc.x - this.startCrop.x);
        break;
      case 'right':
        nc.width = Math.max(minSize, Math.min(this.startCrop.width + dx, renderRight - this.startCrop.x));
        break;
    }
    nc.x = Math.max(renderLeft, Math.min(nc.x, renderRight - nc.width));
    nc.y = Math.max(renderTop, Math.min(nc.y, renderBottom - nc.height));
    nc.width = Math.max(minSize, Math.min(nc.width, renderRight - nc.x));
    nc.height = Math.max(minSize, Math.min(nc.height, renderBottom - nc.y));
    this.onCropChange(nc);
    this.draw();
  }

  private onTouchEnd() { this.dragMode = 'none'; }

  private onCropChanged() { this.draw(); }
  private onSizeChanged() { this.draw(); }

  aboutToAppear() { this.draw(); }

  build() {
    Stack() {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onAreaChange(() => this.draw())
        .hitTestBehavior(HitTestMode.None)

      Column()
        .width('100%')
        .height('100%')
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) this.onTouchStart(e);
          else if (e.type === TouchType.Move) this.onTouchMove(e);
          else if (e.type === TouchType.Up || e.type === TouchType.Cancel) this.onTouchEnd();
        })
    }
    .width('100%')
    .height('100%')
  }
}
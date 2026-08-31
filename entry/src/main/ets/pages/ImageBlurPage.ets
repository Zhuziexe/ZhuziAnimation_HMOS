// ImageBlurPage.ets
import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';

interface CropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

@Entry
@Component
struct ImageBlurPage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  @State imageUri: string = '';
  @State originalImagePath: string = '';
  @State displayImagePath: string = '';
  @State originalWidth: number = 0;
  @State originalHeight: number = 0;
  @State crop: CropRect = { x: 0, y: 0, width: 0, height: 0 };
  @State displayWidth: number = 0;
  @State displayHeight: number = 0;
  @State renderX: number = 0;
  @State renderY: number = 0;
  @State renderW: number = 0;
  @State renderH: number = 0;
  @State isLoading: boolean = true;
  @State isSaving: boolean = false;
  @State pixelInfo: string = '等待选择区域';
  private cropInitialized: boolean = false;
  private isPageAlive: boolean = true;

  @State imageVersion: number = 0;

  @State blurMode: number = 0;
  private blurModeOptions: SelectOption[] = [
    { value: '普通模糊' },
    { value: '高斯模糊' }
  ];
  @State blurStrength: number = 10;

  private previewTimer: number = -1;
  private isGeneratingPreview: boolean = false;

  private getImageSrc(): string {
    return `file://${this.displayImagePath}?v=${this.imageVersion}`;
  }

  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    if (params && params['imageUri']) {
      this.imageUri = params['imageUri'];
      this.prepareImage();
    } else {
      promptAction.showToast({ message: '未传入图片' });
      router.back();
    }
  }

  aboutToDisappear() {
    this.isPageAlive = false;
    if (this.previewTimer > 0) {
      clearTimeout(this.previewTimer);
      this.previewTimer = -1;
    }
    const cacheDir = this.context.cacheDir + '/tools/imageblur/';
    try { fileIo.unlinkSync(cacheDir + 'original.png'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'preview.png'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'output.png'); } catch {}
  }

  private async prepareImage() {
    try {
      this.isLoading = true;
      const cacheDir = this.context.cacheDir + '/tools/imageblur/';
      try { fileIo.mkdirSync(cacheDir, true); } catch {}
      const destPath = cacheDir + 'original.png';
      await this.copyMediaUriToPath(this.imageUri, destPath);
      this.originalImagePath = destPath;
      this.displayImagePath = destPath;

      const imageSource = image.createImageSource(destPath);
      const info = await imageSource.getImageInfo();
      this.originalWidth = info.size.width;
      this.originalHeight = info.size.height;

      this.isLoading = false;
    } catch (err) {
      console.error('准备图片失败:', err);
      promptAction.showToast({ message: '加载图片失败' });
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
    if (containerW === 0 || containerH === 0 || this.originalWidth === 0 || this.originalHeight === 0) return;
    const scale = Math.min(containerW / this.originalWidth, containerH / this.originalHeight);
    const rw = this.originalWidth * scale;
    const rh = this.originalHeight * scale;
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
    // 不在这里触发预览，等待操作结束
  }

  private updatePixelInfo(c: CropRect) {
    if (this.renderW === 0 || this.renderH === 0 || this.originalWidth === 0 || this.originalHeight === 0) {
      this.pixelInfo = '等待图片加载';
      return;
    }
    const relX = (c.x - this.renderX) / this.renderW;
    const relY = (c.y - this.renderY) / this.renderH;
    const relW = c.width / this.renderW;
    const relH = c.height / this.renderH;
    const pixelX = Math.round(relX * this.originalWidth);
    const pixelY = Math.round(relY * this.originalHeight);
    const pixelW = Math.round(relW * this.originalWidth);
    const pixelH = Math.round(relH * this.originalHeight);
    this.pixelInfo = `模糊区域: (${pixelX}, ${pixelY})  大小: ${pixelW}×${pixelH}`;
  }

  private onCropChange(newCrop: CropRect) {
    this.updateCrop(newCrop);
  }

  // 操作结束时触发预览
  private onCropEnd() {
    this.schedulePreview();
  }

  private onParamChange() {
    // 滑块值变化时不触发预览，仅当滑块释放时触发
  }

  private onParamChangeEnd() {
    this.schedulePreview();
  }

  private schedulePreview() {
    if (this.previewTimer > 0) {
      clearTimeout(this.previewTimer);
      this.previewTimer = -1;
    }
    this.previewTimer = setTimeout(() => {
      this.generatePreview();
    }, 300);
  }

  private async generatePreview() {
    if (this.isGeneratingPreview) return;
    if (this.crop.width < 10 || this.crop.height < 10) {
      this.displayImagePath = this.originalImagePath;
      return;
    }

    const rect = this.crop;
    const relX = (rect.x - this.renderX) / this.renderW;
    const relY = (rect.y - this.renderY) / this.renderH;
    const relW = rect.width / this.renderW;
    const relH = rect.height / this.renderH;
    let finalX = Math.round(relX * this.originalWidth);
    let finalY = Math.round(relY * this.originalHeight);
    let finalW = Math.round(relW * this.originalWidth);
    let finalH = Math.round(relH * this.originalHeight);
    finalX = Math.max(0, Math.min(finalX, this.originalWidth - finalW));
    finalY = Math.max(0, Math.min(finalY, this.originalHeight - finalH));
    finalW = Math.min(finalW, this.originalWidth - finalX);
    finalH = Math.min(finalH, this.originalHeight - finalY);
    if (finalW < 10 || finalH < 10) return;

    const cacheDir = this.context.cacheDir + '/tools/imageblur/';
    const previewPath = cacheDir + 'preview.png';

    const strength = Math.round(this.blurStrength);
    let blurFilter: string;
    if (this.blurMode === 0) {
      blurFilter = `boxblur=${strength}:1`;
    } else {
      blurFilter = `gblur=sigma=${strength}`;
    }
    const cmd = `-i "${this.originalImagePath}" -filter_complex "[0:v]crop=${finalW}:${finalH}:${finalX}:${finalY},${blurFilter}[blurred];[0:v][blurred]overlay=${finalX}:${finalY}" -y "${previewPath}"`;
    console.info('预览命令:', cmd);

    try {
      this.isGeneratingPreview = true;
      const result: CommandSyncResult = executeCommandSync(cmd);
      if (result.evenType === 'onSuccess') {
        this.displayImagePath = previewPath;
        if(this.imageVersion == 0){
          this.imageVersion++;
        }else{
          this.imageVersion = 0;
        }
      } else {
        console.error('预览生成失败:', result);
        this.displayImagePath = this.originalImagePath;
      }
    } catch (err) {
      console.error('预览生成异常:', err);
      this.displayImagePath = this.originalImagePath;
    } finally {
      this.isGeneratingPreview = false;
    }
  }

  private async saveBlurred() {
    if (this.isSaving) return;
    if (this.crop.width < 10 || this.crop.height < 10) {
      promptAction.showToast({ message: '区域太小' });
      return;
    }

    const rect = this.crop;
    const relX = (rect.x - this.renderX) / this.renderW;
    const relY = (rect.y - this.renderY) / this.renderH;
    const relW = rect.width / this.renderW;
    const relH = rect.height / this.renderH;
    let finalX = Math.round(relX * this.originalWidth);
    let finalY = Math.round(relY * this.originalHeight);
    let finalW = Math.round(relW * this.originalWidth);
    let finalH = Math.round(relH * this.originalHeight);
    finalX = Math.max(0, Math.min(finalX, this.originalWidth - finalW));
    finalY = Math.max(0, Math.min(finalY, this.originalHeight - finalH));
    finalW = Math.min(finalW, this.originalWidth - finalX);
    finalH = Math.min(finalH, this.originalHeight - finalY);
    if (finalW < 10 || finalH < 10) {
      promptAction.showToast({ message: '区域太小' });
      return;
    }

    const cacheDir = this.context.cacheDir + '/tools/imageblur/';
    const outputPath = cacheDir + 'output.png';
    try { fileIo.unlinkSync(outputPath); } catch {}

    const strength = Math.round(this.blurStrength);
    let blurFilter: string;
    if (this.blurMode === 0) {
      blurFilter = `boxblur=${strength}:1`;
    } else {
      blurFilter = `gblur=sigma=${strength}`;
    }
    const filterComplex = `[0:v]crop=${finalW}:${finalH}:${finalX}:${finalY},${blurFilter}[blurred];[0:v][blurred]overlay=${finalX}:${finalY}`;
    const args = ['-i', this.originalImagePath, '-filter_complex', filterComplex, '-y', outputPath];
    console.info('保存命令:', args.join(' '));

    try {
      this.isSaving = true;
      const result: CommandSyncResult = executeCommandSync(args.join(' '));
      if (result.evenType !== 'onSuccess') {
        throw new Error('处理失败');
      }
      await this.saveToGallery(outputPath);
    } catch (err) {
      console.error('保存失败:', err);
      promptAction.showToast({ message: `保存失败: ${(err as Error).message}` });
    } finally {
      this.isSaving = false;
    }
  }

  private async saveToGallery(filePath: string) {
    try {
      const phHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
      const configs: photoAccessHelper.PhotoCreationConfig[] = [
        {
          title: `模糊_${Date.now()}`,
          fileNameExtension: 'png',
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
        }
      ];
      const destUris = await phHelper.showAssetsCreationDialog([filePath], configs);
      if (!destUris || destUris.length === 0) throw new Error('用户取消保存');
      const destUri = destUris[0];
      const srcFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(destUri, fileIo.OpenMode.WRITE_ONLY);
      fileIo.copyFileSync(srcFile.fd, destFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(destFile);
      promptAction.showToast({ message: '模糊图片已保存' });
      router.back();
    } catch (err) {
      console.error('保存到图库失败:', err);
      const errorMsg = (err as BusinessError).message || '未知错误';
      promptAction.showToast({ message: `保存失败: ${errorMsg}` });
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
        router.back();
      })
      .height(40).width(40).buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('图片区域模糊')
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
          Text('加载图片中...').fontSize(16).fontColor($r('sys.color.font_secondary')).margin({ top: 12 })
        }
        .layoutWeight(1).justifyContent(FlexAlign.Center).width('100%')
      } else {
        Column({ space: 12 }) {
          Stack() {
            Image(this.displayImagePath ? this.getImageSrc() : '')
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
                      // 初始生成预览
                      this.schedulePreview();
                    }
                  }
                }
              })

            CropOverlay({
              cropRect: this.crop,
              imageWidth: this.displayWidth,
              imageHeight: this.displayHeight,
              renderX: this.renderX,
              renderY: this.renderY,
              renderWidth: this.renderW,
              renderHeight: this.renderH,
              onCropChange: (newCrop: CropRect) => { this.onCropChange(newCrop); },
              onCropEnd: () => { this.onCropEnd(); }
            })
              .width('100%')
              .height('100%')
              .position({ x: 0, y: 0 })
          }
          .width('100%')
          .layoutWeight(1)

          Row() {
            Text('模糊方式').width(70).fontSize(16).fontColor($r('sys.color.font_primary'))
            Select(this.blurModeOptions)
              .value(this.blurModeOptions[this.blurMode].value)
              .selected(this.blurMode)
              .onSelect((index: number) => {
                this.blurMode = index;
                // 选择后立即触发预览
                this.schedulePreview();
              })
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Row() {
            Text('模糊程度').width(70).fontSize(16).fontColor($r('sys.color.font_primary'))
            Slider({
              min: 1,
              max: 20,
              step: 1,
              value: this.blurStrength
            })
              .onChange((value: number) => {
                this.blurStrength = value;
                // 拖动过程中不触发预览
              })
              .onChange((value: number, mode: SliderChangeMode) => {
                this.blurStrength = value;
                // 只有拖动结束时才触发预览
                if (mode === SliderChangeMode.End) {
                  this.schedulePreview();
                }
              })
              .layoutWeight(1)
            Text(`${this.blurStrength}`).fontSize(16).width(40).textAlign(TextAlign.End)
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

          Button(this.isSaving ? '保存中...' : '保存模糊图片')
            .width('90%')
            .height(48)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('sys.color.background_emphasize'))
            .fontColor(Color.White)
            .borderRadius(24)
            .onClick(() => this.saveBlurred())
            .enabled(!this.isSaving && this.crop.width > 10 && this.crop.height > 10)
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

@Component
struct CropOverlay {
  @Prop @Watch('onCropChanged') cropRect: CropRect = { x: 0, y: 0, width: 0, height: 0 };
  @Prop @Watch('onSizeChanged') imageWidth: number = 0;
  @Prop @Watch('onSizeChanged') imageHeight: number = 0;
  @Prop @Watch('onSizeChanged') renderX: number = 0;
  @Prop @Watch('onSizeChanged') renderY: number = 0;
  @Prop @Watch('onSizeChanged') renderWidth: number = 0;
  @Prop @Watch('onSizeChanged') renderHeight: number = 0;
  onCropChange: (newRect: CropRect) => void = () => {};
  onCropEnd?: () => void;   // 新增：触摸结束回调

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

  private onTouchEnd() {
    this.dragMode = 'none';
    // 触摸结束时触发预览
    this.onCropEnd?.();
  }

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
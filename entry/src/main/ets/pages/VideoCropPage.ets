import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';
import { getVideoInfo } from '../common/VideoUtils';
import taskpool from '@ohos.taskpool';

// ====== 类型定义 ======
interface CropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface Preset {
  label: string;
  ratio: number;
}

// ====== 并发裁剪任务 ======
@Concurrent
async function cropVideoTask(
  videoUri: string,
  context: common.UIAbilityContext,
  rawWidth: number,
  rawHeight: number,
  renderX: number,
  renderY: number,
  renderW: number,
  renderH: number,
  cropX: number,
  cropY: number,
  cropW: number,
  cropH: number
): Promise<string> {
  const relX = (cropX - renderX) / renderW;
  const relY = (cropY - renderY) / renderH;
  const relW = cropW / renderW;
  const relH = cropH / renderH;
  const pixelX = Math.round(relX * rawWidth);
  const pixelY = Math.round(relY * rawHeight);
  const pixelW = Math.round(relW * rawWidth);
  const pixelH = Math.round(relH * rawHeight);
  const finalX = Math.max(0, Math.min(pixelX, rawWidth - pixelW));
  const finalY = Math.max(0, Math.min(pixelY, rawHeight - pixelH));
  const finalW = Math.min(pixelW, rawWidth - finalX);
  const finalH = Math.min(pixelH, rawHeight - finalY);

  // 复制视频到沙箱
  const cacheDir = context.cacheDir + '/tools/cropvideo/';
  try { fileIo.mkdirSync(cacheDir, true); } catch {}
  const tempInput = cacheDir + 'tmp_video.mp4';
  // 删除旧文件（避免残留影响）
  try { fileIo.unlinkSync(tempInput); } catch {}
  const srcFd = fileIo.openSync(videoUri, fileIo.OpenMode.READ_ONLY);
  if (srcFd.fd < 0) throw new Error('打开视频失败');
  const destFd = fileIo.openSync(tempInput, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try {
    const buf = new ArrayBuffer(1024 * 1024);
    let len: number;
    while ((len = fileIo.readSync(srcFd.fd, buf)) > 0) {
      fileIo.writeSync(destFd.fd, buf, { length: len });
    }
  } finally {
    fileIo.closeSync(srcFd);
    fileIo.closeSync(destFd);
  }

  const outputPath = cacheDir + 'cropped_video.mp4';
  const filter = `crop=${finalW}:${finalH}:${finalX}:${finalY}`;
  const cmd = `-i "${tempInput}" -vf ${filter} -c:a copy -y "${outputPath}"`;
  const result: CommandSyncResult = executeCommandSync(cmd);
  if (result.evenType !== 'onSuccess') {
    throw new Error(`裁剪失败: ${result.failStackTrace || '未知错误'}`);
  }
  // 清理输入
  try { fileIo.unlinkSync(tempInput); } catch {}
  return outputPath;
}

// ====== 裁剪进度对话框 ======
@CustomDialog
struct CropProgressDialog {
  controller: CustomDialogController;
  onCancel: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      LoadingProgress().width(48).height(48)
      Text('裁剪中...').fontSize(18).fontColor($r('sys.color.font_primary'))
      Text('裁剪视频可能需要一些时间。').fontSize(14).fontColor($r('sys.color.font_secondary'))
    }
    .padding(24)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_tertiary'))
  }
}

// ====== 主页面 ======
@Entry
@Component
struct VideoCropPage {
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
  @State selectedPreset: number = -1;
  @State isLoading: boolean = true;
  @State isExporting: boolean = false;
  @State pixelInfo: string = '等待裁剪';
  private cropInitialized: boolean = false;
  private progressDialogController: CustomDialogController | null = null;

  private presets: Preset[] = [
    { label: '1:1', ratio: 1 },
    { label: '16:9', ratio: 16 / 9 },
    { label: '9:16', ratio: 9 / 16 },
    { label: '4:3', ratio: 4 / 3 },
    { label: '3:4', ratio: 3 / 4 },
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
    // 删除第一帧图片
    try { if (this.framePath) fileIo.unlinkSync(this.framePath); } catch {}
    // 清理该工具下的其他临时文件
    const cacheDir = this.context.cacheDir + '/tools/cropvideo/';
    try { fileIo.unlinkSync(cacheDir + 'tmp_video.mp4'); } catch {}
    try { fileIo.unlinkSync(cacheDir + 'cropped_video.mp4'); } catch {}
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

      const cacheDir = this.context.cacheDir + '/tools/cropvideo/';
      // 确保目录存在
      try {
        if (!fileIo.accessSync(cacheDir)) {
          fileIo.mkdirSync(cacheDir, true);
        }
      } catch (e) {
        fileIo.mkdirSync(cacheDir, true);
      }
      const inputPath = cacheDir + 'tmp_video.mp4';
      const framePath = cacheDir + 'crop_frame.png';

      // 复制视频到缓存（内部会先删除目标文件）
      await this.copyMediaUriToPath(this.videoUri, inputPath);
      // 提取第一帧，-y 强制覆盖输出文件
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

  // 🛠️ 关键修复：先删除目标文件，再写入
  private async copyMediaUriToPath(mediaUri: string, destPath: string): Promise<void> {
    // 先尝试删除目标文件（如果存在），避免 File exists 错误
    try {
      fileIo.unlinkSync(destPath);
    } catch (e) {
      // 文件不存在或无法删除，忽略
    }
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
    this.selectedPreset = -1;
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
    this.pixelInfo = `起始: (${pixelX}, ${pixelY})  大小: ${pixelW}×${pixelH}`;
  }

  private onCropChange(newCrop: CropRect) {
    this.updateCrop(newCrop);
  }

  private applyPreset(ratio: number, index: number) {
    if (this.renderW === 0 || this.renderH === 0) {
      promptAction.showToast({ message: '视频尚未加载完成' });
      return;
    }
    this.selectedPreset = index;
    const maxW = this.renderW;
    const maxH = this.renderH;
    let newW: number, newH: number;
    const imgRatio = this.renderW / this.renderH;
    if (ratio >= imgRatio) {
      newW = maxW;
      newH = newW / ratio;
      if (newH > maxH) { newH = maxH; newW = newH * ratio; }
    } else {
      newH = maxH;
      newW = newH * ratio;
      if (newW > maxW) { newW = maxW; newH = newW / ratio; }
    }
    const centerX = this.renderX + this.renderW / 2;
    const centerY = this.renderY + this.renderH / 2;
    let newX = centerX - newW / 2;
    let newY = centerY - newH / 2;
    newX = Math.max(this.renderX, Math.min(newX, this.renderX + this.renderW - newW));
    newY = Math.max(this.renderY, Math.min(newY, this.renderY + this.renderH - newH));
    const rect: CropRect = { x: newX, y: newY, width: newW, height: newH };
    this.crop = rect;
    this.updatePixelInfo(rect);
  }

  private async doCrop() {
    if (this.isExporting) return;
    if (this.crop.width < 10 || this.crop.height < 10) {
      promptAction.showToast({ message: '裁剪区域太小' });
      return;
    }

    this.progressDialogController = new CustomDialogController({
      builder: CropProgressDialog({
        onCancel: () => {
          promptAction.showToast({ message: '正在后台处理，请稍候...' });
        }
      }),
      autoCancel: false,
      customStyle: true,
    });
    this.progressDialogController.open();

    this.isExporting = true;
    try {
      const outputPath = await taskpool.execute(
        cropVideoTask,
        this.videoUri,
        this.context,
        this.rawWidth,
        this.rawHeight,
        this.renderX,
        this.renderY,
        this.renderW,
        this.renderH,
        this.crop.x,
        this.crop.y,
        this.crop.width,
        this.crop.height
      ) as string;

      try {
        await this.saveToGallery(outputPath);
        promptAction.showToast({ message: '裁剪视频已保存到相册' });
      } catch {}
      try { fileIo.unlinkSync(outputPath); } catch {}
    } catch (err) {
      console.error('裁剪失败:', err);
      promptAction.showToast({ message: `裁剪失败: ${err.message || '未知错误'}` });
    } finally {
      this.isExporting = false;
      if (this.progressDialogController) {
        this.progressDialogController.close();
        this.progressDialogController = null;
      }
    }
  }

  private async saveToGallery(filePath: string): Promise<void> {
    const phHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
    const configs: photoAccessHelper.PhotoCreationConfig[] = [
      {
        title: `裁剪_${Date.now()}`,
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
  }

  @Builder
  buildTopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(24).width(24).height(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .onClick(() => router.back())
      .height(40).width(40).buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('视频画面裁剪')
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

            CropOverlay({
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

          Row({ space: 8 }) {
            ForEach(this.presets, (item: Preset, index: number) => {
              Button(item.label)
                .fontSize(14)
                .padding({ left: 10, right: 10 })
                .height(32)
                .borderRadius(16)
                .backgroundColor(this.selectedPreset === index ?
                  $r('sys.color.background_emphasize') :
                  $r('sys.color.background_secondary'))
                .fontColor(this.selectedPreset === index ?
                  Color.White :
                  $r('sys.color.font_primary'))
                .onClick(() => this.applyPreset(item.ratio, index))
                .enabled(this.renderW > 0 && this.renderH > 0)
            }, (item: Preset) => item.label)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Row() {
            Text(this.pixelInfo)
              .fontSize(14)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .height(30)

          Button('裁剪')
            .width('90%')
            .height(48)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('sys.color.background_emphasize'))
            .fontColor(Color.White)
            .borderRadius(24)
            .onClick(() => this.doCrop())
            .enabled(!this.isExporting && this.crop.width > 10 && this.crop.height > 10)
            .margin({ bottom: 20 })
        }
        .layoutWeight(1)
        .padding({ top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_tertiary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}

// ====== CropOverlay（裁剪框覆盖层）======
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
    ctx.fillStyle = 'rgba(0,0,0,0.6)';
    ctx.fillRect(0, 0, w, c.y);
    ctx.fillRect(0, c.y + c.height, w, h - c.y - c.height);
    ctx.fillRect(0, c.y, c.x, c.height);
    ctx.fillRect(c.x + c.width, c.y, w - c.x - c.width, c.height);
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
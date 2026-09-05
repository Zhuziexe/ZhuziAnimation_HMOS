import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommand, stopCommand, executeCommandSync, CommandSyncResult } from '@tyousan/ffmpeg';
import { getVideoInfo } from '../common/VideoUtils';
import { ProcessingDialog } from '../components/ProcessingDialog';
import { RenderRect } from '../common/CommonInterfaces';
import { CropOverlay } from '../components/CropOverlay';

interface Preset {
  label: string;
  ratio: number;
}

@Builder
export function VideoCropPageBuilder() {
  VideoCropPage();
}

@Component
export struct VideoCropPage {
  private pathStack: NavPathStack | null = null;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  @State videoUri: string = '';
  @State rawWidth: number = 0;
  @State rawHeight: number = 0;
  @State framePath: string = '';
  @State crop: RenderRect = { x: 0, y: 0, width: 0, height: 0 };
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
  private currentSessionId: number = -1;
  private cancelFlag: boolean = false;
  private isPageAlive: boolean = true;

  private presets: Preset[] = [
    { label: '1:1', ratio: 1 },
    { label: '16:9', ratio: 16 / 9 },
    { label: '9:16', ratio: 9 / 16 },
    { label: '4:3', ratio: 4 / 3 },
    { label: '3:4', ratio: 3 / 4 },
  ];

  aboutToAppear() {

  }

  aboutToDisappear() {
    this.isPageAlive = false;
    if (this.progressDialogController) {
      try { this.progressDialogController.close(); } catch {}
      this.progressDialogController = null;
    }
    const cacheDir = this.context.cacheDir + '/tools/cropvideo/';
    try { fileIo.unlinkSync(cacheDir + 'crop_frame.png'); } catch {}
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
      try { fileIo.mkdirSync(cacheDir, true); } catch {}
      const inputPath = cacheDir + 'tmp_video.mp4';
      const framePath = cacheDir + 'crop_frame.png';

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

  private updateCrop(newCrop: RenderRect) {
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
    const rect: RenderRect = { x, y, width: w, height: h };
    this.crop = rect;
    this.selectedPreset = -1;
    this.updatePixelInfo(rect);
  }

  private updatePixelInfo(c: RenderRect) {
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

  private onCropChange(newCrop: RenderRect) {
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
    const rect: RenderRect = { x: newX, y: newY, width: newW, height: newH };
    this.crop = rect;
    this.updatePixelInfo(rect);
  }

  private cancelProcess():void{
    if (this.currentSessionId > 0) {
      stopCommand({ sessionId: this.currentSessionId });
    }
    this.cancelFlag = true;
  }

  private doCropAsync() {
    if (this.isExporting) return;
    if (this.crop.width < 10 || this.crop.height < 10) {
      promptAction.showToast({ message: '裁剪区域太小' });
      return;
    }

    this.cancelFlag = false;
    this.isExporting = true;

    this.progressDialogController = new CustomDialogController({
      builder: ProcessingDialog({
        processingText:'裁剪视频中...',
        secondaryText:'裁剪视频可能需要一些时间。',
        onCancel: () => this.cancelProcess()
      }),
      autoCancel: false,
      customStyle: true,
      cancel: ()=>this.cancelProcess()
    });
    this.progressDialogController.open();

    const cacheDir = this.context.cacheDir + '/tools/cropvideo/';
    const inputPath = cacheDir + 'tmp_video.mp4';
    const outputPath = cacheDir + 'cropped_video.mp4';

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
      promptAction.showToast({ message: '裁剪区域映射到视频后太小' });
      this.isExporting = false;
      this.closeProgressDialog();
      return;
    }

    try { fileIo.unlinkSync(outputPath); } catch {}

    const filter = `crop=${finalW}:${finalH}:${finalX}:${finalY}`;
    const args = ['-i', inputPath, '-vf', filter, '-c:a', 'copy', '-y', outputPath];

    console.info('FFmpeg 裁剪参数:', args.join(' '));

    executeCommand({
      cmd: args.join(' '),
      start: (result) => {
        this.currentSessionId = result.sessionId;
        console.info('裁剪任务启动, sessionId:', this.currentSessionId);
      },
      success: (result) => {
        console.info('裁剪任务成功:', result);
        if (!this.cancelFlag && this.isPageAlive) {
          this.saveToGallery(outputPath);
        } else {
          try { fileIo.unlinkSync(outputPath); } catch {}
        }
        this.closeProgressDialog();
      },
      fail: (error) => {
        console.error('裁剪任务失败:', error);
        if (this.isPageAlive && !this.cancelFlag) {
          promptAction.showToast({ message: `裁剪失败: ${error.message || '未知错误'}` });
        }
        try { fileIo.unlinkSync(outputPath); } catch {}
        this.closeProgressDialog();
      },
      cancel: (result) => {
        console.info('裁剪任务已取消:', result);
        try { fileIo.unlinkSync(outputPath); } catch {}
        if (this.isPageAlive) {
          promptAction.showToast({ message: '已取消裁剪' });
        }
        this.closeProgressDialog();
      },
      complete: (result) => {
        console.info('裁剪任务结束:', result);
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

  private async doCrop() {
    this.doCropAsync();
  }

  private async saveToGallery(filePath: string): Promise<void> {
    try {
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
      if (this.isPageAlive) {
        promptAction.showToast({ message: '裁剪视频已保存到相册' });
        this.pathStack?.pop();
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
          promptAction.showToast({ message: '正在裁剪，请使用"取消"按钮停止' });
        } else {
          this.pathStack?.pop();
        }
      })
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
    NavDestination() {
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
                      const rect: RenderRect = {
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
                onCropChange: (newCrop: RenderRect) => {
                  this.onCropChange(newCrop);
                }
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
                .fontColor($r('sys.color.font_primary'))
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
            .height(30)

            Button('裁剪')
              .width('90%')
              .height(48)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .backgroundColor($r('app.color.brand'))
              .fontColor(Color.White)
              .borderRadius(24)
              .onClick(() => this.doCrop())
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
    .hideTitleBar(true)
    .hideBackButton(true)
    .onReady((context:NavDestinationContext)=>{
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

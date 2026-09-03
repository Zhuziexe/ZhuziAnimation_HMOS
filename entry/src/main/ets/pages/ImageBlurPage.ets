import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { executeCommand, stopCommand } from '@tyousan/ffmpeg';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ProcessingDialog } from '../components/ProcessingDialog';
import { FfmpegError, FfmpegResult } from '../common/CommonInterfaces';
import { BlurOverlay } from '../components/BlurOverlay'
import { RenderRect } from '../common/CommonInterfaces'

@CustomDialog
struct BlurResultDialog {
  controller?: CustomDialogController;
  imagePath: string = '';
  onSave: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    Column({ space: 6 }) {
      Text('模糊结果').fontSize(18).fontWeight(FontWeight.Medium)
      Image(`file://${this.imagePath}`)
        .width('100%')
        .constraintSize({
          minHeight: 40,
          maxHeight: '50%'
        })
        .borderRadius(12)
        .objectFit(ImageFit.Contain)
      Button('保存到相册')
        .backgroundColor($r('app.color.brand'))
        .fontColor(Color.White)
        .onClick(() => {
          this.onSave();
          this.controller?.close();
        })
        .width('100%')
      Button('关闭')
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .fontColor($r('app.color.brand'))
        .onClick(() => {
          this.onClose();
          this.controller?.close();
        })
        .width('100%')
    }
    .padding(12)
  }
}

@Entry
@Component
struct ImageBlurPage {
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private isPageAlive: boolean = true;

  @State imageUri: string = '';
  @State originalImagePath: string = '';
  @State originalWidth: number = 0;
  @State originalHeight: number = 0;
  @State crop: RenderRect = { x: 0, y: 0, width: 0, height: 0 };
  @State displayWidth: number = 0;
  @State displayHeight: number = 0;
  @State renderX: number = 0;
  @State renderY: number = 0;
  @State renderW: number = 0;
  @State renderH: number = 0;
  @State isLoading: boolean = true;
  @State isProcessing: boolean = false;
  @State pixelInfo: string = '等待选择区域';
  private cropInitialized: boolean = false;

  @State blurMode: number = 0;
  private blurModeOptions: SelectOption[] = [
    { value: '普通模糊' },
    { value: '高斯模糊' }
  ];
  @State blurStrength: number = 10;

  // 异步任务控制
  private currentSessionId: number = -1;
  private loadingDialogController: CustomDialogController | null = null;
  private resultDialogController: CustomDialogController | null = null;

  // 缓存文件路径
  private cacheDir: string = '';

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
    // 取消正在进行的任务
    if (this.currentSessionId > 0) {
      stopCommand({ sessionId: this.currentSessionId });
    }
    // 关闭弹窗
    this.closeLoadingDialog();
    this.closeResultDialog();
    // 清理缓存文件
    const dir = this.context.cacheDir + '/tools/imageblur/';
    try { fileIo.unlinkSync(dir + 'original.png'); } catch {}
    try { fileIo.unlinkSync(dir + 'output.png'); } catch {}
  }

  private async prepareImage() {
    try {
      this.isLoading = true;
      this.cacheDir = this.context.cacheDir + '/tools/imageblur/';
      try { fileIo.mkdirSync(this.cacheDir, true); } catch {}
      const destPath = this.cacheDir + 'original.png';
      await this.copyMediaUriToPath(this.imageUri, destPath);
      this.originalImagePath = destPath;

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
    this.updatePixelInfo(rect);
  }

  private updatePixelInfo(c: RenderRect) {
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

  private onCropChange(newCrop: RenderRect) {
    this.updateCrop(newCrop);
  }

  // ---------- 执行模糊处理（异步，可取消） ----------
  private async startBlur() {
    if (this.isProcessing) return;
    if (this.crop.width < 10 || this.crop.height < 10) {
      promptAction.showToast({ message: '区域太小' });
      return;
    }

    // 计算裁剪像素坐标
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

    const outputPath = this.cacheDir + 'output.png';
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
    console.info('模糊命令:', args.join(' '));

    // 显示加载弹窗
    this.showLoadingDialog();

    this.isProcessing = true;
    try {
      executeCommand({
        cmd: args.join(' '),
        start: (result: FfmpegResult) => {
          this.currentSessionId = result.sessionId ?? -1;
          console.info('模糊任务启动, sessionId:', this.currentSessionId);
        },
        success: (result: FfmpegResult) => {
          console.info('模糊任务成功');
          if (!this.isPageAlive) return;
          this.closeLoadingDialog();
          this.showResultDialog(outputPath);
          this.isProcessing = false;
          this.currentSessionId = -1;
        },
        fail: (error: FfmpegError) => {
          console.error('模糊任务失败:', JSON.stringify(error));
          if (error.stderr) {
            console.error('stderr:', error.stderr);
          }
          if (this.isPageAlive) {
            this.closeLoadingDialog();
            promptAction.showToast({ message: `模糊失败: ${error.message || '未知错误'}` });
          }
          this.isProcessing = false;
          this.currentSessionId = -1;
          try { fileIo.unlinkSync(outputPath); } catch {}
        },
        cancel: (result: FfmpegResult) => {
          console.info('模糊任务已取消');
          if (this.isPageAlive) {
            this.closeLoadingDialog();
            promptAction.showToast({ message: '已取消模糊处理' });
          }
          this.isProcessing = false;
          this.currentSessionId = -1;
          try { fileIo.unlinkSync(outputPath); } catch {}
        },
        complete: (result: FfmpegResult) => {
          console.info('模糊任务结束');
          this.currentSessionId = -1;
        }
      });
    } catch (err) {
      console.error('启动模糊任务异常:', err);
      this.closeLoadingDialog();
      promptAction.showToast({ message: '启动失败' });
      this.isProcessing = false;
    }
  }

  // ---------- 取消任务 ----------
  private cancelBlur():void {
    if (this.currentSessionId > 0) {
      stopCommand({ sessionId: this.currentSessionId });
    }
  }

  // ---------- 弹窗管理 ----------
  private showLoadingDialog() {
    if (this.loadingDialogController) {
      this.loadingDialogController.close();
      this.loadingDialogController = null;
    }
    this.loadingDialogController = new CustomDialogController({
      builder: ProcessingDialog({
        processingText: '模糊处理中...',
        secondaryText:'图片区域模糊可能需要一些时间。',
        onCancel: () => this.cancelBlur()
      }),
      autoCancel: false,
      customStyle: true,
      cancel: () => this.cancelBlur()
    });
    this.loadingDialogController.open();
  }

  private closeLoadingDialog() {
    if (this.loadingDialogController) {
      try { this.loadingDialogController.close(); } catch {}
      this.loadingDialogController = null;
    }
  }

  private showResultDialog(imagePath: string) {
    if (this.resultDialogController) {
      this.resultDialogController.close();
      this.resultDialogController = null;
    }
    this.resultDialogController = new CustomDialogController({
      builder: BlurResultDialog({
        imagePath: imagePath,
        onSave: () => {
          this.saveToGallery(imagePath);
        },
        onClose: () => {
        }
      }),
      alignment: DialogAlignment.Center
    });
    this.resultDialogController.open();
  }

  private closeResultDialog() {
    if (this.resultDialogController) {
      try { this.resultDialogController.close(); } catch {}
      this.resultDialogController = null;
    }
  }

  // ---------- 保存到相册 ----------
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
      if (!destUris || destUris.length === 0) {
        promptAction.showToast({ message: '保存已取消' });
        return;
      }
      const srcFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(destUris[0], fileIo.OpenMode.WRITE_ONLY);
      fileIo.copyFileSync(srcFile.fd, destFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(destFile);
      promptAction.showToast({ message: '模糊图片已保存到相册' });
      // 保存成功后返回上一页（可选）
      // router.back();
    } catch (err) {
      console.error('保存到图库失败:', err);
      const errorMsg = (err as BusinessError).message || '未知错误';
      promptAction.showToast({ message: `保存失败: ${errorMsg}` });
    } finally {
      // 不删除文件，因为弹窗可能还需要显示，下次处理会覆盖
    }
  }

  // ---------- 构建顶部栏 ----------
  @Builder
  buildTopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(24).width(24).height(24)
          .fontColor([$r('sys.color.font_primary')])
      }
      .onClick(() => {
        if (this.isProcessing) {
          promptAction.showToast({ message: '正在处理，请使用"取消"按钮停止' });
        } else {
          router.back();
        }
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

  // ---------- 主界面 ----------
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
            // 始终显示原始图片
            Image(`file://${this.originalImagePath}`)
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

            BlurOverlay({
              cropRect: this.crop,
              imageWidth: this.displayWidth,
              imageHeight: this.displayHeight,
              renderX: this.renderX,
              renderY: this.renderY,
              renderWidth: this.renderW,
              renderHeight: this.renderH,
              onCropChange: (newCrop: RenderRect) => { this.onCropChange(newCrop); }
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
              })
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })

          Row() {
            Text('模糊程度').width(70).fontSize(16).fontColor($r('sys.color.font_primary'))
            Slider({
              min: 1,
              max: 40,
              step: 1,
              value: this.blurStrength
            })
              .onChange((value: number, mode: SliderChangeMode) => {
                this.blurStrength = value;
              })
              .layoutWeight(1)
              .selectedColor($r('app.color.brand'))
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

          // “模糊”按钮
          Button(this.isProcessing ? '处理中...' : '模糊')
            .width('90%')
            .height(48)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.brand'))
            .fontColor(Color.White)
            .borderRadius(24)
            .onClick(() => this.startBlur())
            .enabled(!this.isProcessing && this.crop.width > 10 && this.crop.height > 10)
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
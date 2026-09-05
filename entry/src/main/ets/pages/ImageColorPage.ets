import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { ProcessingDialog } from '../components/ProcessingDialog';
import { createHueRotationMatrix } from '../common/ImageFilterUtils';

@Builder
export function ImageColorPageBuilder() {
  ImageColorPage();
}

@Component
export struct ImageColorPage {
  private pathStack: NavPathStack | null = null;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  @State imageUri: string = '';
  @State originalPixelMap: image.PixelMap | null = null;
  @State displayPixelMap: image.PixelMap | null = null;
  @State currentAngle: number = 0;
  @State isProcessing: boolean = false;
  @State isLoading: boolean = true;

  private progressDialogController: CustomDialogController | null = null;
  private isPageAlive: boolean = true;

  aboutToAppear() {
  }

  aboutToDisappear() {
    this.isPageAlive = false;
    if (this.progressDialogController) {
      try { this.progressDialogController.close(); } catch {}
      this.progressDialogController = null;
    }
    if (this.originalPixelMap) {
      try { this.originalPixelMap.release(); } catch {}
      this.originalPixelMap = null;
    }
    if (this.displayPixelMap) {
      try { this.displayPixelMap.release(); } catch {}
      this.displayPixelMap = null;
    }
  }

  private async loadImage() {
    try {
      this.isLoading = true;
      const pixelMap = await this.getPixelMapFromUri(this.imageUri);
      if (!pixelMap) {
        throw new Error('加载图片失败');
      }
      this.originalPixelMap = pixelMap;
      this.displayPixelMap = await this.applyHueShift(pixelMap, 0);
      this.isLoading = false;
    } catch (err) {
      console.error('加载图片失败:', err);
      promptAction.showToast({ message: '加载图片失败' });
      this.pathStack?.pop();
    }
  }

  private async getPixelMapFromUri(uri: string): Promise<image.PixelMap | null> {
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const imgSource = image.createImageSource(file.fd);
      const pixelMap = await imgSource.createPixelMap();
      imgSource.release();
      return pixelMap;
    } catch (err) {
      console.error('创建PixelMap失败:', err);
      return null;
    } finally {
      if (file) {
        try { fileIo.closeSync(file); } catch {}
      }
    }
  }

  private async applyHueShift(source: image.PixelMap, angle: number): Promise<image.PixelMap> {
    try {
      const cloned = await source.clone();
      const filter = effectKit.createEffect(cloned);
      if (!filter) {
        throw new Error('创建Filter失败');
      }
      const matrix = createHueRotationMatrix(angle);
      filter.setColorMatrix(matrix);
      const result = await filter.getEffectPixelMap();
      return result;
    } catch (err) {
      console.error('应用色相偏移失败:', err);
      throw new Error(err instanceof Error ? err.message : String(err));
    }
  }

  private onSliderChanging(value: number) {
    this.currentAngle = value;
  }

  private async onSliderChangeEnd(value: number) {
    if (!this.originalPixelMap || this.isProcessing) return;
    this.isProcessing = true;
    try {
      if (this.displayPixelMap) {
        try { this.displayPixelMap.release(); } catch {}
        this.displayPixelMap = null;
      }
      const newDisplay = await this.applyHueShift(this.originalPixelMap, value);
      if (newDisplay) {
        this.displayPixelMap = newDisplay;
      }
    } catch (err) {
      console.error('刷新预览失败:', err);
    } finally {
      this.isProcessing = false;
    }
  }

  private async startExport() {
    if (this.isProcessing || !this.originalPixelMap) return;
    this.isProcessing = true;
    this.progressDialogController = new CustomDialogController({
      builder: ProcessingDialog({
        processingText: '正在处理图片...',
        secondaryText: '处理图片可能需要一些时间',
        onCancel: () => {}
      }),
      autoCancel: false,
      customStyle: true,
    });
    this.progressDialogController.open();

    try {
      const resultPixelMap = await this.applyHueShift(this.originalPixelMap, this.currentAngle);
      if (!resultPixelMap) {
        throw new Error('处理失败');
      }
      const cacheDir = this.context.cacheDir + '/tools/color/';
      try { fileIo.mkdirSync(cacheDir, true); } catch {}
      const outputPath = cacheDir + `color_${Date.now()}.jpg`;
      await this.savePixelMapToFile(resultPixelMap, outputPath);
      await this.saveToGallery(outputPath);
      resultPixelMap.release();
    } catch (err) {
      console.error('导出失败:', err);
      if (this.isPageAlive) {
        promptAction.showToast({ message: `导出失败: ${(err as Error).message}` });
      }
    } finally {
      this.closeProgressDialog();
      this.isProcessing = false;
    }
  }

  // 简化：不捕获异常，让上层统一处理
  private async savePixelMapToFile(pixelMap: image.PixelMap, filePath: string): Promise<void> {
    const imagePacker = image.createImagePacker();
    const packOpts: image.PackingOption = {
      format: 'image/jpeg',
      quality: 90,
    };
    const buffer = await imagePacker.packing(pixelMap, packOpts);
    imagePacker.release();
    const fd = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(fd.fd, buffer);
    fileIo.closeSync(fd);
  }

  private async saveToGallery(filePath: string): Promise<void> {
    try {
      const phHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
      const configs: photoAccessHelper.PhotoCreationConfig[] = [
        {
          title: `色相偏移_${this.currentAngle}_${Date.now()}`,
          fileNameExtension: 'jpg',
          photoType: photoAccessHelper.PhotoType.IMAGE,
          subtype: photoAccessHelper.PhotoSubtype.DEFAULT,
        }
      ];
      const destUris = await phHelper.showAssetsCreationDialog([filePath], configs);
      if (!destUris || destUris.length === 0) {
        promptAction.showToast({ message: '用户取消保存' });
        return;
      }
      const srcFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(destUris[0], fileIo.OpenMode.WRITE_ONLY);
      fileIo.copyFileSync(srcFile.fd, destFile.fd);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(destFile);
      if (this.isPageAlive) {
        promptAction.showToast({ message: '图片已保存到相册' });
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

  private closeProgressDialog() {
    if (this.progressDialogController) {
      try { this.progressDialogController.close(); } catch {}
      this.progressDialogController = null;
    }
  }

  // ---------- UI ----------
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
          promptAction.showToast({ message: '正在处理，请稍候' });
        } else {
          this.pathStack?.pop();
        }
      })
      .height(40).width(40).buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('迷幻变色')
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
  buildPreview() {
    Stack() {
      if (this.isLoading) {
        LoadingProgress().width(48).height(48)
      } else if (this.isProcessing) {
        LoadingProgress().width(48).height(48)
      } else if(this.displayPixelMap){
        Image(this.displayPixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
      } else {
        Text('加载失败')
          .fontColor($r('sys.color.font_primary'))
      }
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
  }

  @Builder
  buildSlider() {
    Column({ space: 12 }) {
      Row() {
        Text('色相偏移')
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
        Blank()
        Text(`${Math.round(this.currentAngle)}°`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
      }
      .width('100%')

      Slider({
        value: this.currentAngle,
        min: 0,
        max: 360,
        step: 1,
        style: SliderStyle.OutSet,
      })
        .width('100%')
        .trackThickness(4)
        .selectedColor($r('app.color.brand'))
        .blockColor($r('app.color.brand'))
        .onChange((value: number, mode: SliderChangeMode) => {
          this.currentAngle = value;
          if (mode === SliderChangeMode.End) {
            this.onSliderChangeEnd(value);
          }
        })
        .enabled(!this.isProcessing)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('sys.color.background_tertiary'))
    .borderRadius(16)
  }

  build() {
    NavDestination() {
      Column() {
        this.buildTopBar();
        this.buildPreview();
        Column() {
          this.buildSlider();
          Button('导出并保存')
            .height(48)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.brand'))
            .fontColor(Color.White)
            .borderRadius(24)
            .onClick(() => this.startExport())
            .enabled(!this.isProcessing && !this.isLoading)
            .width('90%')
        }
        .width('100%')
        .backgroundColor($r('sys.color.background_tertiary'))
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
        this.loadImage();
      } else {
        this.pathStack.pop();
        return;
      }
    })
  }
}
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { PixelPos } from '../common/CommonInterfaces';

@Builder
export function ImageColorPickerPageBuilder() {
  ImageColorPickerPage();
}

@Component
export struct ImageColorPickerPage {
  private pathStack: NavPathStack | null = null;
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  @State imageUri: string = '';
  @State pixelMap: image.PixelMap | null = null;
  @State isLoading: boolean = true;

  private imageDisplayWidth: number = 0;
  private imageDisplayHeight: number = 0;
  private imagePixelWidth: number = 0;
  private imagePixelHeight: number = 0;
  private pixelData: Uint8Array | null = null;

  @State currentColor: string = '#000000';
  @State currentRgb: string = 'rgb(0, 0, 0)';
  @State currentHsl: string = 'hsl(0, 0%, 0%)';
  @State hasColor: boolean = false;

  @State magnifierX: number = 0;
  @State magnifierY: number = 0;
  @State magnifierColor: string = '#000000';
  @State showMagnifier: boolean = false;

  private isPageAlive: boolean = true;

  aboutToAppear() {
  }

  aboutToDisappear() {
    this.isPageAlive = false;
    if (this.pixelMap) {
      try { this.pixelMap.release(); } catch {}
      this.pixelMap = null;
    }
    this.pixelData = null;
  }

  private async loadImage() {
    try {
      this.isLoading = true;
      const pixelMap = await this.getPixelMapFromUri(this.imageUri);
      if (!pixelMap) {
        throw new Error('加载图片失败');
      }
      this.pixelMap = pixelMap;
      const info = pixelMap.getImageInfoSync();
      this.imagePixelWidth = info.size.width;
      this.imagePixelHeight = info.size.height;

      // 一次性读取所有像素到 buffer，并缓存为 Uint8Array
      const bufferSize = this.imagePixelWidth * this.imagePixelHeight * 4; // RGBA_8888
      const buffer = new ArrayBuffer(bufferSize);
      pixelMap.readPixelsToBufferSync(buffer);
      this.pixelData = new Uint8Array(buffer);

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

  private onImageAreaChange(area: Area) {
    if (area.width && area.height) {
      this.imageDisplayWidth = area.width as number;
      this.imageDisplayHeight = area.height as number;
    }
  }

  private viewToPixel(viewX: number, viewY: number): PixelPos | null {
    if (!this.pixelData || this.imageDisplayWidth === 0 || this.imageDisplayHeight === 0) {
      return null;
    }
    const imgW = this.imagePixelWidth;
    const imgH = this.imagePixelHeight;
    const viewW = this.imageDisplayWidth;
    const viewH = this.imageDisplayHeight;

    const scaleX = viewW / imgW;
    const scaleY = viewH / imgH;
    const scale = Math.min(scaleX, scaleY);

    const displayW = imgW * scale;
    const displayH = imgH * scale;
    const offsetX = (viewW - displayW) / 2;
    const offsetY = (viewH - displayH) / 2;

    if (viewX < offsetX || viewX > offsetX + displayW || viewY < offsetY || viewY > offsetY + displayH) {
      return null;
    }

    const pixelX = (viewX - offsetX) / scale;
    const pixelY = (viewY - offsetY) / scale;

    return {
      x: Math.min(imgW - 1, Math.max(0, Math.round(pixelX))),
      y: Math.min(imgH - 1, Math.max(0, Math.round(pixelY)))
    };
  }

  // 从缓存的像素数据中直接读取颜色（纯内存操作）
  private getPixelColor(x: number, y: number): string | null {
    if (!this.pixelData) return null;
    try {
      const width = this.imagePixelWidth;
      const index = (y * width + x) * 4; // RGBA_8888
      const r = this.pixelData[index];
      const g = this.pixelData[index + 1];
      const b = this.pixelData[index + 2];
      const a = this.pixelData[index + 3];
      if (a === 0) return null;
      return '#' + [r, g, b].map(c => c.toString(16).padStart(2, '0')).join('');
    } catch (err) {
      console.error('读取像素失败:', err);
      return null;
    }
  }

  private colorToRgb(hex: string): string {
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    return `rgb(${r}, ${g}, ${b})`;
  }

  private colorToHsl(hex: string): string {
    const r = parseInt(hex.slice(1, 3), 16) / 255;
    const g = parseInt(hex.slice(3, 5), 16) / 255;
    const b = parseInt(hex.slice(5, 7), 16) / 255;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    let h = 0, s = 0, l = (max + min) / 2;
    if (max !== min) {
      const d = max - min;
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
      switch (max) {
        case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break;
        case g: h = ((b - r) / d + 2) / 6; break;
        case b: h = ((r - g) / d + 4) / 6; break;
      }
    }
    return `hsl(${Math.round(h * 360)}, ${Math.round(s * 100)}%, ${Math.round(l * 100)}%)`;
  }

  private handleTouch(event: TouchEvent) {
    if (!this.pixelData) return;
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      // 只隐藏放大镜，颜色信息保留
      this.showMagnifier = false;
      return;
    }

    const touch = event.touches[0];
    const viewX = touch.x;
    const viewY = touch.y;

    const pixel = this.viewToPixel(viewX, viewY);
    if (!pixel) {
      this.showMagnifier = false;
      return;
    }

    const colorHex = this.getPixelColor(pixel.x, pixel.y);
    if (!colorHex) {
      this.showMagnifier = false;
      return;
    }

    // 更新颜色信息（始终显示）
    this.currentColor = colorHex;
    this.currentRgb = this.colorToRgb(colorHex);
    this.currentHsl = this.colorToHsl(colorHex);
    this.magnifierColor = colorHex;
    this.hasColor = true; // 标记已取色
    this.showMagnifier = true;

    let top = viewY - 120;
    if (top < 0) top = 0;
    let left = viewX - 40;
    if (left < 0) left = 0;
    const maxLeft = this.imageDisplayWidth - 80;
    if (left > maxLeft) left = maxLeft;

    this.magnifierX = left;
    this.magnifierY = top;
  }

  private copyHex() {
    if (!this.currentColor) return;
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const pasteData = pasteboard.createPlainTextData(this.currentColor);
      systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: '已复制 ' + this.currentColor });
    } catch (err) {
      console.error('复制失败:', err);
      promptAction.showToast({ message: '复制失败' });
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
      .onClick(() => this.pathStack?.pop())
      .height(40).width(40).buttonStyle(ButtonStyleMode.TEXTUAL)

      Text('图片取色器')
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
  buildMagnifier() {
    if (this.showMagnifier) {
      Column() {
        Circle({ width: 80, height: 80 })
          .fill(this.magnifierColor)
          .stroke(Color.White)
      }
      .position({ x: this.magnifierX, y: this.magnifierY })
      .width(80)
      .height(90)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  build() {
    NavDestination() {
      Column() {
        this.buildTopBar();

        Stack() {
          if (this.isLoading) {
            LoadingProgress().width(48).height(48)
          } else if (this.pixelMap) {
            Image(this.pixelMap)
              .width('100%')
              .height('100%')
              .draggable(false)
              .objectFit(ImageFit.Contain)
              .onAreaChange((oldArea: Area, newArea: Area) => {
                this.onImageAreaChange(newArea);
              })
              .onTouch((event: TouchEvent) => {
                this.handleTouch(event);
              })
          } else {
            Text('加载失败')
          }

          this.buildMagnifier()
        }
        .width('100%')
        .layoutWeight(1)
        .clip(true)

        Column({ space: 12 }) {
          if (!this.hasColor) {
            Text('点击或滑动图片取色')
              .fontSize(16)
              .fontColor($r('sys.color.font_primary'))
              .height(80)
          } else {
            Row({ space: 12 }) {
              Rect()
                .width(32)
                .height(32)
                .fill(this.currentColor)
                .borderRadius(4)
                .border({ width: 1, color: '#E0E0E0' })

              Text(this.currentColor)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)

              Button('复制')
                .fontSize(14)
                .fontColor($r('app.color.brand'))
                .backgroundColor(Color.Transparent)
                .onClick(() => this.copyHex())
            }
            .width('100%')

            Row({ space: 12 }) {
              Text(this.currentRgb)
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
              Text(this.currentHsl)
                .fontSize(14)
                .fontColor($r('sys.color.font_primary'))
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
          }
        }
        .height(101)
        .width('100%')
        .padding(16)
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
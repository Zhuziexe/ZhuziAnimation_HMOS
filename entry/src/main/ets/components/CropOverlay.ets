import { RenderRect } from '../common/CommonInterfaces';

@Component
export struct CropOverlay {
  @Prop @Watch('onCropChanged') cropRect: RenderRect = { x: 0, y: 0, width: 0, height: 0 };
  @Prop @Watch('onSizeChanged') imageWidth: number = 0;
  @Prop @Watch('onSizeChanged') imageHeight: number = 0;
  @Prop @Watch('onSizeChanged') renderX: number = 0;
  @Prop @Watch('onSizeChanged') renderY: number = 0;
  @Prop @Watch('onSizeChanged') renderWidth: number = 0;
  @Prop @Watch('onSizeChanged') renderHeight: number = 0;
  onCropChange: (newRect: RenderRect) => void = () => {};

  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D();
  private dragMode: string = 'none';
  private startX: number = 0;
  private startY: number = 0;
  private startCrop: RenderRect = { x: 0, y: 0, width: 0, height: 0 };

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
    let nc: RenderRect = {
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
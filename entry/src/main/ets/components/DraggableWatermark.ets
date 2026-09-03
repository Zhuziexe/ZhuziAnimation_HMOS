import {RenderRect} from '../common/CommonInterfaces'

@Component
export struct DraggableWatermark {
  @Prop text: string = '';
  @Prop fontSize: number = 30;
  @Prop fontColor: string = '#FFFFFF';
  @Prop alpha: number = 0.8;
  @State x: number = 0;
  @State y: number = 0;
  @Prop renderRect: RenderRect = { x: 0, y: 0, width: 0, height: 0 };

  onPositionChange: (x: number, y: number) => void = () => {};

  private startX: number = 0;
  private startY: number = 0;
  private offsetX: number = 0;
  private offsetY: number = 0;
  private isDragging: boolean = false;

  private getTextWidth(): number {
    const charWidth = this.fontSize * 0.6;
    return this.text.length * charWidth;
  }

  build() {
    Column() {
      Text(this.text)
        .fontSize(this.fontSize)
        .fontColor(this.fontColor)
        .opacity(this.alpha)
        .textAlign(TextAlign.Start)
        .lineHeight(this.fontSize)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Clip })
    }
    .border({ width: 2, color: '#00BFFF', style: BorderStyle.Solid })
    .backgroundColor('rgba(0,0,0,0)')
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
          const tw = this.getTextWidth();
          const th = this.fontSize;
          const minX = this.renderRect.x;
          const minY = this.renderRect.y;
          const maxX = this.renderRect.x + this.renderRect.width - tw;
          const maxY = this.renderRect.y + this.renderRect.height - th;
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
  }
}
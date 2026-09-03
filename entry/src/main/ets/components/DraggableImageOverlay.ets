import { RenderRect } from "../common/CommonInterfaces";

@Component
export struct DraggableImageOverlay {
  @Prop imageUri: string = '';
  @Prop imageWidth: number = 0;
  @Prop imageHeight: number = 0;
  @Prop imageAlpha: number = 1.0;
  @State x: number = 0;
  @State y: number = 0;
  @Prop renderRect: RenderRect = { x: 0, y: 0, width: 0, height: 0 };

  onPositionChange: (x: number, y: number) => void = () => {};

  private startX: number = 0;
  private startY: number = 0;
  private offsetX: number = 0;
  private offsetY: number = 0;
  private isDragging: boolean = false;

  build() {
    Image(this.imageUri)
      .width(this.imageWidth)
      .height(this.imageHeight)
      .objectFit(ImageFit.Fill)
      .opacity(this.imageAlpha)
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
            const minX = this.renderRect.x;
            const minY = this.renderRect.y;
            const maxX = this.renderRect.x + this.renderRect.width - this.imageWidth;
            const maxY = this.renderRect.y + this.renderRect.height - this.imageHeight;
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
      .border({ width: 2, color: '#00BFFF', style: BorderStyle.Solid })
  }
}
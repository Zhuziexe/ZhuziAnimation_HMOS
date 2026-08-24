@Component
export struct ControlBar {
  @Prop isPlaying: boolean = false;
  @Prop progress: number = 0;
  @Prop max: number = 0;
  onPlayToggle: () => void = () => {};
  onProgressChange: (pos: number) => void = () => {};

  build() {
    Row() {
      Button(){
        SymbolGlyph(this.isPlaying?$r('sys.symbol.pause'):$r('sys.symbol.play_fill'))
      }
        .width(48)
        .height(48)
        .fontSize(20)
        .onClick(() => this.onPlayToggle())

      Slider({
        value: this.progress,
        min: 0,
        max: this.max > 0 ? this.max : 1,
        step: 1
      })
        .layoutWeight(1)
        .margin({ left: 12, right: 12 })
        .onChange((value: number) => {
          if (!this.isPlaying) {
            this.onProgressChange(Math.round(value));
          }
        })
      Text(`${this.progress+1}/${this.max+1}`)
        .fontSize(14)
        .fontColor('#666')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('sys.color.background_tertiary'))
    .shadow({ radius: 2, color: '#1A000000', offsetY: -2 })
  }
}
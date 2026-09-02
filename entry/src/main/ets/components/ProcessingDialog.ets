@CustomDialog
export struct ProcessingDialog {
  controller?: CustomDialogController;
  processingText: string = '处理中...';
  secondaryText: string = '请稍候，处理可能需要一些时间。';
  onCancel: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      LoadingProgress().width(48).height(48)
      Text(this.processingText)
        .fontSize(18)
        .fontColor($r('sys.color.font_primary'))
      Text(this.secondaryText)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
      Button('取消')
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .onClick(() => {
          this.onCancel();
          this.controller?.close();
        })
        .fontColor($r('app.color.brand'))
        .width(120)
    }
    .padding(24)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_tertiary'))
  }
}
@Component
export struct Preview {
  @Prop imageUri: string = '';

  build() {
    Stack() {
      if (this.imageUri) {
        Image(this.imageUri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
      } else {
        Text('无帧')
          .fontSize(20)
          .fontColor('#999')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1E1E1E')
  }
}
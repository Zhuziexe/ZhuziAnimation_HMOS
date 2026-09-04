@CustomDialog
export struct PropertiesDialog {
  controller?: CustomDialogController;
  onConfirm?: (fps: number, ratio: number) => void;

  private optionsFps: SelectOption[] = [
    { value: '默认(10 FPS)' },
    { value: '12 FPS' },
    { value: '6 FPS' }
  ];
  private optionsRatio: SelectOption[] = [
    { value: '横屏' },
    { value: '竖屏' },
    { value: '1:1' }
  ];

  paramFPS: number = 0;
  paramRatio: number = 0;

  @State selectedIndexFPS: number = 0;
  @State selectedTextFPS: string = this.optionsFps[0].value.toString();
  @State selectedIndexRatio: number = 0;
  @State selectedTextRatio: string = this.optionsRatio[0].value.toString();
  @State enabledRatio: boolean = false;

  aboutToAppear(): void {
    if (this.paramFPS === 12) {
      this.selectedIndexFPS = 1;
      this.selectedTextFPS = this.optionsFps[1].value.toString();
    } else if (this.paramFPS === 6) {
      this.selectedIndexFPS = 2;
      this.selectedTextFPS = this.optionsFps[2].value.toString();
    } else {
      this.selectedIndexFPS = 0;
      this.selectedTextFPS = this.optionsFps[0].value.toString();
    }

    if (this.paramRatio === 1) {
      this.selectedIndexRatio = 1;
      this.selectedTextRatio = this.optionsRatio[1].value.toString();
    } else if (this.paramRatio === 2) {
      this.selectedIndexRatio = 2;
      this.selectedTextRatio = this.optionsRatio[2].value.toString();
    } else {
      this.selectedIndexRatio = 0;
      this.selectedTextRatio = this.optionsRatio[0].value.toString();
    }
  }

  getSelectedFPS(): number {
    const value = this.optionsFps[this.selectedIndexFPS].value;
    if (value === this.optionsFps[1].value.toString()) return 12;
    if (value === this.optionsFps[2].value.toString()) return 6;
    return 10;
  }

  getSelectedRatio(): number {
    const value = this.optionsRatio[this.selectedIndexRatio].value;
    if (value === this.optionsRatio[1].value.toString()) return 1;
    if (value === this.optionsRatio[2].value.toString()) return 2;
    return 0;
  }

  build() {
    Column({ space: 20 }) {
      Text('属性')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)

      Row({ space: 20 }) {
        Text('帧率:')
          .width(60)
        Select(this.optionsFps)
          .selected(this.selectedIndexFPS)
          .value(this.selectedTextFPS)
          .onSelect((index: number, value: string) => {
            this.selectedIndexFPS = index;
            this.selectedTextFPS = value;
          })
          .layoutWeight(1)
          .height(50)
      }
      .width('100%')

      Row({ space: 20 }) {
        Text('比例:')
          .width(60)
        Select(this.optionsRatio)
          .selected(this.selectedIndexRatio)
          .value(this.selectedTextRatio)
          .onSelect((index: number, value: string) => {
            this.selectedIndexRatio = index;
            this.selectedTextRatio = value;
          })
          .layoutWeight(1)
          .height(50)
          .enabled(this.enabledRatio)
      }
      .width('100%')

      Row({ space: 20 }) {
        Button('取消')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .onClick(() => { this.controller?.close(); })
          .layoutWeight(1)
        Button('确定')
          .onClick(() => {
            this.onConfirm?.(this.getSelectedFPS(), this.getSelectedRatio());
            this.controller?.close();
          })
          .layoutWeight(1)
      }
    }
    .padding(20)
  }
}

@CustomDialog
export struct SavingDialog {
  controller?: CustomDialogController;
  @State message: string = '保存中...';

  build() {
    Column() {
      Row() {
        LoadingProgress()
          .width(40)
          .height(40)
        Text(this.message)
          .fontSize(16)
          .margin({ left: 12 })
      }
      .padding(20)
    }
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_tertiary'))
  }
}

@CustomDialog
export struct ExportProgressDialog {
  controller?: CustomDialogController;
  onCancel?: () => void;

  build() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(48)
        .height(48)
      Text('导出中...')
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
      Button('取消')
        .onClick(() => {
          this.onCancel?.();
          this.controller?.close();
        })
        .width(120)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
    }
    .padding(24)
    .borderRadius(12)
    .backgroundColor($r('sys.color.background_tertiary'))
  }
}

@CustomDialog
export struct SaveOptionsDialog {
  controller?: CustomDialogController;
  onSave?: ()=>void;
  onDontSave?: ()=>void;
  onCancel?: () => void;

  build() {
    Column({space:12}){
      Text('提示')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)
        .fontColor($r('sys.color.font_primary'))
      Text('有未保存的更改，是否保存？')
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .textAlign(TextAlign.Center)

      Button('保存')
        .backgroundColor($r('app.color.brand'))
        .fontColor(Color.White)
        .width('100%')
        .onClick(() => {
          this.controller?.close();
          this.onSave?.();
        })

      Button('不保存')
        .buttonStyle(ButtonStyleMode.NORMAL)
        .fontColor($r('sys.color.warning'))
        .width('100%')
        .onClick(() => {
          this.controller?.close();
          this.onDontSave?.();
        })

      Button('取消')
        .buttonStyle(ButtonStyleMode.NORMAL)
        .fontColor($r('sys.color.font_primary'))
        .width('100%')
        .onClick(() => {
          this.controller?.close();
          this.onCancel?.();
        })
    }
    .padding(16)
  }
}
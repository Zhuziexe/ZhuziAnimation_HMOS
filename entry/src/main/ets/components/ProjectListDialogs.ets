export interface ZapHeader {
  fps: number;
  frameCount: number;
  ratioIndex: number;
}

@CustomDialog
export struct NewProjectDialog {
  controller?: CustomDialogController;
  onConfirm: (name: string) => void = () => {};
  @Prop projectNames: string[] = []; // 已有的项目名称列表

  @State inputText: string = '';
  @State errorMsg: string = '';

  /**
   * 校验项目名称
   * @param name 待校验的名称
   * @returns 是否通过校验
   */
  private validateName(name: string): boolean {
    const trimmed = name.trim();
    // 1. 不能为空
    if (!trimmed) {
      this.errorMsg = '项目名称不能为空';
      return false;
    }
    // 2. 不能包含 Windows 文件名非法字符：\ / : * ? " < > |
    if (/[\\/:*?"<>|]/.test(trimmed)) {
      this.errorMsg = '项目名称不能包含 \\ / : * ? " < > | 等特殊字符';
      return false;
    }
    // 3. 不能与已有项目重名（不区分大小写）
    if (this.projectNames.some(existing => existing.toLowerCase() === trimmed.toLowerCase())) {
      this.errorMsg = '已存在同名项目，请修改名称';
      return false;
    }
    // 校验通过
    this.errorMsg = '';
    return true;
  }

  build() {
    Column({ space: 16 }) {
      Text('新项目')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))

      TextInput({ placeholder: '请输入项目名称', text: this.inputText })
        .width('100%')
        .onChange((value: string) => {
          this.inputText = value;
          // 用户输入时清除错误信息
          if (this.errorMsg) {
            this.errorMsg = '';
          }
        })

      // 显示错误信息
      if (this.errorMsg) {
        Text(this.errorMsg)
          .fontSize(14)
          .fontColor(Color.Red)
          .width('100%')
      }

      Row({ space: 20 }) {
        Button('取消')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .onClick(() => {
            this.controller?.close();
          })
          .layoutWeight(1)

        Button('创建')
          .buttonStyle(ButtonStyleMode.EMPHASIZED)
          .onClick(() => {
            // 执行校验
            if (this.validateName(this.inputText)) {
              // 校验通过，调用回调，传递去除首尾空格后的名称
              this.onConfirm(this.inputText.trim());
              this.controller?.close();
            }
          })
          .enabled(this.inputText != '')
          .layoutWeight(1)
      }
      .width('100%')
    }
    .padding(20)
    .borderRadius(12)
  }
}

@CustomDialog
export struct RenameProjectDialog {
  controller?: CustomDialogController;
  currentName: string = '';
  projectNames: string[] = []; // 所有项目名称列表（含自身），用于重名校验
  onConfirm: (newName: string) => void = () => {};

  @State inputText: string = '';
  @State errorMsg: string = '';

  aboutToAppear() {
    this.inputText = this.currentName;
  }

  private validateName(name: string): boolean {
    const trimmed = name.trim();
    if (!trimmed) {
      this.errorMsg = '项目名称不能为空';
      return false;
    }
    if (/[\\/:*?"<>|]/.test(trimmed)) {
      this.errorMsg = '项目名称不能包含 \\ / : * ? " < > | 等特殊字符';
      return false;
    }
    // 检查是否与其它项目重名（不区分大小写），排除自身
    if (this.projectNames.some(existing =>
    existing.toLowerCase() === trimmed.toLowerCase() &&
      existing !== this.currentName
    )) {
      this.errorMsg = '已存在同名项目，请修改名称';
      return false;
    }
    this.errorMsg = '';
    return true;
  }

  build() {
    Column({ space: 16 }) {
      Text('重命名项目')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary'))

      TextInput({ placeholder: '请输入新名称', text: this.inputText })
        .width('100%')
        .onChange((value: string) => {
          this.inputText = value;
          if (this.errorMsg) {
            this.errorMsg = '';
          }
        })

      if (this.errorMsg) {
        Text(this.errorMsg)
          .fontSize(14)
          .fontColor(Color.Red)
          .width('100%')
      }

      Row({ space: 20 }) {
        Button('取消')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .onClick(() => this.controller?.close())
          .layoutWeight(1)

        Button('确定')
          .buttonStyle(ButtonStyleMode.EMPHASIZED)
          .onClick(() => {
            if (this.validateName(this.inputText)) {
              this.onConfirm(this.inputText.trim());
              this.controller?.close();
            }
          })
          .enabled(this.inputText !== '')
          .layoutWeight(1)
      }
      .width('100%')
    }
    .padding(20)
    .borderRadius(12)
  }
}
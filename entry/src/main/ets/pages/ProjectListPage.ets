import router from '@ohos.router';
import { ProjectManager, ProjectMeta } from '../common/ProjectManager';
import { ZapUtils } from '../common/ZapUtils';
import { common } from '@kit.AbilityKit';
import { HdsTabsController, HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { ToolsContent } from '../components/ToolsContent';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';

@CustomDialog
struct NewProjectDialog {
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

@Entry
@Component
struct ProjectListPage {
  @State projects: ProjectMeta[] = [];
  @State sortBy: 'name' | 'time' = 'time';
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private newProjectDialogController: CustomDialogController | null = null;

  @State tabPressedStates: boolean[] = [false, false];
  @State currentIndex: number = 0;
  private tabcont: HdsTabsController = new HdsTabsController();

  @Builder
  TabBarBuilder(title: string, index: number, IconSymbol: Resource) {
    Column() {
      SymbolGlyph(IconSymbol)
        .width(24)
        .height(24)
        .fontSize(24)
        .fontColor([this.currentIndex === index ? $r('sys.color.background_emphasize') : $r('sys.color.font_primary')])
        .scale({
          x: this.tabPressedStates[index] ? 0.85 : 1.0,
          y: this.tabPressedStates[index] ? 0.85 : 1.0,
        })
      Text(title)
        .fontSize(12)
        .fontColor(this.currentIndex === index ? $r('sys.color.background_emphasize') : $r('sys.color.font_primary'))
        .margin({ top: 2 })
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        animateTo({ duration: 100, curve: Curve.EaseIn }, () => {
          this.tabPressedStates[index] = true;
        });
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        animateTo({ duration: 100, curve: Curve.EaseOut }, () => {
          this.tabPressedStates[index] = false;
        });
      }
    })
  }

  async exportZapProject(project: ProjectMeta) {
    try {
      const srcPath = project.filePath;
      const srcFile = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(srcFile.fd);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(srcFile.fd, buffer);
      fileIo.closeSync(srcFile);

      const options = new picker.DocumentSaveOptions();
      const fileName = project.name.endsWith('.zap') ? project.name : project.name + '.zap';
      options.newFileNames = [fileName];
      options.fileSuffixChoices = ['ZAP文件|.zap'];

      const documentPicker = new picker.DocumentViewPicker(this.context);
      const uris = await documentPicker.save(options);

      if (uris && uris.length > 0) {
        const destUri = uris[0];
        const destFile = fileIo.openSync(destUri,
          fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
        );
        fileIo.writeSync(destFile.fd, buffer);
        fileIo.closeSync(destFile);
        promptAction.showToast({ message: '导出成功' });
      } else {
        promptAction.showToast({ message: '取消导出' });
      }
    } catch (err) {
      console.error('导出ZAP失败:', err);
      const errorMsg = err instanceof Error ? err.message : String(err);
      promptAction.showToast({ message: `导出失败: ${errorMsg}` });
    }
  }

  onPageShow() {
    console.log("刷新");
    this.loadProjects();
  }

  aboutToAppear() {
    ProjectManager.init(this.context);
    ZapUtils.init(this.context);
    this.loadProjects();
  }

  async loadProjects() {
    const list = await ProjectManager.getProjects();
    this.projects = ProjectManager.sortProjects(list, this.sortBy);
  }

  createProject() {
    if (this.newProjectDialogController) {
      this.newProjectDialogController.close();
      this.newProjectDialogController = null;
    }
    this.newProjectDialogController = new CustomDialogController({
      builder: NewProjectDialog({
        // 传入已有项目名称列表，供重名校验使用
        projectNames: this.projects.map(p => p.name),
        onConfirm: (name: string) => {
          router.pushUrl({
            url: 'pages/EditorPage',
            params: { projectName: name }
          });
        }
      })
    });
    this.newProjectDialogController.open();
  }

  openProject(project: ProjectMeta) {
    router.pushUrl({
      url: 'pages/EditorPage',
      params: { projectId: project.id }
    });
  }

  async deleteProject(project: ProjectMeta, index: number) {
    AlertDialog.show({
      title: '确认删除',
      message: `确定要删除项目“${project.name}”吗？`,
      confirm: {
        value: '删除',
        action: async () => {
          await ProjectManager.deleteProject(project.id);
          this.projects.splice(index, 1);
          this.projects = [...this.projects];
        }
      },
      cancel: () => {}
    });
  }

  build() {
    Column() {
      HdsTabs({
        controller: this.tabcont
      }) {
        // ---------- 第一个 TabContent：项目列表 ----------
        TabContent() {
          Stack() {
            // 列表内容（位于下层，顶部留出标题栏高度）
            Column() {
              if (this.projects.length === 0) {
                Column() {
                  Text('还没有项目')
                    .fontSize(18)
                    .fontColor($r('sys.color.font_primary'))
                  Text('点击右上角 + 创建新项目')
                    .fontSize(14)
                    .fontColor($r('sys.color.font_secondary'))
                    .margin({ top: 8 })
                }
                .width('100%')
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
                .padding({ top: 56, bottom: 80 })
              } else {
                List({ space: 4 }) {
                  ForEach(this.projects, (project: ProjectMeta, index: number) => {
                    ListItem() {
                      Row() {
                        SymbolGlyph($r('sys.symbol.template'))
                          .fontSize(32)
                          .width(40)
                          .height(40)
                          .fontColor([$r('sys.color.font_primary')])

                        Column() {
                          Text(project.name)
                            .fontSize(18)
                            .fontWeight(FontWeight.Medium)
                            .fontColor($r('sys.color.font_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                          Row() {
                            Text(`帧数: ${project.frameCount}`)
                              .fontSize(14)
                              .fontColor($r('sys.color.font_secondary'))
                            Text('  ')
                            Text(new Date(project.lastModified).toLocaleString())
                              .fontSize(14)
                              .fontColor($r('sys.color.font_secondary'))
                          }
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start)
                        .padding({ left: 12 })

                        Button() {
                          SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
                            .fontSize(28)
                            .fontColor([$r('sys.color.font_primary')])
                        }
                        .buttonStyle(ButtonStyleMode.TEXTUAL)
                        .backgroundColor(Color.Transparent)
                        .bindMenu([
                          {
                            value: '导出ZAP文件',
                            action: () => this.exportZapProject(project)
                          },
                          {
                            value: '删除',
                            action: () => this.deleteProject(project, index)
                          }
                        ])
                        .width(40)
                        .height(40)
                      }
                      .width('100%')
                      .height(72)
                      .padding({ left: 16, right: 8 })
                      .backgroundColor($r('app.color.listitem'))
                      .borderRadius(8)
                      .onClick(() => this.openProject(project))
                    }
                    .margin({ left: 16, right: 16 })
                  }, (project: ProjectMeta) => project.id)
                }
                .layoutWeight(1)
                .width('100%')
                .contentEndOffset(80)
                .contentStartOffset(56)
              }
            }
            .width('100%')
            .height('100%')
            .backgroundColor($r('sys.color.background_secondary'))

            // ---------- 悬浮标题栏（上层） ----------
            Row() {
              Text('竹子定格动画')
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)

              Button(this.sortBy === 'time' ? '按时间' : '按名称')
                .fontSize(14)
                .backgroundColor($r('sys.color.background_tertiary'))
                .fontColor($r('sys.color.font_primary'))
                .onClick(() => {
                  this.sortBy = this.sortBy === 'time' ? 'name' : 'time';
                  this.projects = ProjectManager.sortProjects(this.projects, this.sortBy);
                })

              Button() {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(24)
                  .fontColor([Color.White])
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor($r('sys.color.background_emphasize'))
              .margin({ left: 8 })
              .onClick(() => this.createProject())
            }
            .width('100%')
            .height(56)
            .padding({ left: 16, right: 16 })
            .position({ x: 0, y: 0 })
            .zIndex(1)
            .backgroundColor('#00000000')
            .linearGradient({
              angle: 0,
              colors: [
                [$r('app.color.titlebar_gradient_end'), 0.0],
                [$r('sys.color.background_secondary'), 1.0]
              ]
            })
          }
          .width('100%')
          .height('100%')
        }
        .tabBar(this.TabBarBuilder('定格动画', 0, $r('sys.symbol.template_fill')))

        // ---------- 第二个 TabContent：工具 ----------
        TabContent() {
          ToolsContent()
        }
        .tabBar(this.TabBarBuilder('小工具', 1, $r('sys.symbol.more_fill')))
      }
      .barPosition(BarPosition.End)
      .vertical(false)
      .barOverlap(true)
      .barFloatingStyle({
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .onChange((index: number) => {
        this.currentIndex = index;
      })
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
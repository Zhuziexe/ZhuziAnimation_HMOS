import router from '@ohos.router';
import { ProjectManager, ProjectMeta } from '../common/ProjectManager';
import { ZapUtils } from '../common/ZapUtils';
import { common } from '@kit.AbilityKit';

@CustomDialog
struct NewProjectDialog {
  controller?: CustomDialogController;
  onConfirm: (name: string) => void = () => {};

  @State inputText: string = '';

  build() {
    Column({ space: 16 }) {
      Text('新项目')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_primary')) // 显式使用系统色

      TextInput({ placeholder: '请输入项目名称', text: this.inputText })
        .width('80%')
        .onChange((value: string) => {
          this.inputText = value;
        })

      Row({ space: 20 }) {
        Button('取消')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .onClick(() => {
            this.controller?.close();
          })
        Button('创建')
          .buttonStyle(ButtonStyleMode.EMPHASIZED)
          .onClick(() => {
            if (this.inputText.trim()) {
              this.onConfirm(this.inputText.trim());
              this.controller?.close();
            }
          })
      }
    }
    .padding(20)
    .borderRadius(12) // 为了美观加一点圆角
  }
}

@Entry
@Component
struct ProjectListPage {
  @State projects: ProjectMeta[] = [];
  @State sortBy: 'name' | 'time' = 'time';
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private newProjectDialogController: CustomDialogController | null = null;

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
      Row() {
        Text('竹子定格动画')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)

        Button(this.sortBy === 'time' ? '按时间' : '按名称')
          .fontSize(14)
          .backgroundColor($r('sys.color.background_tertiary')) // 透明背景，颜色继承
          .fontColor($r('sys.color.font_primary')) // 显式指定次级文字色
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
        .fontColor($r('sys.color.font_primary')) // 图标颜色跟随系统
        .margin({ left: 8 })
        .onClick(() => this.createProject())
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('sys.color.background_primary'))

      if (this.projects.length === 0) {
        Column() {
          Text('还没有项目')
            .fontSize(18)
            .fontColor($r('sys.color.font_primary'))
          Text('点击右上角 + 创建新项目')
            .fontSize(14)
            .fontColor($r('sys.color.font_secondary')) // 使用次级文字色
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 4 }) {
          ForEach(this.projects, (project: ProjectMeta, index: number) => {
            ListItem() {
              Row() {
                SymbolGlyph($r('sys.symbol.folder'))
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
                  SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                    .fontSize(28)
                    .fontColor([$r('sys.color.font_primary')])
                }
                .buttonStyle(ButtonStyleMode.TEXTUAL)
                .backgroundColor(Color.Transparent)
                .bindMenu([
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
              .backgroundColor($r('sys.color.comp_background_tertiary'))
              .borderRadius(8)
              .onClick(() => this.openProject(project))
            }
            .margin({ left: 16, right: 16 })
          })
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('sys.color.background_primary'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]) // 顺便解决小白条沉浸
  }
}
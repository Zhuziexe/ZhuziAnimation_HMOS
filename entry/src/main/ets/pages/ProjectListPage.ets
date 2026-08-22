import router from '@ohos.router';
import { ProjectManager, ProjectMeta } from '../common/ProjectManager';
import { ZapUtils } from '../common/ZapUtils';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct ProjectListPage {
  @State projects: ProjectMeta[] = [];
  @State sortBy: 'name' | 'time' = 'time';
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  onPageShow() {
    console.log("刷新");
    this.loadProjects();  // 每次显示页面时刷新列表
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
    router.pushUrl({ url: 'pages/EditorPage' });
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
          .fontColor('#333')
          .layoutWeight(1)

        Button(this.sortBy === 'time' ? '按时间' : '按名称')
          .fontSize(14)
          .fontColor('#007AFF')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.sortBy = this.sortBy === 'time' ? 'name' : 'time';
            this.projects = ProjectManager.sortProjects(this.projects, this.sortBy);
          })

        Button() {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(24)
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor('#007AFF')
        .fontColor(Color.White)
        .margin({ left: 8 })
        .onClick(() => this.createProject())
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#F5F5F5')

      if (this.projects.length === 0) {
        Column() {
          Text('还没有项目')
            .fontSize(18)
            .fontColor('#999')
          Text('点击右上角 + 创建新项目')
            .fontSize(14)
            .fontColor('#BBB')
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
                  .fontSize(28)
                  .width(40)
                  .height(40)

                Column() {
                  Text(project.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row() {
                    Text(`帧数: ${project.frameCount}`)
                      .fontSize(12)
                      .fontColor('#999')
                    Text('  ')
                    Text(new Date(project.lastModified).toLocaleString())
                      .fontSize(12)
                      .fontColor('#999')
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 12 })

                Button() {
                  SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(20)
                }
                .type(ButtonType.Normal)
                .backgroundColor(Color.Transparent)
                .bindMenu([
                  {
                    value: '删除',
                    action: () => this.deleteProject(project, index)
                  }
                ])
                .width(36)
                .height(36)
              }
              .width('100%')
              .height(64)
              .padding({ left: 16, right: 8 })
              .backgroundColor(Color.White)
              .borderRadius(8)
              .onClick(() => this.openProject(project))
            }
            .margin({ left: 16, right: 16 })
          })
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor('#F9F9F9')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F9F9F9')
  }
}
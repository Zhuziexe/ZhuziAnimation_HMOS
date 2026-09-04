import router from '@ohos.router';
import { HomeContent } from '../tabs/HomeContent';
import { ProjectManager, ProjectMeta } from '../common/ProjectManager';
import { ZapUtils } from '../common/ZapUtils';
import { common } from '@kit.AbilityKit';
import { HdsTabsController, HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { ToolsContent } from '../tabs/ToolsContent';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { LengthMetrics, promptAction, SymbolGlyphModifier, window } from '@kit.ArkUI';
import { showAbout } from '../common/ShowAbout';
import { ZapHeader, NewProjectDialog, RenameProjectDialog } from '../components/ProjectListDialogs';

@Entry
@Component
struct Index {
  @State projects: ProjectMeta[] = [];
  @State sortBy: 'name' | 'time' = 'time';
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private newProjectDialogController: CustomDialogController | null = null;
  private renameDialogController: CustomDialogController | null = null;

  private tabcont: HdsTabsController = new HdsTabsController();
  private windowClass?: window.Window;

  @StorageLink('tabindex') tabindex: number = 1;

  formatFileSize(bytes: number): string {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
  }

  showRenameDialog(project: ProjectMeta, index: number) {
    if (this.renameDialogController) {
      this.renameDialogController.close();
      this.renameDialogController = null;
    }
    const allNames = this.projects.map(p => p.name);
    this.renameDialogController = new CustomDialogController({
      builder: RenameProjectDialog({
        currentName: project.name,
        projectNames: allNames,
        onConfirm: (newName: string) => {
          this.doRename(project, index, newName);
        }
      })
    });
    this.renameDialogController.open();
  }

  private async renameProjectFile(oldPath: string, newPath: string): Promise<boolean> {
    try {
      fileIo.renameSync(oldPath, newPath);
      return true;
    } catch (e) {
      console.error('重命名文件失败:', e);
      return false;
    }
  }

  async doRename(project: ProjectMeta, index: number, newName: string) {
    try {
      const oldFrameCount = project.frameCount;
      const oldFilePath = project.filePath;

      const newId = Date.now().toString(36) + Math.random().toString(36).substring(2, 8);
      const newFilePath = `${this.context.filesDir}/${newId}.zhuziani`;

      const renameSuccess = await this.renameProjectFile(oldFilePath, newFilePath);
      if (!renameSuccess) {
        promptAction.showToast({ message: '重命名文件失败' });
        return;
      }

      await ProjectManager.deleteProject(project.id);

      const newProject: ProjectMeta = {
        id: newId,
        name: newName,
        filePath: newFilePath,
        lastModified: Date.now(),
        frameCount: oldFrameCount,
      };
      await ProjectManager.upsertProject(newProject);

      await this.loadProjects();

      promptAction.showToast({ message: '重命名成功' });
    } catch (e) {
      console.error('重命名失败:', e);
      promptAction.showToast({ message: '重命名失败，请重试' });
    }
  }

  private readZapHeader(buffer: ArrayBuffer): ZapHeader | null {
    const view = new DataView(buffer);
    let offset = 0;
    const magic = new Uint8Array(buffer, offset, 4);
    if (magic[0] !== 0x5A || magic[1] !== 0x41 || magic[2] !== 0x50 || magic[3] !== 0x31) return null;
    offset += 4;
    const version = view.getUint16(offset, true);
    if (version !== 1) return null;
    offset += 2;
    const fps = view.getUint16(offset, true);
    offset += 2;
    const frameCount = view.getUint32(offset, true);
    offset += 4;
    const ratioIndex = view.getUint8(offset);
    return { fps, frameCount, ratioIndex };
  }

  async importZapProject() {
    try {
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['ZHUZIANI文件|.zhuziani'];
      options.isEncryptionSupported = false;
      options.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker(this.context);
      const uris = await documentPicker.select(options);
      if (!uris || uris.length === 0) return;

      const sourceUri = uris[0];
      const srcFile = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(srcFile.fd);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(srcFile.fd, buffer);
      fileIo.closeSync(srcFile);

      const header = this.readZapHeader(buffer);
      if (!header) {
        promptAction.showToast({ message: '无效的 ZHUZIANI 文件' });
        return;
      }
      const frameCount = header.frameCount;

      const fileName = decodeURIComponent(sourceUri.split('/').pop() || '');
      let baseName = fileName.replace(/\.zhuziani$/i, '');
      if (!baseName) baseName = '导入项目';

      const allProjects = await ProjectManager.getProjects();
      const existingNames = allProjects.map(p => p.name.toLowerCase());
      let finalName = baseName;
      let counter = 2;
      while (existingNames.includes(finalName.toLowerCase())) {
        finalName = `${baseName}(${counter})`;
        counter++;
      }

      const newId = Date.now().toString(36) + Math.random().toString(36).substring(2, 8);
      const newFilePath = `${this.context.filesDir}/${newId}.zhuziani`;
      const destFile = fileIo.openSync(newFilePath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
      );
      fileIo.writeSync(destFile.fd, buffer);
      fileIo.closeSync(destFile);

      const meta: ProjectMeta = {
        id: newId,
        name: finalName,
        filePath: newFilePath,
        lastModified: Date.now(),
        frameCount: frameCount,
      };
      await ProjectManager.upsertProject(meta);
      await this.loadProjects();
      promptAction.showToast({ message: `导入成功，共 ${frameCount} 帧` });
    } catch (err) {
      console.error('导入 ZHUZIANI 失败:', err);
      const errorMsg = err instanceof Error ? err.message : String(err);
      promptAction.showToast({ message: `导入失败: ${errorMsg}` });
    }
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
      const fileName = project.name.endsWith('.zhuziani') ? project.name : project.name + '.zhuziani';
      options.newFileNames = [fileName];
      options.fileSuffixChoices = ['ZHUZIANI文件|.zhuziani'];

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
      console.error('导出ZHUZIANI失败:', err);
      const errorMsg = err instanceof Error ? err.message : String(err);
      promptAction.showToast({ message: `导出失败: ${errorMsg}` });
    }
  }

  onPageShow() {
    this.loadProjects();
  }

  aboutToAppear() {
    window.getLastWindow(this.context)
      .then((win) => {
        this.windowClass = win;
        const limits: window.WindowLimits = {
          minWidth: 500,
          minHeight: 400,
          maxWidth: 0,
          maxHeight: 0,
          pixelUnit: window.PixelUnit.VP
        };
        win.setWindowLimits(limits)
          .then(()=>{
            console.info('设置窗口大小限制');
          })
          .catch(() => {
            console.error('无法设置大小限制');
          });

        const rect = win.getWindowProperties().windowRect;
        AppStorage.setOrCreate('windowWidth', px2vp(rect.width));
        AppStorage.setOrCreate('windowHeight',px2vp(rect.height));

        win.on('windowSizeChange', (data) => {
          AppStorage.set('windowWidth', px2vp(data.width));
          AppStorage.set('windowHeight',px2vp(data.height))
        });
      })
      .catch((err: Error) => {
        console.error('获取窗口失败:', err);
      });

    ProjectManager.init(this.context);
    ZapUtils.init(this.context);
    (async () => {
      await this.cleanOrphanZapFiles();
    })();
  }

  async loadProjects() {
    console.log("刷新");
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
      buttons: [
        {
          value:"取消",
          action:()=>{}
        },
        {
          value:"确定",
          fontColor:$r('sys.color.warning'),
          action: async ()=>{
            await ProjectManager.deleteProject(project.id);
            this.projects.splice(index, 1);
            this.projects = [...this.projects];
          }
        }
      ]
    });
  }

  private async cleanOrphanZapFiles() {
    try {
      const projects = await ProjectManager.getProjects();
      const validPaths = new Set(projects.map(p => p.filePath));
      const filesDir = this.context.filesDir;
      const files = fileIo.listFileSync(filesDir);
      for (const file of files) {
        if (file.endsWith('.zhuziani')) {
          const fullPath = `${filesDir}/${file}`;
          if (!validPaths.has(fullPath)) {
            fileIo.unlinkSync(fullPath);
            console.info('删除孤立ZHUZIANI文件:', fullPath);
          }
        }
      }
    } catch (e) {
      console.warn('清理孤立ZHUZIANI文件失败:', e);
    }
  }

  buildBottomTabBar(icon: Resource, label: ResourceStr) : BottomTabBarStyle{
    return BottomTabBarStyle.of({
      normal: new SymbolGlyphModifier(icon)
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontColor([$r('sys.color.font_primary')]),
      selected: new SymbolGlyphModifier(icon)
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontColor([$r('app.color.brand')])
    }, label)
      .labelStyle({ unselectedColor: $r('sys.color.font_primary'),selectedColor: $r('app.color.brand') });
  }

  build() {
    Column() {
      HdsTabs({
        controller: this.tabcont,
        index: this.tabindex
      }) {
        TabContent() {
          ToolsContent()
        }
        .tabBar(
          this.buildBottomTabBar($r('sys.symbol.more_fill'),$r('app.string.tools_page'))
        )
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        TabContent() {
          HomeContent()
        }
        .tabBar(
          this.buildBottomTabBar($r('sys.symbol.house_fill'),$r('app.string.home_page'))
        )
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        TabContent() {
          Stack() {
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
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                .width('100%')
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
                .padding({ top: 56, bottom: 80 })
              }
              else {
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
                          Flex({direction:FlexDirection.Row,wrap:FlexWrap.Wrap,space:{main:LengthMetrics.vp(6)}}) {
                            Text(`帧数: ${project.frameCount}`)
                              .fontSize(14)
                              .fontColor($r('sys.color.font_secondary'))
                            Text(`大小: ${this.formatFileSize(project.size??0)}`)
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
                          { value: '导出ZHUZIANI文件', action: () => this.exportZapProject(project) },
                          { value: '重命名', action: () => this.showRenameDialog(project, index) },
                          { value: '删除', action: () => this.deleteProject(project, index) }
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
                      .hoverEffect(HoverEffect.Highlight)
                    }
                    .margin({ left: 16, right: 16 })
                  }, (project: ProjectMeta) => project.id + project.lastModified)
                }
                .layoutWeight(1)
                .width('100%')
                .contentEndOffset(80)
                .contentStartOffset(56)
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              }
            }
            .width('100%')
            .height('100%')
            .backgroundColor($r('sys.color.background_secondary'))
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

            Row() {
              Text($r('app.string.stop_motion_animation'))
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

              Button(this.sortBy === 'time' ? '按时间' : '按名称')
                .fontSize(18)
                .backgroundColor($r('app.color.icon_button'))
                .border({ width: 1, color: 'rgba(255, 255, 255, 0.3)' })
                .shadow({ radius: 10, color: 'rgba(0, 0, 0, 0.2)' })
                .fontColor($r('sys.color.font_primary'))
                .onClick(() => {
                  this.sortBy = this.sortBy === 'time' ? 'name' : 'time';
                  this.projects = ProjectManager.sortProjects(this.projects, this.sortBy);
                })
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

              Button() {
                SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
                  .fontSize(24)
                  .fontColor([$r('sys.color.font_primary')])
                  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              }
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor($r('app.color.icon_button'))
              .border({ width: 1, color: 'rgba(255, 255, 255, 0.3)' })
              .shadow({ radius: 10, color: 'rgba(0, 0, 0, 0.2)' })
              .margin({ left: 8 })
              .bindMenu([
                { value: "导入 ZHUZIANI 文件", action: () => this.importZapProject() },
                { value: "关于", action: () => showAbout() }
              ])

              Button() {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(24)
                  .fontColor([Color.White])
              }
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor($r('app.color.brand'))
              .border({ width: 1, color: 'rgba(255, 255, 255, 0.3)' })
              .shadow({ radius: 10, color: 'rgba(0, 0, 0, 0.2)' })
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
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          }
          .alignContent(Alignment.TopStart)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .width('100%')
          .height('100%')
        }
        .tabBar(
          this.buildBottomTabBar($r('sys.symbol.template_fill'),$r('app.string.stop_motion_animation'))
        )
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
      .barPosition(BarPosition.End)
      .vertical(false)
      .barOverlap(true)
      .barFloatingStyle({
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .animationDuration(0)
      .scrollable(false)
      .onChange((index: number) => {
        this.tabindex = index;
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
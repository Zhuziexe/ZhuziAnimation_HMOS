import router from '@ohos.router';
import { ProjectManager, ProjectMeta } from '../common/ProjectManager';
import { ZapUtils } from '../common/ZapUtils';
import { common } from '@kit.AbilityKit';
import { HdsTabsController, HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { ToolsContent } from '../tabs/ToolsContent';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
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
      const newFilePath = `${this.context.filesDir}/${newId}.zap`;

      // 重命名 .zap 文件
      const renameSuccess = await this.renameProjectFile(oldFilePath, newFilePath);
      if (!renameSuccess) {
        promptAction.showToast({ message: '重命名文件失败' });
        return;
      }

      // 删除旧项目元数据
      await ProjectManager.deleteProject(project.id);

      // 创建新项目元数据
      const newProject: ProjectMeta = {
        id: newId,
        name: newName,
        filePath: newFilePath,
        lastModified: Date.now(),
        frameCount: oldFrameCount,
      };
      await ProjectManager.upsertProject(newProject);

      // 刷新列表
      await this.loadProjects();

      promptAction.showToast({ message: '重命名成功' });
    } catch (e) {
      console.error('重命名失败:', e);
      promptAction.showToast({ message: '重命名失败，请重试' });
    }
  }

  // ---------- 其余方法保持不变 ----------
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
      options.fileSuffixFilters = ['ZAP文件|.zap'];
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
        promptAction.showToast({ message: '无效的 ZAP 文件' });
        return;
      }
      const frameCount = header.frameCount;

      const fileName = decodeURIComponent(sourceUri.split('/').pop() || '');
      let baseName = fileName.replace(/\.zap$/i, '');
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
      const newFilePath = `${this.context.filesDir}/${newId}.zap`;
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
      console.error('导入 ZAP 失败:', err);
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
    this.loadProjects();
  }

  aboutToAppear() {
    ProjectManager.init(this.context);
    ZapUtils.init(this.context);
    this.loadProjects();
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

  private async cleanOrphanZapFiles() {
    try {
      const projects = await ProjectManager.getProjects();
      const validPaths = new Set(projects.map(p => p.filePath));
      const filesDir = this.context.filesDir;
      const files = fileIo.listFileSync(filesDir);
      for (const file of files) {
        if (file.endsWith('.zap')) {
          const fullPath = `${filesDir}/${file}`;
          if (!validPaths.has(fullPath)) {
            fileIo.unlinkSync(fullPath);
            console.info('删除孤立ZAP文件:', fullPath);
          }
        }
      }
    } catch (e) {
      console.warn('清理孤立ZAP文件失败:', e);
    }
  }

  build() {
    Column() {
      HdsTabs({
        controller: this.tabcont
      }) {
        TabContent() {
          ToolsContent()
        }
        .tabBar(
          BottomTabBarStyle.of({
            normal: new SymbolGlyphModifier($r('sys.symbol.more_fill'))
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              .fontColor([$r('sys.color.font_primary')]),
            selected: new SymbolGlyphModifier($r('sys.symbol.more_fill'))
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          }, $r('app.string.video_tools'))
            .labelStyle({ unselectedColor: $r('sys.color.font_primary') })
        )

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
                          { value: '导出ZAP文件', action: () => this.exportZapProject(project) },
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

            Row() {
              Text($r('app.string.stop_motion_animation'))
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.font_primary'))
                .layoutWeight(1)

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

              Button() {
                SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
                  .fontSize(24)
                  .fontColor([$r('sys.color.font_primary')])
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor($r('app.color.icon_button'))
              .border({ width: 1, color: 'rgba(255, 255, 255, 0.3)' })
              .shadow({ radius: 10, color: 'rgba(0, 0, 0, 0.2)' })
              .margin({ left: 8 })
              .bindMenu([
                { value: "导入 ZAP 文件", action: () => this.importZapProject() },
                { value: "关于", action: () => showAbout() }
              ])

              Button() {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(24)
                  .fontColor([Color.White])
              }
              .width(40)
              .height(40)
              .borderRadius(20)
              .backgroundColor($r('sys.color.brand'))
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
          }
          .width('100%')
          .height('100%')
        }
        .tabBar(
          BottomTabBarStyle.of({
            normal: new SymbolGlyphModifier($r('sys.symbol.template_fill'))
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              .fontColor([$r('sys.color.font_primary')]),
            selected: new SymbolGlyphModifier($r('sys.symbol.template_fill'))
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          }, $r('app.string.stop_motion_animation'))
            .labelStyle({ unselectedColor: $r('sys.color.font_primary') })
        )
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
      .animationDuration(0)
      .scrollable(false)
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

export interface ProjectMeta {
  id: string;
  name: string;
  filePath: string;
  lastModified: number;
  frameCount: number;
}

export class ProjectManager {
  private static context: common.UIAbilityContext;

  static init(context: common.UIAbilityContext) {
    ProjectManager.context = context;
  }

  private static getProjectsFilePath(): string {
    return ProjectManager.context.filesDir + '/projects.json';
  }

  static async getProjects(): Promise<ProjectMeta[]> {
    const filePath = ProjectManager.getProjectsFilePath();
    try {
      const stat = fileIo.statSync(filePath);
      if (stat.size === 0) return [];
      const data = fileIo.readTextSync(filePath);
      return JSON.parse(data) as ProjectMeta[];
    } catch (e) {
      return [];
    }
  }

  static async saveProjects(projects: ProjectMeta[]): Promise<void> {
    const filePath = ProjectManager.getProjectsFilePath();
    const json = JSON.stringify(projects, null, 2);
    const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(file.fd, json);
    fileIo.closeSync(file);
  }

  static async upsertProject(project: ProjectMeta): Promise<void> {
    let projects = await ProjectManager.getProjects();
    const index = projects.findIndex(p => p.id === project.id);
    if (index >= 0) {
      projects[index] = project;
    } else {
      projects.push(project);
    }
    await ProjectManager.saveProjects(projects);
  }

  static async deleteProject(id: string): Promise<void> {
    let projects = await ProjectManager.getProjects();
    const index = projects.findIndex(p => p.id === id);
    if (index < 0) return;
    const filePath = projects[index].filePath;
    try {
      fileIo.unlinkSync(filePath);
    } catch (e) {}
    projects.splice(index, 1);
    await ProjectManager.saveProjects(projects);
  }

  static sortProjects(projects: ProjectMeta[], by: 'name' | 'time'): ProjectMeta[] {
    const sorted = [...projects];
    if (by === 'name') {
      sorted.sort((a, b) => a.name.localeCompare(b.name));
    } else {
      sorted.sort((a, b) => b.lastModified - a.lastModified);
    }
    return sorted;
  }
}
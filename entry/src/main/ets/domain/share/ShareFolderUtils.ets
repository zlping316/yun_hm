import { LsLogger } from '../../common/log/LsLogger';
import { CloudFile } from '../../model/drive/CloudDriveModels';

const TAG: string = 'ShareFolderUtils';

export class ShareFolderUtils {
  static rootFolders(files: CloudFile[]): CloudFile[] {
    const folders = files.filter((file: CloudFile) =>
      file.type === 'folder' || file.type === '0');
    const sharedIndex = folders.findIndex((file: CloudFile) =>
      file.name === '来自分享' || file.name === '来自：分享');
    if (sharedIndex > 0) {
      const shared = folders[sharedIndex];
      folders.splice(sharedIndex, 1);
      folders.unshift(shared);
    }
    LsLogger.info(TAG, `Root folders prepared count=${folders.length}`);
    return folders;
  }
}

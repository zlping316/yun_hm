import { JsonFileStore } from '../storage/JsonFileStore';
import { TransferJob, TransferState } from '../../model/AppModels';

const FILE_NAME: string = 'transfer_jobs.json';
const HISTORY_FILE_NAME: string = 'transfer_history.json';

interface TransferHistoryItem {
  downloadUrl: string;
  key: string;
  completedAt: number;
}

export class TransferRepository {
  private readonly store: JsonFileStore;

  constructor(store: JsonFileStore) {
    this.store = store;
  }

  load(): TransferJob[] {
    const content = this.store.read(FILE_NAME);
    if (content.length === 0) {
      return [];
    }
    const jobs = JSON.parse(content) as TransferJob[];
    jobs.forEach((job: TransferJob) => {
      if (job.state === TransferState.DOWNLOADING || job.state === TransferState.CONVERTING ||
        job.state === TransferState.UPLOADING || job.state === TransferState.RESOLVING) {
        job.state = TransferState.QUEUED;
      }
    });
    return jobs;
  }

  save(jobs: TransferJob[]): void {
    this.store.write(FILE_NAME, JSON.stringify(jobs));
  }

  recordCompleted(job: TransferJob): void {
    const history = this.loadHistory();
    const exists = history.some((item: TransferHistoryItem) =>
      item.downloadUrl === job.downloadUrl);
    if (!exists) {
      history.push({
        downloadUrl: job.downloadUrl,
        key: job.key,
        completedAt: job.updatedAt
      });
      this.store.write(HISTORY_FILE_NAME, JSON.stringify(history));
    }
  }

  completedUrls(): Set<string> {
    const urls = new Set<string>();
    this.loadHistory().forEach((item: TransferHistoryItem) => urls.add(item.downloadUrl));
    return urls;
  }

  completedKeys(): Set<string> {
    const keys = new Set<string>();
    this.loadHistory().forEach((item: TransferHistoryItem) => {
      if (item.key.length > 0) {
        keys.add(item.key);
      }
    });
    return keys;
  }

  upsert(jobs: TransferJob[], changed: TransferJob): TransferJob[] {
    const index = jobs.findIndex((item: TransferJob) => item.jobId === changed.jobId);
    if (index >= 0) {
      jobs[index] = changed;
    } else {
      jobs.push(changed);
    }
    this.save(jobs);
    return jobs;
  }

  private loadHistory(): TransferHistoryItem[] {
    const content = this.store.read(HISTORY_FILE_NAME);
    return content.length > 0 ? JSON.parse(content) as TransferHistoryItem[] : [];
  }
}

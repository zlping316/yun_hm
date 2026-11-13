export interface RemuxTask {
  taskId: number;
  promise: Promise<number>;
}

export const startRemux: (inputPath: string, outputPath: string) => RemuxTask;
export const cancelRemux: (taskId: number) => void;

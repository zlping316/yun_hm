import { connection } from '@kit.NetworkKit';
import { LsLogger } from '../../common/log/LsLogger';

const TAG = 'NetworkResumeMonitor';

export interface NetworkMonitor {
  start(onAvailable: () => void): void;
  stop(): void;
}

export class DefaultNetworkMonitor implements NetworkMonitor {
  private readonly netConnection: connection.NetConnection = connection.createNetConnection();
  private registered: boolean = false;
  private onAvailable?: () => void;

  start(onAvailable: () => void): void {
    if (this.registered) {
      return;
    }
    this.onAvailable = onAvailable;
    this.netConnection.on('netAvailable', () => {
      LsLogger.info(TAG, 'Network available');
      this.onAvailable?.();
    });
    this.netConnection.register((error) => {
      if (error !== undefined) {
        LsLogger.warn(TAG, `Network listener registration failed: ${error.message}`);
        return;
      }
      this.registered = true;
    });
  }

  stop(): void {
    if (!this.registered) {
      return;
    }
    this.netConnection.unregister((error) => {
      if (error !== undefined) {
        LsLogger.warn(TAG, `Network listener removal failed: ${error.message}`);
        return;
      }
      this.registered = false;
      this.onAvailable = undefined;
    });
  }
}

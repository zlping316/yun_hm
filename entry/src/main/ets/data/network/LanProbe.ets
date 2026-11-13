import { socket } from '@kit.NetworkKit';
import { AppError, AppErrorCode } from '../../common/error/AppError';
import { Result } from '../../common/result/Result';
import { LsLogger } from '../../common/log/LsLogger';

const TAG = 'LanProbe';

export interface LanProbeResult {
  host: string;
  port: number;
  latencyMs: number;
}

export class LanProbe {
  async probe(host: string, port: number, timeoutMs: number): Promise<Result<LanProbeResult>> {
    const client: socket.TCPSocket = socket.constructTCPSocketInstance();
    const startedAt = Date.now();
    try {
      await client.connect({
        address: {
          address: host,
          family: 1,
          port: port
        },
        timeout: timeoutMs
      });
      const result: LanProbeResult = {
        host: host,
        port: port,
        latencyMs: Date.now() - startedAt
      };
      LsLogger.info(TAG, `LAN target reachable: ${host}:${port}, ${result.latencyMs}ms`);
      return Result.success<LanProbeResult>(result);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      LsLogger.warn(TAG, `LAN target unreachable: ${host}:${port}, ${detail}`);
      return Result.failure<LanProbeResult>(
        new AppError(AppErrorCode.NETWORK, `无法连接 ${host}:${port}`)
      );
    } finally {
      try {
        await client.close();
      } catch (_) {
        // The socket can already be closed after a failed connection.
      }
    }
  }
}

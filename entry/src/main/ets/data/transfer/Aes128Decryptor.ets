import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { AppError, AppErrorCode } from '../../common/error/AppError';

export class Aes128Decryptor {
  static async decrypt(data: ArrayBuffer, key: ArrayBuffer, iv: ArrayBuffer): Promise<ArrayBuffer> {
    if (key.byteLength !== 16 || iv.byteLength !== 16) {
      throw new AppError(AppErrorCode.PARSE, 'HLS AES-128 的 key 和 IV 必须为 16 字节');
    }
    try {
      const generator = cryptoFramework.createSymKeyGenerator('AES128');
      const symKey = generator.convertKeySync({ data: new Uint8Array(key) });
      const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
      const params: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: { data: new Uint8Array(iv) }
      };
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
      const output = await cipher.doFinal({ data: new Uint8Array(data) });
      return Aes128Decryptor.toArrayBuffer(output.data);
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      throw new AppError(AppErrorCode.PARSE, `HLS AES-128 解密失败: ${detail}`);
    }
  }

  static ivFrom(sequence: number, explicitIv: string): ArrayBuffer {
    if (explicitIv.length > 0) {
      const hex = explicitIv.toLowerCase().startsWith('0x') ? explicitIv.substring(2) : explicitIv;
      const normalized = hex.padStart(32, '0').substring(hex.length > 32 ? hex.length - 32 : 0);
      const bytes = new Uint8Array(16);
      for (let index = 0; index < 16; index++) {
        bytes[index] = parseInt(normalized.substring(index * 2, index * 2 + 2), 16);
      }
      return bytes.buffer;
    }
    const bytes = new Uint8Array(16);
    let value = sequence;
    for (let index = 15; index >= 0 && value > 0; index--) {
      bytes[index] = value & 0xff;
      value = Math.floor(value / 256);
    }
    return bytes.buffer;
  }

  private static toArrayBuffer(data: Uint8Array): ArrayBuffer {
    return data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
  }
}

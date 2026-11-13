import { AppError, AppErrorCode } from '../../common/error/AppError';
import { Result } from '../../common/result/Result';
import { WebAddress } from '../../model/AppModels';
import { AddressRepository } from './AddressRepository';
import { ParserRegistry } from './ParserRegistry';

export class AddressController {
  private readonly repository: AddressRepository;
  private readonly parsers: ParserRegistry;
  private addresses: WebAddress[] = [];

  constructor(repository: AddressRepository, parsers: ParserRegistry) {
    this.repository = repository;
    this.parsers = parsers;
    this.addresses = repository.load();
  }

  snapshot(): WebAddress[] {
    return this.addresses.map((address: WebAddress): WebAddress => this.copy(address));
  }

  add(type: string, subType: string, rawAddress: string): Result<WebAddress[]> {
    const validation = this.validate(type, subType, rawAddress);
    if (!validation.isSuccess || validation.value === undefined) {
      return Result.failure<WebAddress[]>(validation.error as AppError);
    }
    const address = validation.value;
    if (this.addresses.some((item: WebAddress) => item.address === address.address)) {
      return Result.failure<WebAddress[]>(
        new AppError(AppErrorCode.INVALID_INPUT, '已存在！')
      );
    }
    const newHost = this.hostOf(address.address);
    const sameType = this.addresses.find((item: WebAddress) => item.type === type);
    if (sameType !== undefined && newHost.length > 0 &&
      this.hostOf(sameType.address) !== newHost) {
      this.addresses.forEach((item: WebAddress) => {
        if (item.type === type) {
          item.address = this.replaceHost(item.address, newHost);
        }
      });
      return this.persist();
    }
    this.addresses.unshift(address);
    return this.persist();
  }

  update(originalAddress: string, type: string, subType: string, rawAddress: string):
    Result<WebAddress[]> {
    const validation = this.validate(type, subType, rawAddress);
    if (!validation.isSuccess || validation.value === undefined) {
      return Result.failure<WebAddress[]>(validation.error as AppError);
    }
    const index = this.addresses.findIndex((item: WebAddress) => item.address === originalAddress);
    if (index < 0) {
      return Result.failure<WebAddress[]>(
        new AppError(AppErrorCode.NOT_FOUND, '待编辑地址不存在')
      );
    }
    const duplicate = this.addresses.find((item: WebAddress, itemIndex: number) =>
      itemIndex !== index && item.address === validation.value?.address);
    if (duplicate !== undefined) {
      return Result.failure<WebAddress[]>(
        new AppError(AppErrorCode.INVALID_INPUT, '该地址已存在')
      );
    }
    validation.value.selected = this.addresses[index].selected;
    this.addresses[index] = validation.value;
    return this.persist();
  }

  remove(address: string): WebAddress[] {
    this.addresses = this.addresses.filter((item: WebAddress) => item.address !== address);
    this.repository.save(this.addresses);
    return this.snapshot();
  }

  setSelected(address: string, selected: boolean): WebAddress[] {
    const item = this.addresses.find((value: WebAddress) => value.address === address);
    if (item !== undefined) {
      item.selected = selected;
      this.repository.save(this.addresses);
    }
    return this.snapshot();
  }

  selectType(type: string, selected: boolean): WebAddress[] {
    this.addresses.forEach((item: WebAddress) => {
      if (item.type === type) {
        item.selected = selected;
      }
    });
    this.repository.save(this.addresses);
    return this.snapshot();
  }

  reload(): WebAddress[] {
    this.addresses = this.repository.load();
    return this.snapshot();
  }

  private validate(type: string, subType: string, rawAddress: string): Result<WebAddress> {
    if (!/^[0-8]$/.test(type)) {
      return Result.failure<WebAddress>(
        new AppError(AppErrorCode.INVALID_INPUT, '网址类型无效')
      );
    }
    const address = rawAddress.trim();
    const name = subType.trim();
    if (!/^https?:\/\/[^/\s]+/i.test(address)) {
      return Result.failure<WebAddress>(
        new AppError(AppErrorCode.INVALID_INPUT, '请输入有效的 HTTP(S) 地址')
      );
    }
    if (name.length === 0) {
      return Result.failure<WebAddress>(
        new AppError(AppErrorCode.INVALID_INPUT, '请输入地址名称')
      );
    }
    return Result.success<WebAddress>({
      type: type,
      subType: name,
      address: address,
      selected: false
    });
  }

  private hostOf(address: string): string {
    const matched = /^https?:\/\/([^/]+)/i.exec(address);
    return matched?.[1] ?? '';
  }

  private replaceHost(address: string, host: string): string {
    return address.replace(/^(https?:\/\/)[^/]+/i, `$1${host}`);
  }

  private persist(): Result<WebAddress[]> {
    this.repository.save(this.addresses);
    return Result.success<WebAddress[]>(this.snapshot());
  }

  private copy(address: WebAddress): WebAddress {
    const result: WebAddress = {
      type: address.type,
      subType: address.subType,
      address: address.address,
      selected: address.selected
    };
    return result;
  }
}

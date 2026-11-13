import { JsonFileStore } from '../../data/storage/JsonFileStore';
import { WebAddress } from '../../model/AppModels';

const FILE_NAME: string = 'web_addresses.json';

export class AddressRepository {
  private readonly store: JsonFileStore;

  constructor(store: JsonFileStore) {
    this.store = store;
  }

  load(): WebAddress[] {
    const content = this.store.read(FILE_NAME);
    if (content.length === 0) {
      return [];
    }
    const values = JSON.parse(content) as WebAddress[];
    const addresses: WebAddress[] = [];
    values.forEach((value: WebAddress) => {
      if (value.address.length > 0 &&
        addresses.find((item: WebAddress) => item.address === value.address) === undefined) {
        addresses.push({
          type: value.type,
          subType: value.subType,
          address: value.address,
          selected: value.selected ?? false
        });
      }
    });
    return addresses;
  }

  save(addresses: WebAddress[]): void {
    this.store.write(FILE_NAME, JSON.stringify(addresses));
  }
}

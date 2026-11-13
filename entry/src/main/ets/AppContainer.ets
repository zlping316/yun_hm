import { common } from '@kit.AbilityKit';
import { PreferenceStore } from './data/storage/PreferenceStore';
import { SettingsRepository } from './config/SettingsRepository';
import { AppSettings, Credentials } from './config/AppSettings';
import { HttpClient } from './data/network/HttpClient';
import { ProviderRegistry } from './domain/provider/ProviderRegistry';
import { AliyunDriveProvider } from './domain/provider/aliyun/AliyunDriveProvider';
import { QuarkDriveProvider } from './domain/provider/quark/QuarkDriveProvider';
import { JsonFileStore } from './data/storage/JsonFileStore';
import { ShareRepository } from './domain/share/ShareRepository';
import { ShareController } from './domain/share/ShareController';
import { CloudProviderType } from './model/AppModels';
import { ParserRegistry } from './domain/parser/ParserRegistry';
import { TParser } from './domain/parser/impl/TParser';
import { AParser } from './domain/parser/impl/AParser';
import { HuaDuParser } from './domain/parser/impl/HuaDuParser';
import { F404Parser } from './domain/parser/impl/F404Parser';
import { MadouParser } from './domain/parser/impl/MadouParser';
import { UUParser } from './domain/parser/impl/UUParser';
import { TransferRepository } from './data/transfer/TransferRepository';
import { DefaultTransferExecutor } from './data/transfer/DefaultTransferExecutor';
import { TransferBackgroundService } from './domain/transfer/TransferBackgroundService';
import { TransferQueueController } from './domain/transfer/TransferQueueController';
import { DefaultNetworkMonitor, NetworkMonitor } from './data/network/NetworkResumeMonitor';
import { AddressRepository } from './domain/parser/AddressRepository';
import { AddressController } from './domain/parser/AddressController';
import { ParsingController } from './domain/parser/ParsingController';
import { CloudBackupController } from './domain/backup/CloudBackupController';
import { PendingShareSelection } from './domain/share/PendingShareSelection';
import { ShareListBackupController } from './domain/share/ShareListBackupController';

export class AppContainer {
  private static instance?: AppContainer;
  readonly preferenceStore: PreferenceStore = new PreferenceStore();
  readonly settingsRepository: SettingsRepository = new SettingsRepository(this.preferenceStore);
  readonly httpClient: HttpClient = new HttpClient();
  readonly jsonFileStore: JsonFileStore = new JsonFileStore();
  settings?: AppSettings;
  credentials?: Credentials;
  providerRegistry?: ProviderRegistry;
  parserRegistry?: ParserRegistry;
  transferRepository?: TransferRepository;
  transferExecutor?: DefaultTransferExecutor;
  transferQueue?: TransferQueueController;
  addressController?: AddressController;
  parsingController?: ParsingController;
  cloudBackupController?: CloudBackupController;
  shareListBackupController?: ShareListBackupController;
  readonly pendingShareSelection: PendingShareSelection = new PendingShareSelection();
  networkMonitor?: NetworkMonitor;
  private initializePromise?: Promise<void>;

  static getInstance(): AppContainer {
    if (AppContainer.instance === undefined) {
      AppContainer.instance = new AppContainer();
    }
    return AppContainer.instance;
  }

  async initialize(context: common.Context): Promise<void> {
    if (this.initializePromise === undefined) {
      this.initializePromise = this.initializeInternal(context);
    }
    await this.initializePromise;
  }

  async waitUntilReady(): Promise<void> {
    if (this.initializePromise !== undefined) {
      await this.initializePromise;
    }
  }

  createShareController(type: CloudProviderType): ShareController {
    if (this.providerRegistry === undefined) {
      throw new Error('AppContainer is not initialized');
    }
    return new ShareController(
      this.providerRegistry.get(type),
      new ShareRepository(this.jsonFileStore, type)
    );
  }

  private async initializeInternal(context: common.Context): Promise<void> {
    await this.preferenceStore.initialize(context);
    this.jsonFileStore.initialize(context);
    this.settings = await this.settingsRepository.loadSettings();
    this.credentials = await this.settingsRepository.loadCredentials();
    this.providerRegistry = new ProviderRegistry(
      new AliyunDriveProvider(this.httpClient, this.settingsRepository, this.settings),
      new QuarkDriveProvider(this.httpClient, this.settingsRepository, this.settings)
    );
    this.parserRegistry = new ParserRegistry([
      new TParser(),
      new AParser(this.httpClient),
      new HuaDuParser(),
      new F404Parser(),
      new MadouParser(),
      new UUParser(this.httpClient, this.settingsRepository)
    ]);
    this.transferRepository = new TransferRepository(this.jsonFileStore);
    this.cloudBackupController = new CloudBackupController(
      this.jsonFileStore,
      this.providerRegistry,
      this.settings,
      this.settingsRepository,
      this.httpClient
    );
    this.transferExecutor = new DefaultTransferExecutor(
      context.filesDir,
      this.settings,
      this.providerRegistry,
      this.httpClient
    );
    this.transferQueue = new TransferQueueController(
      this.transferRepository,
      this.transferExecutor,
      new TransferBackgroundService(context)
    );
    this.transferQueue.setBatchCompletedHandler(
      async (provider: CloudProviderType): Promise<void> => {
        const result = await this.cloudBackupController?.backup(provider);
        if (result !== undefined && !result.isSuccess) {
          throw result.error ?? new Error('同步日志备份失败');
        }
      }
    );
    this.transferQueue.initialize(this.settings.autoResumeOnNetwork);
    this.addressController = new AddressController(
      new AddressRepository(this.jsonFileStore),
      this.parserRegistry
    );
    this.parsingController = new ParsingController(
      this.parserRegistry,
      this.httpClient,
      this.transferRepository,
      this.transferQueue
    );
    this.shareListBackupController = new ShareListBackupController(
      this.jsonFileStore,
      this.providerRegistry,
      this.settings,
      this.httpClient
    );
    if (this.settings.autoResumeOnNetwork) {
      this.networkMonitor = new DefaultNetworkMonitor();
      this.networkMonitor.start(() => this.transferQueue?.start());
    }
  }
}

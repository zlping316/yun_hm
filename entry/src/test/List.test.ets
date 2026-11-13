import localUnitTest from './LocalUnit.test';
import parserTest from './Parser.test';
import transferTest from './Transfer.test';
import syncWorkflowTest from './SyncWorkflow.test';
import cloudDriveParityTest from './CloudDriveParity.test';
import searchSourceTest from './SearchSource.test';

export default function testsuite() {
  localUnitTest();
  parserTest();
  transferTest();
  syncWorkflowTest();
  cloudDriveParityTest();
  searchSourceTest();
}

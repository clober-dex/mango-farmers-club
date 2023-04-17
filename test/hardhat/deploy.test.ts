import { deployments } from 'hardhat'
import { expect } from 'chai'

describe('Test Deploy Script', () => {
  it('should deploy properly', async () => {
    await deployments.fixture()
    const deployedFixtures = await deployments.all()
    const expectedUpgradeableContracts: string[] = ['MangoPublicRegistration']
    const expectedNonUpgradeableContracts: string[] = []
    if (expectedUpgradeableContracts.length > 0) {
      expect(Object.keys(deployedFixtures).length).to.be.equal(
        expectedUpgradeableContracts.length * 3 +
          expectedNonUpgradeableContracts.length +
          1,
      )
      expect('DefaultProxyAdmin' in deployedFixtures)
    }
    for (const expectedUpgradeableContract of expectedUpgradeableContracts) {
      expect(expectedUpgradeableContract in deployedFixtures).to.be.true
      expect(`${expectedUpgradeableContract}_Proxy` in deployedFixtures).to.be
        .true
      expect(
        `${expectedUpgradeableContract}_Implementation` in deployedFixtures,
      ).to.be.true
    }
    for (const expectedNonUpgradeableContract of expectedNonUpgradeableContracts) {
      expect(expectedNonUpgradeableContract in deployedFixtures).to.be.true
    }
  })
})

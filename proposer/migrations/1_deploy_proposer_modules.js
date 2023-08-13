const { deployTruffleContract } = require("@gnosis.pm/singleton-deployer-truffle")
const ProposerExecution = artifacts.require("ProposerExecution")

// Safe singleton factory was deployed using eip155 transaction
// If the network enforces EIP155, then the safe singleton factory should be used
// More at https://github.com/gnosis/safe-singleton-factory
const USE_SAFE_SINGLETON_FACTORY = process.env.USE_SAFE_SINGLETON_FACTORY === "true"

module.exports = function (deployer) {
  deployer.then(async () => {
    await deployTruffleContract(web3, ProposerExecution, USE_SAFE_SINGLETON_FACTORY)
  })
}

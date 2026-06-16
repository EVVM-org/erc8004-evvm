.PHONY: deployUserValidatorManual deployUserValidator deployUserValidatorPreRegistrated

TESTNET_ARGS := --rpc-url $(RPC_URL_TESTNET) \
					 --account defaultKey \
					 --broadcast \
					 --verify \
					 --etherscan-api-key $(ETHERSCAN_API)

deployUserValidatorManual:
	@forge clean
	@echo "Deploying UserValidatorManual to testnet"
	@forge script script/DeployUserValidatorManual.s.sol:DeployUserValidatorManual $(TESTNET_ARGS)

deployUserValidator:
	@forge clean
	@echo "Deploying UserValidator to testnet"
	@forge script script/DeployUserValidator.s.sol:DeployUserValidator $(TESTNET_ARGS)

deployUserValidatorPreRegistrated:
	@forge clean
	@echo "Deploying UserValidatorPreRegistrated to testnet"
	@forge script script/DeployUserValidatorPreRegistrated.s.sol:DeployUserValidatorPreRegistrated $(TESTNET_ARGS)
